import AVFoundation
import CoreGraphics
import ImageIO
import Foundation

// MARK: - CanvasElementInput

/// Service 层使用的画布元素输入模型（从 CanvasElement 转换）
struct CanvasElementInput: Sendable {
	let sourceURL: URL
	let mediaType: CanvasMediaType
	let displaySize: CGSize
	let duration: Double
	let position: CGPoint
	let effectiveSize: CGSize
	let cropRect: CGRect?
	let volume: Double
	let zIndex: Int
}

// MARK: - Errors

enum SpatialCanvasError: LocalizedError {
	case failedToLoadAsset(String)
	case failedToCreateWriter(String)
	case failedToExportVideo(String)
	case failedToExportAudio(String)
	case failedToMerge(String)
	case noElements
	case invalidCanvasSize

	var errorDescription: String? {
		switch self {
		case .failedToLoadAsset(let msg):  return "无法加载媒体文件：\(msg)"
		case .failedToCreateWriter(let msg): return "无法创建导出器：\(msg)"
		case .failedToExportVideo(let msg):  return "视频导出失败：\(msg)"
		case .failedToExportAudio(let msg):  return "音频导出失败：\(msg)"
		case .failedToMerge(let msg):        return "音视频合并失败：\(msg)"
		case .noElements:                    return "没有待导出的元素"
		case .invalidCanvasSize:             return "画布尺寸无效"
		}
	}
}

// MARK: - SpatialCanvasToolkit

