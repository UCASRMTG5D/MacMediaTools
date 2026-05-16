import AVFoundation
import Foundation

struct VideoDisplayInfo: Sendable {
	let displaySize: CGSize
	let durationSeconds: Double
}

enum VideoScaleMode: String, CaseIterable, Identifiable {
	case stretch = "拉伸到目标分辨率（会改变比例）"
	case aspectFit = "保持比例加黑边"

	var id: String { rawValue }
}

enum VideoToolkitError: LocalizedError {
	case noVideoTrack
	case exportFailed(String)
	case incompatibleVideos(String)

	var errorDescription: String? {
		switch self {
		case .noVideoTrack:
			return "未找到视频轨道"
		case .exportFailed(let message):
			return "导出失败：\(message)"
		case .incompatibleVideos(let message):
			return message
		}
	}
}

enum VideoToolkit {
	static func readDisplayInfo(url: URL) async throws -> VideoDisplayInfo {
		let asset = AVURLAsset(url: url)
		let duration = try await asset.load(.duration)
		guard let track = try await asset.loadTracks(withMediaType: .video).first else {
			throw VideoToolkitError.noVideoTrack
		}
		let naturalSize = try await track.load(.naturalSize)
		let preferredTransform = try await track.load(.preferredTransform)
		let display = naturalSize.applying(preferredTransform)
		let displaySize = CGSize(width: abs(display.width), height: abs(display.height))
		return VideoDisplayInfo(displaySize: displaySize, durationSeconds: duration.seconds)
	}

	/// 视频尺寸修改：输出为 MP4(H.264)+AAC
	static func exportResized(
		inputURL: URL,
		outputURL: URL,
		targetSize: CGSize,
		scaleMode: VideoScaleMode
	) async throws {
		let asset = AVURLAsset(url: inputURL)
		guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
			throw VideoToolkitError.noVideoTrack
		}

		// 基于视频原始显示尺寸计算缩放
		let naturalSize = try await videoTrack.load(.naturalSize)
		let preferredTransform = try await videoTrack.load(.preferredTransform)
		let display = naturalSize.applying(preferredTransform)
		let displaySize = CGSize(width: abs(display.width), height: abs(display.height))

