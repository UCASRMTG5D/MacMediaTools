import AVFoundation
import Foundation
import ImageIO

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
		if url.pathExtension.lowercased() == "gif" {
			return try readGIFDisplayInfo(url: url)
		}

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

	private static func readGIFDisplayInfo(url: URL) throws -> VideoDisplayInfo {
		guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
			throw VideoToolkitError.noVideoTrack
		}
		let frameCount = CGImageSourceGetCount(source)
		guard frameCount > 0 else {
			throw VideoToolkitError.noVideoTrack
		}

		let firstProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
		let width = firstProps?[kCGImagePropertyPixelWidth as String] as? Int ?? 0
		let height = firstProps?[kCGImagePropertyPixelHeight as String] as? Int ?? 0

		var totalDuration: Double = 0
		for i in 0..<frameCount {
			if let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
			   let gifDict = props[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
				let delay = gifDict[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double
					?? gifDict[kCGImagePropertyGIFDelayTime as String] as? Double
					?? 0.1
				totalDuration += max(delay, 0.02)
			} else {
				totalDuration += 0.1
			}
		}

		return VideoDisplayInfo(
			displaySize: CGSize(width: width, height: height),
			durationSeconds: totalDuration
		)
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

	/// 裁剪 + 尺寸调整合并导出（支持只裁剪、只调整、二者都做）
	/// - Parameters:
	///   - cropRect: 裁剪区域（显示坐标系），nil = 不裁剪
	///   - targetSize: 目标输出尺寸，nil = 使用裁剪后/原始尺寸
	static func exportCroppedAndResized(
		inputURL: URL,
		outputURL: URL,
		cropRect: CGRect?,
		targetSize: CGSize?,
		scaleMode: VideoScaleMode
	) async throws {
		guard cropRect != nil || targetSize != nil else {
			throw VideoToolkitError.exportFailed("请至少启用裁剪或尺寸调整中的一项")
		}

		let asset = AVURLAsset(url: inputURL)
		guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
			throw VideoToolkitError.noVideoTrack
		}

		let naturalSize = try await videoTrack.load(.naturalSize)
		let preferredTransform = try await videoTrack.load(.preferredTransform)
		let display = naturalSize.applying(preferredTransform)
		let displaySize = CGSize(width: abs(display.width), height: abs(display.height))

		let crop = cropRect ?? CGRect(origin: .zero, size: displaySize)
		let renderSize = targetSize ?? crop.size

		guard crop.width > 2, crop.height > 2 else {
			throw VideoToolkitError.exportFailed("裁剪区域太小")
		}

		let instruction = AVMutableVideoCompositionInstruction()
		instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)

		let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)

		if targetSize == nil {
			// 纯裁剪：仅旋转 + 平移裁剪区域到原点
			let t = preferredTransform.concatenating(
				CGAffineTransform(translationX: -crop.origin.x, y: -crop.origin.y)
			)
			layerInstruction.setTransform(t, at: .zero)
		} else {
			// 裁剪 + 调整 或 纯调整：使用 makeTransform
			let t = makeTransform(
				preferredTransform: preferredTransform,
				sourceDisplaySize: displaySize,
				targetSize: renderSize,
				scaleMode: scaleMode,
				cropRectInTargetSpace: cropRect
			)
			layerInstruction.setTransform(t, at: .zero)
		}
		instruction.layerInstructions = [layerInstruction]

		let videoComposition = AVMutableVideoComposition()
		videoComposition.instructions = [instruction]
		videoComposition.renderSize = renderSize
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
		outputURL: URL,
		targetSize: CGSize? = nil
	) async throws {
		guard inputURLs.count >= 2 else { throw VideoToolkitError.exportFailed("至少需要2个视频才能拼接") }

		let assets = inputURLs.map { AVURLAsset(url: $0) }

		// Read display info for all videos
		var videoInfos: [VideoDisplayInfo] = []
		for url in inputURLs {
			videoInfos.append(try await readDisplayInfo(url: url))
		}

		let renderSize: CGSize
		if let target = targetSize {
			renderSize = target
		} else {
			let firstInfo = videoInfos[0]
			for (idx, info) in videoInfos.enumerated() where idx > 0 {
				if abs(info.displaySize.width - firstInfo.displaySize.width) > 0.5 ||
					abs(info.displaySize.height - firstInfo.displaySize.height) > 0.5 {
					throw VideoToolkitError.incompatibleVideos("拼接失败：所有视频分辨率必须一致（第\(idx + 1)个视频与第1个不一致）。")
				}
			}
			renderSize = firstInfo.displaySize
		}

		let composition = AVMutableComposition()
		guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
			throw VideoToolkitError.exportFailed("无法创建合成视频轨道")
		}
		let compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

		var instructions: [AVMutableVideoCompositionInstruction] = []
		var cursor = CMTime.zero

		for (idx, asset) in assets.enumerated() {
			guard let vTrack = try await asset.loadTracks(withMediaType: .video).first else {
				throw VideoToolkitError.noVideoTrack
			}
			let timeRange = CMTimeRange(start: .zero, duration: asset.duration)
			try compVideoTrack.insertTimeRange(timeRange, of: vTrack, at: cursor)

			if let aTrack = try await asset.loadTracks(withMediaType: .audio).first, let compAudioTrack {
				try? compAudioTrack.insertTimeRange(timeRange, of: aTrack, at: cursor)
			}

			let naturalSize = try await vTrack.load(.naturalSize)
			let preferredTransform = try await vTrack.load(.preferredTransform)

			if targetSize != nil {
				let display = naturalSize.applying(preferredTransform)
				let displaySize = CGSize(width: abs(display.width), height: abs(display.height))
				let tx = (renderSize.width - displaySize.width) / 2
				let ty = (renderSize.height - displaySize.height) / 2

				let instruction = AVMutableVideoCompositionInstruction()
				instruction.timeRange = CMTimeRange(start: cursor, duration: asset.duration)

				let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)
				let t = preferredTransform.concatenating(CGAffineTransform(translationX: tx, y: ty))
				layerInstruction.setTransform(t, at: cursor)
				instruction.layerInstructions = [layerInstruction]
				instructions.append(instruction)
			}

			cursor = cursor + asset.duration
		}

		let videoComposition = AVMutableVideoComposition()

		if targetSize != nil {
			videoComposition.instructions = instructions
		} else {
			let firstTrack = try await assets[0].loadTracks(withMediaType: .video).first!
			let firstTransform = try await firstTrack.load(.preferredTransform)
			let instruction = AVMutableVideoCompositionInstruction()
			instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
			let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)
			layerInstruction.setTransform(firstTransform, at: .zero)
			instruction.layerInstructions = [layerInstruction]
			videoComposition.instructions = [instruction]
		}

		videoComposition.renderSize = renderSize
		videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

		try await export(
			asset: composition,
			outputURL: outputURL,
			videoComposition: videoComposition
		)
	}

	// MARK: - Image Processing

	static func exportImageCroppedAndResized(
		inputURL: URL,
		outputURL: URL,
		cropRect: CGRect?,
		targetSize: CGSize?,
		scaleMode: VideoScaleMode
	) async throws {
		guard cropRect != nil || targetSize != nil else {
			throw VideoToolkitError.exportFailed("请至少启用裁剪或尺寸调整中的一项")
		}

		guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil) else {
			throw VideoToolkitError.exportFailed("无法读取图片文件")
		}
		guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
			throw VideoToolkitError.exportFailed("无法解码图片")
		}

		let imageSize = CGSize(width: image.width, height: image.height)
		let crop = cropRect ?? CGRect(origin: .zero, size: imageSize)
		guard crop.width > 2, crop.height > 2 else {
			throw VideoToolkitError.exportFailed("裁剪区域太小")
		}

		let cropped: CGImage
		if let cropRect, cropRect != CGRect(origin: .zero, size: imageSize) {
			guard let c = image.cropping(to: crop) else {
				throw VideoToolkitError.exportFailed("裁剪失败")
			}
			cropped = c
		} else {
			cropped = image
		}

		let finalImage: CGImage
		if let target = targetSize {
			guard let resized = scaleCGImageStatic(cropped, to: target, scaleMode: scaleMode) else {
				throw VideoToolkitError.exportFailed("缩放失败")
			}
			finalImage = resized
		} else {
			finalImage = cropped
		}

		let uti = outputUTI(for: outputURL)
		guard let dest = CGImageDestinationCreateWithURL(outputURL as CFURL, uti, 1, nil) else {
			throw VideoToolkitError.exportFailed("无法创建输出文件")
		}
		CGImageDestinationAddImage(dest, finalImage, nil)
		guard CGImageDestinationFinalize(dest) else {
			throw VideoToolkitError.exportFailed("写入图片失败")
		}
	}

	private static func outputUTI(for url: URL) -> CFString {
		switch url.pathExtension.lowercased() {
		case "jpg", "jpeg": return UTType.jpeg.identifier as CFString
		case "png": return UTType.png.identifier as CFString
		case "tiff", "tif": return UTType.tiff.identifier as CFString
		case "bmp": return UTType.bmp.identifier as CFString
		case "gif": return UTType.gif.identifier as CFString
		case "heic": return UTType.heic.identifier as CFString
		default: return UTType.png.identifier as CFString
		}
	}

	static func scaleCGImageStatic(_ image: CGImage, to targetSize: CGSize, scaleMode: VideoScaleMode) -> CGImage? {
		let srcSize = CGSize(width: image.width, height: image.height)
		let sx = targetSize.width / max(srcSize.width, 1)
		let sy = targetSize.height / max(srcSize.height, 1)

		var drawRect: CGRect
		switch scaleMode {
		case .stretch:
			drawRect = CGRect(origin: .zero, size: targetSize)
		case .aspectFit:
			let s = min(sx, sy)
			let fitSize = CGSize(width: srcSize.width * s, height: srcSize.height * s)
			drawRect = CGRect(
				x: (targetSize.width - fitSize.width) / 2,
				y: (targetSize.height - fitSize.height) / 2,
				width: fitSize.width,
				height: fitSize.height
			)
		}

		let cs = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
		let bpc = image.bitsPerComponent
		let bitmapInfo = image.bitmapInfo

		guard let ctx = CGContext(
			data: nil,
			width: Int(targetSize.width),
			height: Int(targetSize.height),
			bitsPerComponent: bpc,
			bytesPerRow: 0,
			space: cs,
			bitmapInfo: bitmapInfo.rawValue
		) else { return nil }

		ctx.interpolationQuality = .high
		ctx.draw(image, in: drawRect)
		return ctx.makeImage()
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