actor SpatialCanvasToolkit {
	static let shared = SpatialCanvasToolkit()
	private init() {}

	// MARK: - Public API

	/// 导出一幅画布为 MP4 视频
	/// - Parameters:
	///   - inputs: 画布元素列表（已按 zIndex 排序）
	///   - canvasSize: 画布尺寸（像素）
	///   - outputURL: 输出文件 URL
	///   - frameRate: 帧率（默认 30）
	///   - progressHandler: 进度回调（0.0 ~ 1.0）
	func exportCanvas(
		inputs: [CanvasElementInput],
		canvasSize: CGSize,
		outputURL: URL,
		frameRate: Int = 30,
		progressHandler: (@Sendable (Double) -> Void)? = nil
	) async throws {
		guard !inputs.isEmpty else { throw SpatialCanvasError.noElements }
		guard canvasSize.width > 0, canvasSize.height > 0 else { throw SpatialCanvasError.invalidCanvasSize }

		let tempDir = FileManager.default.temporaryDirectory
		let tempVideoURL = tempDir.appendingPathComponent("canvas_video_\(UUID().uuidString).mp4")
		let tempAudioURL = tempDir.appendingPathComponent("canvas_audio_\(UUID().uuidString).m4a")

		defer {
			try? FileManager.default.removeItem(at: tempVideoURL)
			try? FileManager.default.removeItem(at: tempAudioURL)
		}

		// Step 1: 按 zIndex 排序
		let sorted = inputs.sorted { $0.zIndex < $1.zIndex }

		// Step 2: 计算总时长（所有元素中最大时长 + 1s 缓冲）
		let maxDuration = sorted.map(\.duration).max() ?? 3.0
		let totalDuration = max(maxDuration, 1.0) + 1.0

		// Step 3: 渲染视频
		try await renderVideo(
			inputs: sorted,
			canvasSize: canvasSize,
			totalDuration: totalDuration,
			frameRate: frameRate,
			outputURL: tempVideoURL,
			progressHandler: { p in progressHandler?(p * 0.7) }
		)

		// Step 4: 混音
		let hasAudio = sorted.contains { $0.volume > 0 && $0.mediaType != .image }
		var audioExists = false
		if hasAudio {
			audioExists = try await mixAudio(
				inputs: sorted,
				totalDuration: totalDuration,
				outputURL: tempAudioURL,
				progressHandler: { p in progressHandler?(0.7 + p * 0.15) }
			)
		}

		// Step 5: 合并视频 + 音频
		try await mergeVideoAudio(
			videoURL: tempVideoURL,
			audioURL: audioExists ? tempAudioURL : nil,
			outputURL: outputURL,
			progressHandler: { p in progressHandler?(0.85 + p * 0.15) }
		)
	}

	// MARK: - Video Rendering

	private func renderVideo(
		inputs: [CanvasElementInput],
		canvasSize: CGSize,
		totalDuration: Double,
		frameRate: Int,
		outputURL: URL,
		progressHandler: (@Sendable (Double) -> Void)?
	) async throws {
		let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
		let totalFrames = Int(totalDuration * Double(frameRate))

		// 预加载所有视频源的关键帧读取器
		var frameSources: [FrameSource] = []
		for input in inputs {
			let source = try await FrameSource(input: input)
			frameSources.append(source)
		}

		defer {
			for var source in frameSources { source.cleanup() }
		}

		// 创建 AVAssetWriter
		guard FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: nil) else {
			throw SpatialCanvasError.failedToCreateWriter("无法创建输出文件")
		}

		let writer = try AVAssetWriter(url: outputURL, fileType: .mp4)

		let videoSettings: [String: Any] = [
			AVVideoCodecKey: AVVideoCodecType.h264,
			AVVideoWidthKey: Int(canvasSize.width),
			AVVideoHeightKey: Int(canvasSize.height),
			AVVideoScalingModeKey: AVVideoScalingModeResize,
		]

		let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
		writerInput.expectsMediaDataInRealTime = false
		guard writer.canAdd(writerInput) else {
			throw SpatialCanvasError.failedToCreateWriter("无法添加视频轨道")
		}
		writer.add(writerInput)

		let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput)

		guard writer.startWriting() else {
			throw SpatialCanvasError.failedToExportVideo(writer.error?.localizedDescription ?? "未知错误")
		}
		writer.startSession(atSourceTime: .zero)

		// 帧渲染循环
		for frameIndex in 0..<totalFrames {
			let pts = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(frameRate))

			// 等待 writer input 就绪
			while !writerInput.isReadyForMoreMediaData {
				try await Task.sleep(nanoseconds: 5_000_000)
			}

			// 创建 CVPixelBuffer
			guard let pixelBuffer = createPixelBuffer(width: Int(canvasSize.width), height: Int(canvasSize.height)) else {
				continue
			}

			// 在 pixel buffer 上绘制所有元素
			renderFrame(
				pixelBuffer: pixelBuffer,
				canvasSize: canvasSize,
				inputs: inputs,
				frameSources: frameSources,
				atTime: CMTimeGetSeconds(pts)
			)

			adaptor.append(pixelBuffer, withPresentationTime: pts)

			if frameIndex % max(1, totalFrames / 50) == 0 {
				progressHandler?(Double(frameIndex) / Double(totalFrames))
			}
		}

		writerInput.markAsFinished()
		await writer.finishWriting()

		if writer.status != .completed {
			throw SpatialCanvasError.failedToExportVideo(writer.error?.localizedDescription ?? "写入失败")
		}
	}

	// MARK: - Pixel Buffer Helpers

	private func createPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
		var pixelBuffer: CVPixelBuffer?
		let attrs: [String: Any] = [
			kCVPixelBufferCGImageCompatibilityKey as String: true,
			kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
		]
		let status = CVPixelBufferCreate(
			kCFAllocatorDefault, width, height,
			kCVPixelFormatType_32ARGB,
			attrs as CFDictionary,
			&pixelBuffer
		)
		guard status == kCVReturnSuccess, let pb = pixelBuffer else { return nil }
		return pb
	}

	private func renderFrame(
		pixelBuffer: CVPixelBuffer,
		canvasSize: CGSize,
		inputs: [CanvasElementInput],
		frameSources: [FrameSource],
		atTime time: Double
	) {
		CVPixelBufferLockBaseAddress(pixelBuffer, [])

		guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
			CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
			return
		}

		let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
		let width = CVPixelBufferGetWidth(pixelBuffer)
		let height = CVPixelBufferGetHeight(pixelBuffer)

		let colorSpace = CGColorSpaceCreateDeviceRGB()
		let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

		guard let context = CGContext(
			data: baseAddress,
			width: width,
			height: height,
			bitsPerComponent: 8,
			bytesPerRow: bytesPerRow,
			space: colorSpace,
			bitmapInfo: bitmapInfo
		) else {
			CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
			return
		}

		// 绘制黑色背景
		context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
		context.fill(CGRect(origin: .zero, size: canvasSize))

		// 按 zIndex 顺序绘制每个元素
		for (index, input) in inputs.enumerated() {
			guard index < frameSources.count else { continue }
			guard let cgImage = frameSources[index].frame(at: time) else { continue }

			let drawRect = drawRect(for: input, canvasSize: canvasSize)
			context.saveGState()

			if let crop = input.cropRect {
				let cw = CGFloat(cgImage.width)
				let ch = CGFloat(cgImage.height)
				let cropInSource = CGRect(
					x: CGFloat(crop.origin.x) * cw,
					y: CGFloat(crop.origin.y) * ch,
					width: CGFloat(crop.size.width) * cw,
					height: CGFloat(crop.size.height) * ch
				)
				if let cropped = cgImage.cropping(to: cropInSource) {
					context.draw(cropped, in: drawRect)
				} else {
					context.draw(cgImage, in: drawRect)
				}
			} else {
				context.draw(cgImage, in: drawRect)
			}

			context.restoreGState()
		}

		CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
	}

	private func drawRect(for input: CanvasElementInput, canvasSize: CGSize) -> CGRect {
		let x = input.position.x
		let y = canvasSize.height - input.position.y - input.effectiveSize.height
		return CGRect(x: x, y: y, width: input.effectiveSize.width, height: input.effectiveSize.height)
	}

	// MARK: - Audio Mixing

	/// 混音并导出为 m4a，返回是否有音频成功导出
	private func mixAudio(
		inputs: [CanvasElementInput],
		totalDuration: Double,
		outputURL: URL,
		progressHandler: (@Sendable (Double) -> Void)?
	) async throws -> Bool {
		let mixComposition = AVMutableComposition()

		var hasAnyAudio = false
		var mixParams: [AVMutableAudioMixInputParameters] = []

		for input in inputs where input.volume > 0 && input.mediaType != .image {
			let asset = AVURLAsset(url: input.sourceURL)
			guard let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first else { continue }

			let compTrack = mixComposition.addMutableTrack(
				withMediaType: .audio,
				preferredTrackID: kCMPersistentTrackID_Invalid
			)
			let sourceDuration = min(input.duration, totalDuration)
			let timeRange = CMTimeRange(
				start: .zero,
				duration: CMTime(seconds: sourceDuration, preferredTimescale: 600)
			)
			do {
				try compTrack?.insertTimeRange(timeRange, of: audioTrack, at: .zero)
				hasAnyAudio = true
			} catch {
				continue
			}

			let params = AVMutableAudioMixInputParameters(track: compTrack)
			params.setVolume(Float(input.volume), at: .zero)
			mixParams.append(params)
		}

		guard hasAnyAudio else { return false }

		let audioMix = AVMutableAudioMix()
		audioMix.inputParameters = mixParams

		guard let session = AVAssetExportSession(
			asset: mixComposition,
			presetName: AVAssetExportPresetAppleM4A
		) else {
			return false
		}

		session.audioMix = audioMix
		session.outputURL = outputURL
		session.outputFileType = .m4a

		await session.export()

		if session.status != .completed {
			throw SpatialCanvasError.failedToExportAudio(session.error?.localizedDescription ?? "未知错误")
		}

		progressHandler?(1.0)
		return true
	}

	// MARK: - Merge Video + Audio

	private func mergeVideoAudio(
		videoURL: URL,
		audioURL: URL?,
		outputURL: URL,
		progressHandler: (@Sendable (Double) -> Void)?
	) async throws {
		let composition = AVMutableComposition()

		let videoAsset = AVURLAsset(url: videoURL)
		guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
			try? FileManager.default.copyItem(at: videoURL, to: outputURL)
			return
		}

		let compVideoTrack = composition.addMutableTrack(
			withMediaType: .video,
			preferredTrackID: kCMPersistentTrackID_Invalid
		)
		let videoDuration = try await videoAsset.load(.duration)
		try compVideoTrack?.insertTimeRange(
			CMTimeRange(start: .zero, duration: videoDuration),
			of: videoTrack,
			at: .zero
		)

		if let audioURL {
			let audioAsset = AVURLAsset(url: audioURL)
			if let audioTrack = try? await audioAsset.loadTracks(withMediaType: .audio).first {
				let compAudioTrack = composition.addMutableTrack(
					withMediaType: .audio,
					preferredTrackID: kCMPersistentTrackID_Invalid
				)
				let audioDuration = try? await audioAsset.load(.duration)
				if let audioDuration {
					try? compAudioTrack?.insertTimeRange(
						CMTimeRange(start: .zero, duration: audioDuration),
						of: audioTrack,
						at: .zero
					)
				}
			}
		}

		guard let session = AVAssetExportSession(
			asset: composition,
			presetName: AVAssetExportPresetHighestQuality
		) else {
			throw SpatialCanvasError.failedToMerge("无法创建导出会话")
		}

		session.outputURL = outputURL
		session.outputFileType = .mp4
		session.shouldOptimizeForNetworkUse = true

		await session.export()

		if session.status != .completed {
			throw SpatialCanvasError.failedToMerge(session.error?.localizedDescription ?? "未知错误")
		}

		progressHandler?(1.0)
	}

	// MARK: - 导出进度查询

	@MainActor
	static func estimateFileSize(canvasSize: CGSize, elementCount: Int, duration: Double) -> String {
		let roughBytesPerPixel = 0.5
		let totalPixels = canvasSize.width * canvasSize.height
		let bytesPerFrame = totalPixels * roughBytesPerPixel
		let totalBytes = bytesPerFrame * 30 * duration // 30fps
		let totalMB = totalBytes / (1024 * 1024)
		let estimated = max(Int(totalMB), 10)
		return "约 \(estimated) MB"
	}
}