		let instruction = AVMutableVideoCompositionInstruction()
		instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)

		let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
		let t = makeTransform(
			preferredTransform: preferredTransform,
			sourceDisplaySize: displaySize,
			targetSize: targetSize,
			scaleMode: scaleMode,
			cropRectInTargetSpace: nil
		)
		layerInstruction.setTransform(t, at: .zero)
		instruction.layerInstructions = [layerInstruction]

		let videoComposition = AVMutableVideoComposition()
		videoComposition.instructions = [instruction]
		videoComposition.renderSize = targetSize
		videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

		try await export(
			asset: asset,
			outputURL: outputURL,
			videoComposition: videoComposition
		)
	}

	/// 视频裁剪：cropRect 以“显示方向(已应用preferredTransform)的坐标系”为准
	static func exportCropped(
		inputURL: URL,
		outputURL: URL,
		cropRect: CGRect
	) async throws {
		let asset = AVURLAsset(url: inputURL)
		guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
			throw VideoToolkitError.noVideoTrack
		}

		let naturalSize = try await videoTrack.load(.naturalSize)
		let preferredTransform = try await videoTrack.load(.preferredTransform)
		let display = naturalSize.applying(preferredTransform)
		let displaySize = CGSize(width: abs(display.width), height: abs(display.height))

		guard cropRect.width > 2, cropRect.height > 2 else {
			throw VideoToolkitError.exportFailed("裁剪区域太小")
		}

		// 将视频先转正，再把裁剪区域移动到(0,0)
		let instruction = AVMutableVideoCompositionInstruction()
		instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)

		let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
		let t = preferredTransform.concatenating(
			CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y)
		)
		layerInstruction.setTransform(t, at: .zero)
		instruction.layerInstructions = [layerInstruction]

		let videoComposition = AVMutableVideoComposition()
		videoComposition.instructions = [instruction]
		videoComposition.renderSize = cropRect.size
		videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

		try await export(
			asset: asset,
			outputURL: outputURL,
			videoComposition: videoComposition
		)
	}

	/// 多视频拼接（MVP：要求分辨率一致；输出 MP4/H.264+AAC）
	static func exportConcatenated(
		inputURLs: [URL],
		outputURL: URL
	) async throws {
		guard inputURLs.count >= 2 else { return }

		let assets = inputURLs.map { AVURLAsset(url: $0) }
		let firstInfo = try await readDisplayInfo(url: inputURLs[0])

		for (idx, url) in inputURLs.enumerated() where idx > 0 {
			let info = try await readDisplayInfo(url: url)
			if abs(info.displaySize.width - firstInfo.displaySize.width) > 0.5 ||
				abs(info.displaySize.height - firstInfo.displaySize.height) > 0.5 {
				throw VideoToolkitError.incompatibleVideos("拼接失败：当前MVP要求所有视频分辨率一致（第\(idx + 1)个视频与第1个不一致）。")
			}
		}

		let composition = AVMutableComposition()
		guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
			throw VideoToolkitError.exportFailed("无法创建合成视频轨道")
		}
		let compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

		var cursor = CMTime.zero
		for asset in assets {
			guard let vTrack = try await asset.loadTracks(withMediaType: .video).first else {
				throw VideoToolkitError.noVideoTrack
			}
			let timeRange = CMTimeRange(start: .zero, duration: asset.duration)
			try compVideoTrack.insertTimeRange(timeRange, of: vTrack, at: cursor)
			if let aTrack = try await asset.loadTracks(withMediaType: .audio).first, let compAudioTrack {
				try? compAudioTrack.insertTimeRange(timeRange, of: aTrack, at: cursor)
			}
			cursor = cursor + asset.duration
		}

		// 拼接后统一转正（简单处理：使用第一段的 preferredTransform）
		let firstTrack = try await assets[0].loadTracks(withMediaType: .video).first!
		let preferredTransform = try await firstTrack.load(.preferredTransform)

		let instruction = AVMutableVideoCompositionInstruction()
		instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)

		let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)
		layerInstruction.setTransform(preferredTransform, at: .zero)
		instruction.layerInstructions = [layerInstruction]

		let videoComposition = AVMutableVideoComposition()
		videoComposition.instructions = [instruction]
		videoComposition.renderSize = firstInfo.displaySize
		videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

		try await export(
			asset: composition,
			outputURL: outputURL,
			videoComposition: videoComposition
		)
	}

	// MARK: - Private

	private static func export(
		asset: AVAsset,
		outputURL: URL,
		videoComposition: AVVideoComposition?
	) async throws {
		try? FileManager.default.removeItem(at: outputURL)

		guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
			throw VideoToolkitError.exportFailed("无法创建导出会话")
		}
		exportSession.outputURL = outputURL
		exportSession.outputFileType = .mp4
		exportSession.shouldOptimizeForNetworkUse = true
		if let videoComposition {
			exportSession.videoComposition = videoComposition
		}

		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			exportSession.exportAsynchronously {
				switch exportSession.status {
				case .completed:
					continuation.resume()
				case .failed:
					continuation.resume(throwing: VideoToolkitError.exportFailed(exportSession.error?.localizedDescription ?? "未知错误"))
				case .cancelled:
					continuation.resume(throwing: VideoToolkitError.exportFailed("已取消"))
				default:
					continuation.resume(throwing: VideoToolkitError.exportFailed("导出状态异常：\(exportSession.status.rawValue)"))
				}
			}
		}
	}

	/// 说明：
	/// - preferredTransform 负责“转正/处理旋转信息”
	/// - scaleMode 决定是否保持比例
	/// - cropRectInTargetSpace：用于裁剪时将目标区域平移到(0,0)（以显示方向坐标系为准）
	private static func makeTransform(
		preferredTransform: CGAffineTransform,
		sourceDisplaySize: CGSize,
		targetSize: CGSize,
		scaleMode: VideoScaleMode,
		cropRectInTargetSpace: CGRect?
	) -> CGAffineTransform {
		let sx = targetSize.width / max(sourceDisplaySize.width, 1)
		let sy = targetSize.height / max(sourceDisplaySize.height, 1)

		let scale: CGAffineTransform
		let translate: CGAffineTransform

		switch scaleMode {
		case .stretch:
			scale = CGAffineTransform(scaleX: sx, y: sy)
			translate = .identity
		case .aspectFit:
			let s = min(sx, sy)
			let dx = (targetSize.width - sourceDisplaySize.width * s) / 2
			let dy = (targetSize.height - sourceDisplaySize.height * s) / 2
			scale = CGAffineTransform(scaleX: s, y: s)
			translate = CGAffineTransform(translationX: dx, y: dy)
		}

		let cropTranslate: CGAffineTransform
		if let crop = cropRectInTargetSpace {
			cropTranslate = CGAffineTransform(translationX: -crop.origin.x, y: -crop.origin.y)
		} else {
			cropTranslate = .identity
		}

		// 应用顺序：先转正，再裁剪平移，再缩放，再（可选）居中平移
		return preferredTransform
			.concatenating(cropTranslate)
			.concatenating(scale)
			.concatenating(translate)
	}
}