// MARK: - FrameSource

/// 视频 / GIF / 图片的逐帧读取器
private struct FrameSource {
	let input: CanvasElementInput
	private var videoGenerator: AVAssetImageGenerator?
	private var gifFrames: [(image: CGImage, duration: Double)] = []
	private var staticImage: CGImage?
	private let isStatic: Bool

	init(input: CanvasElementInput) async throws {
		self.input = input
		switch input.mediaType {
		case .image:
			isStatic = true
			staticImage = await loadStaticImage(url: input.sourceURL)
		case .gif:
			isStatic = false
			gifFrames = loadGIFFrames(url: input.sourceURL)
		case .video:
			isStatic = false
			let asset = AVURLAsset(url: input.sourceURL)
			let gen = AVAssetImageGenerator(asset: asset)
			gen.appliesPreferredTrackTransform = true
			gen.requestedTimeToleranceBefore = .zero
			gen.requestedTimeToleranceAfter = .zero
			videoGenerator = gen
		}
	}

	func frame(at time: Double) -> CGImage? {
		if isStatic {
			return staticImage
		}

		if !gifFrames.isEmpty {
			return gifFrame(at: time)
		}

		guard let gen = videoGenerator else { return nil }
		let cmTime = CMTime(seconds: time, preferredTimescale: 600)
		var actualTime = CMTime.zero
		let image = try? gen.copyCGImage(at: cmTime, actualTime: &actualTime)
		return image
	}

	mutating func cleanup() {
		videoGenerator = nil
		gifFrames = []
		staticImage = nil
	}

	// MARK: - Private

	private func gifFrame(at time: Double) -> CGImage? {
		var accumulated: Double = 0
		for (image, duration) in gifFrames {
			accumulated += duration
			if time < accumulated { return image }
		}
		return gifFrames.last?.image
	}

	private func loadStaticImage(url: URL) async -> CGImage? {
		return await Task.detached {
			guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
			let props: [String: Any] = [kCGImageSourceShouldCache as String: true]
			return CGImageSourceCreateImageAtIndex(source, 0, props as CFDictionary)
		}.value
	}

	private func loadGIFFrames(url: URL) -> [(CGImage, Double)] {
		guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }
		let count = CGImageSourceGetCount(source)
		var frames: [(CGImage, Double)] = []

		for i in 0..<count {
			guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
			let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]
			let gifDict = props?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
			let delay = gifDict?[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double
				?? gifDict?[kCGImagePropertyGIFDelayTime as String] as? Double
				?? 0.1
			frames.append((cgImage, max(delay, 0.02)))
		}

		return frames
	}
}
