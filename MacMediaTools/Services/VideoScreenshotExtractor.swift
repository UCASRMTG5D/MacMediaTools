import AVFoundation
import AppKit
import Foundation

actor VideoScreenshotExtractor {
    enum ScreenshotExtractorError: LocalizedError {
        case noVideoTrack
        case invalidSettings(String)
        case userCancelled
        case noFramesExtracted
        case zipFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .noVideoTrack: return "未能找到视频轨道"
            case .invalidSettings(let msg): return msg
            case .userCancelled: return "用户已取消"
            case .noFramesExtracted: return "未能提取任何截图"
            case .zipFailed(let msg): return "打包失败: \(msg)"
            }
        }
    }
    
    static let shared = VideoScreenshotExtractor()

    private init() {}

    struct VideoMetadata {
        let duration: Double
        let width: Int
        let height: Int
        let frameRate: Double
        let codec: String
    }

	struct ExtractionSettings {
		var startTime: Double = 0
		var endTime: Double = 0
		var interval: Double = 1.0
		var outputFormat: OutputFormat = .png
		var enableQualityCheck: Bool = true
		var qualityThreshold: Double = 0.85
		var enableDuplicateFilter: Bool = false
		var duplicateThreshold: Double = 0.15

		enum OutputFormat: String, CaseIterable {
			case png = "PNG"
			case jpeg = "JPEG"
		}
	}

    struct ExtractedFrame: @unchecked Sendable {
        let time: Double
        let image: CGImage
        let filePath: URL?
        let qualityScore: Double
        let isReplaced: Bool
    }

    struct ExtractionResult {
        let success: Bool
        let allFrames: [ExtractedFrame]
        let qualityFilteredFrames: [ExtractedFrame]
        let dedupedFrames: [ExtractedFrame]
        let qualityAndDedupedFrames: [ExtractedFrame]
        let outputDirectory: URL
        let error: String?
        let logs: [String]
    }

    enum FilterMode: String, CaseIterable, Identifiable {
        case all = "全部"
        case quality = "质量筛选"
        case dedup = "去重"
        case qualityAndDedup = "筛选+去重"

        var id: String { rawValue }

        func frames(from result: ExtractionResult) -> [ExtractedFrame] {
            switch self {
            case .all: return result.allFrames
            case .quality: return result.qualityFilteredFrames
            case .dedup: return result.dedupedFrames
            case .qualityAndDedup: return result.qualityAndDedupedFrames
            }
        }
    }

    struct ExtractionProgress {
        let current: Int
        let total: Int
        let status: String
        let estimatedRemainingTime: TimeInterval?
    }

    // MARK: - Video Metadata

    func getVideoMetadata(url: URL) async throws -> VideoMetadata {
        let asset = AVURLAsset(url: url)

        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)

        guard let videoTrack = tracks.first else {
            throw ScreenshotExtractorError.noVideoTrack
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)

        var codec = "未知"
        if let formatDesc = formatDescriptions.first {
            codec = CMFormatDescriptionGetMediaSubType(formatDesc).description
        }

        return VideoMetadata(
            duration: duration.seconds,
            width: Int(naturalSize.width),
            height: Int(naturalSize.height),
            frameRate: Double(frameRate),
            codec: codec
        )
    }

    // MARK: - Validation

    func validateVideoFormat(url: URL) async -> Bool {
		let supportedExtensions = Array(MediaFileExtensions.video)
        let fileExtension = url.pathExtension.lowercased()
        return supportedExtensions.contains(fileExtension)
    }

    func validateSettings(settings: ExtractionSettings, duration: Double) -> String? {
        if settings.startTime < 0 {
            return "开始时间不能为负数"
        }
        if settings.endTime > duration {
            return "结束时间不能超过视频时长"
        }
        if settings.startTime >= settings.endTime {
            return "开始时间必须小于结束时间"
        }
        if settings.interval < 0.001 || settings.interval > 60 {
            return "时间间隔必须在0.001秒至60秒之间"
        }
		if settings.qualityThreshold < 0 || settings.qualityThreshold > 1 {
			return "质量阈值必须在0到1之间"
		}
		if settings.duplicateThreshold < 0 || settings.duplicateThreshold > 1 {
			return "相似度阈值必须在0到1之间"
		}
		return nil
    }

    // MARK: - Quality Assessment

    nonisolated private func calculateImageSharpness(image: CGImage) -> Double {
        let width = image.width
        let height = image.height
        let bytesPerPixel = image.bitsPerPixel / 8
        let bytesPerRow = image.bytesPerRow

        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return 50.0
        }

        // 确定像素通道偏移：支持 BGRA / ARGB / RGBA
        let ri: Int, gi: Int, bi: Int
        let byteOrder = image.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue
        if byteOrder == CGBitmapInfo.byteOrder32Little.rawValue {
            ri = 2; gi = 1; bi = 0
        } else {
            let ai = CGImageAlphaInfo(rawValue: image.bitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue)
            switch ai {
            case .some(.first), .some(.premultipliedFirst), .some(.noneSkipFirst):
                ri = 1; gi = 2; bi = 3
            default:
                ri = 0; gi = 1; bi = 2
            }
        }

        // Step 1: Compute Y (luma) plane: Y = 0.299*R + 0.587*G + 0.114*B
        var luma: [Double] = Array(repeating: 0, count: width * height)
        for y in 0..<height {
            let rowBase = y * bytesPerRow
            let lumaBase = y * width
            for x in 0..<width {
                let idx = rowBase + x * bytesPerPixel
                let r = Double(bytes[idx + ri])
                let g = Double(bytes[idx + gi])
                let b = Double(bytes[idx + bi])
                luma[lumaBase + x] = 0.299 * r + 0.587 * g + 0.114 * b
            }
        }

        // Step 2: Sobel 3x3 edge magnitude on luma plane
        // Gx: [[-1, 0, +1], [-2, 0, +2], [-1, 0, +1]]
        // Gy: [[-1, -2, -1], [ 0,  0,  0], [+1, +2, +1]]
        var totalMagnitude = 0.0
        var pixelCount = 0

        for y in 1..<(height - 1) {
            let lumaBase = y * width
            let prevBase = (y - 1) * width
            let nextBase = (y + 1) * width
            for x in 1..<(width - 1) {
                let tl = luma[prevBase + x - 1]
                let tc = luma[prevBase + x]
                let tr = luma[prevBase + x + 1]
                let ml = luma[lumaBase + x - 1]
                let mr = luma[lumaBase + x + 1]
                let bl = luma[nextBase + x - 1]
                let bc = luma[nextBase + x]
                let br = luma[nextBase + x + 1]

                let gx = (-1)*tl + 1*tr + (-2)*ml + 2*mr + (-1)*bl + 1*br
                let gy = (-1)*tl + (-2)*tc + (-1)*tr + 1*bl + 2*bc + 1*br

                totalMagnitude += sqrt(gx * gx + gy * gy)
                pixelCount += 1
            }
        }

        if pixelCount == 0 {
            return 50.0
        }

        return totalMagnitude / Double(pixelCount)
    }

    // MARK: - Image Similarity & Dedup

    /// Compute a 16x16 grayscale hash for an image.
    /// Returns a flattened array of 256 grayscale values (0.0–1.0).
    private func computeHash(image: CGImage) -> [Double] {
        let size = 16
        let width = image.width
        let height = image.height
        let scaleX = max(1, width / size)
        let scaleY = max(1, height / size)

        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return Array(repeating: 0.5, count: size * size)
        }

        // 确定像素通道偏移：支持 BGRA / ARGB / RGBA
        let ri: Int, gi: Int, bi: Int
        let byteOrder = image.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue
        if byteOrder == CGBitmapInfo.byteOrder32Little.rawValue {
            ri = 2; gi = 1; bi = 0
        } else {
            let ai = CGImageAlphaInfo(rawValue: image.bitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue)
            switch ai {
            case .some(.first), .some(.premultipliedFirst), .some(.noneSkipFirst):
                ri = 1; gi = 2; bi = 3
            default:
                ri = 0; gi = 1; bi = 2
            }
        }

        let bpp = image.bitsPerPixel / 8
        let row = image.bytesPerRow
        var hash = [Double]()
        hash.reserveCapacity(size * size)

        for gy in 0..<size {
            for gx in 0..<size {
                var r: Double = 0, g: Double = 0, b: Double = 0, count: Double = 0
                for py in 0..<scaleY {
                    for px in 0..<scaleX {
                        let x = gx * scaleX + px
                        let y = gy * scaleY + py
                        if x < width && y < height {
                            let idx = y * row + x * bpp
                            if idx + 2 < row * height {
                                r += Double(bytes[idx + ri])
                                g += Double(bytes[idx + gi])
                                b += Double(bytes[idx + bi])
                                count += 1
                            }
                        }
                    }
                }
                if count > 0 {
                    let gray = (r / count * 0.299 + g / count * 0.587 + b / count * 0.114) / 255.0
                    hash.append(gray)
                } else {
                    hash.append(0.5)
                }
            }
        }
        return hash
    }

    /// Compute similarity (0 = identical, 1 = completely different) between two images
    /// by comparing their 16x16 grayscale hashes.
    private func imageDifference(_ img1: CGImage, _ img2: CGImage) -> Double {
        let h1 = computeHash(image: img1)
        let h2 = computeHash(image: img2)
        guard h1.count == h2.count, !h1.isEmpty else { return 1.0 }

        var totalDiff: Double = 0
        for i in 0..<h1.count {
            totalDiff += abs(h1[i] - h2[i])
        }
        return totalDiff / Double(h1.count)
    }

    /// Filter frames using temporal sliding window dedup:
    /// compare each frame against the last KEPT frame; skip if similar but
    /// replace when the new frame has higher quality.
    func filterDuplicateFrames(_ frames: [ExtractedFrame], threshold: Double) -> [ExtractedFrame] {
        guard frames.count > 1 else { return frames }
        let clampedThreshold = max(0, min(1, threshold))
        var kept = [ExtractedFrame]()
        kept.reserveCapacity(frames.count)
        kept.append(frames[0])

        for i in 1..<frames.count {
            let diff = imageDifference(kept.last!.image, frames[i].image)
            if diff >= clampedThreshold {
                kept.append(frames[i])
            } else if frames[i].qualityScore > kept.last!.qualityScore {
                kept[kept.count - 1] = frames[i]
            }
        }
        return kept
    }

    // MARK: - Screenshot Extraction

    func extractScreenshots(
        videoURL: URL,
        outputDirectory: URL,
        settings: ExtractionSettings,
        progressHandler: @escaping (ExtractionProgress) -> Void,
        pauseHandler: @escaping () -> Bool,
        cancelHandler: @escaping () -> Bool
    ) async throws -> ExtractionResult {
        var logs: [String] = []
        let startTime = Date()
        logs.append("[\(timestamp())] 开始提取截图")
        logs.append("[\(timestamp())] 视频文件: \(videoURL.lastPathComponent)")
        logs.append("[\(timestamp())] 设置: 开始=\(formatTime(settings.startTime)), 结束=\(formatTime(settings.endTime)), 间隔=\(settings.interval)s")

        let metadata = try await getVideoMetadata(url: videoURL)
        logs.append("[\(timestamp())] 视频信息: 时长=\(formatTime(metadata.duration)), 分辨率=\(metadata.width)x\(metadata.height), 帧率=\(metadata.frameRate)fps")

        if let validationError = validateSettings(settings: settings, duration: metadata.duration) {
            throw ScreenshotExtractorError.invalidSettings(validationError)
        }

        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // 使用 25% 间隔的容差，避免因精确帧定位失败而丢帧
        let tolerance = CMTime(seconds: settings.interval * 0.25, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        // 计算时间点
        let timeRange = settings.endTime - settings.startTime
        guard settings.interval > 0 else {
            throw ScreenshotExtractorError.invalidSettings("时间间隔不能为零")
        }
        let frameCount = max(1, Int(timeRange / settings.interval) + 1)
        var timePoints: [Double] = []

        for i in 0..<frameCount {
            let time = settings.startTime + (Double(i) * settings.interval)
            timePoints.append(min(time, settings.endTime))
        }

        logs.append("[\(timestamp())] 将提取 \(frameCount) 帧")

        var extractedFrames: [ExtractedFrame] = []
        let videoName = videoURL.deletingPathExtension().lastPathComponent
        let folderName = "\(videoName)_screenshots_\(timestamp())"
        let finalOutputDir = outputDirectory.appendingPathComponent(folderName)

        try FileManager.default.createDirectory(at: finalOutputDir, withIntermediateDirectories: true)
        logs.append("[\(timestamp())] 输出目录: \(finalOutputDir.path)")

        // 并行提取：将时间点分块，每块独立提取
        let processorCount = max(2, ProcessInfo.processInfo.processorCount)
        let chunkSize = max(1, (timePoints.count + processorCount - 1) / processorCount)

        // 线程安全的进度追踪器
        actor ProgressTracker {
            nonisolated let total: Int
            nonisolated let startTime: Date
            nonisolated let handler: (ExtractionProgress) -> Void
            var completed = 0

            init(total: Int, startTime: Date, handler: @escaping (ExtractionProgress) -> Void) {
                self.total = total
                self.startTime = startTime
                self.handler = handler
            }

            func reportOne() {
                completed += 1
                let elapsed = Date().timeIntervalSince(startTime)
                let pc = Double(completed) / Double(total)
                let remaining = pc > 0 ? elapsed / pc * (1 - pc) : Double.infinity
                handler(ExtractionProgress(
                    current: completed, total: total,
                    status: "正在提取第 \(completed)/\(total) 帧...",
                    estimatedRemainingTime: remaining
                ))
            }
        }

        let progressTracker = ProgressTracker(total: timePoints.count, startTime: startTime, handler: progressHandler)
        var allFrames: [ExtractedFrame] = []
        var allLogs: [String] = []

        try await withThrowingTaskGroup(of: (frames: [ExtractedFrame], logs: [String]).self) { group in
            for chunkIndex in 0..<processorCount {
                let startIdx = chunkIndex * chunkSize
                guard startIdx < timePoints.count else { break }
                let endIdx = min(startIdx + chunkSize, timePoints.count)
                let chunk = Array(timePoints[startIdx..<endIdx])

                group.addTask { [self] in
                    while pauseHandler() {
                        if cancelHandler() { throw ScreenshotExtractorError.userCancelled }
                        try await Task.sleep(nanoseconds: 100_000_000)
                    }
                    if cancelHandler() { throw ScreenshotExtractorError.userCancelled }

                    let gen = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
                    gen.appliesPreferredTrackTransform = true
                    gen.requestedTimeToleranceBefore = tolerance
                    gen.requestedTimeToleranceAfter = tolerance

                    var frames: [ExtractedFrame] = []
                    var logs: [String] = []

                    for (localIdx, targetTime) in chunk.enumerated() {
                        while pauseHandler() {
                            if cancelHandler() { throw ScreenshotExtractorError.userCancelled }
                            try await Task.sleep(nanoseconds: 100_000_000)
                        }
                        if cancelHandler() { throw ScreenshotExtractorError.userCancelled }
                        let globalIdx = startIdx + localIdx
                        do {
                            let time = CMTime(seconds: targetTime, preferredTimescale: 600)
                            var image = try gen.copyCGImage(at: time, actualTime: nil)
                            var qualityScore = calculateImageSharpness(image: image)
                            var isReplaced = false
                            var actualTime = targetTime

                            if settings.enableQualityCheck {
                                let searchRange = 1.0
                                let searchInterval = 0.1
                                var bestImage = image
                                var bestScore = qualityScore
                                var bestTime = actualTime

                                for offset in stride(from: -searchRange, through: searchRange, by: searchInterval) {
                                    if cancelHandler() { throw ScreenshotExtractorError.userCancelled }
                                    let searchTime = targetTime + offset
                                    if searchTime < settings.startTime || searchTime > settings.endTime { continue }
                                    do {
                                        let st = CMTime(seconds: searchTime, preferredTimescale: 600)
                                        let candidateImage = try gen.copyCGImage(at: st, actualTime: nil)
                                        let candidateScore = calculateImageSharpness(image: candidateImage)
                                        if candidateScore > bestScore {
                                            bestScore = candidateScore
                                            bestImage = candidateImage
                                            bestTime = searchTime
                                        }
                                    } catch { continue }
                                }

                                if bestScore > qualityScore {
                                    image = bestImage
                                    qualityScore = bestScore
                                    actualTime = bestTime
                                    isReplaced = true
                                    logs.append("[\(timestamp())] 帧 \(globalIdx + 1) 已替换为 \(formatTime(actualTime))，质量提升至 \(String(format: "%.2f", qualityScore))")
                                }
                            }

                            frames.append(ExtractedFrame(
                                time: actualTime, image: image, filePath: nil,
                                qualityScore: qualityScore, isReplaced: isReplaced
                            ))
                            logs.append("[\(timestamp())] 帧 \(globalIdx + 1) 提取成功 (\(formatTime(actualTime)))")

                        } catch {
                            logs.append("[\(timestamp())] 帧 \(globalIdx + 1) 提取失败: \(error.localizedDescription)")
                        }

                        await progressTracker.reportOne()
                    }

                    return (frames, logs)
                }
            }

            for try await chunkResult in group {
                allFrames.append(contentsOf: chunkResult.frames)
                allLogs.append(contentsOf: chunkResult.logs)
            }
        }

        // 按时间排序
        allFrames.sort { $0.time < $1.time }
        extractedFrames = allFrames
        logs.append(contentsOf: allLogs)

        // 4种筛选模式
        // 1) 质量筛选：按百分位保留质量分靠前的帧
        // （calculateImageSharpness 对自然视频输出 0.02-0.25，绝对阈值 0.85 永远筛不出帧）
        let qualityFiltered: [ExtractedFrame]
        if settings.enableQualityCheck {
            let keepCount = max(1, Int(Double(extractedFrames.count) * settings.qualityThreshold))
            qualityFiltered = extractedFrames
                .enumerated()
                .sorted { $0.element.qualityScore > $1.element.qualityScore }
                .prefix(keepCount)
                .sorted { $0.offset < $1.offset }
                .map { $0.element }
            logs.append("[\(timestamp())] 质量筛选（百分位，阈值 \(String(format: "%.2f", settings.qualityThreshold))）：\(extractedFrames.count) → \(qualityFiltered.count) 帧")
        } else {
            qualityFiltered = extractedFrames
        }

        // 2) 去重：时序滑动窗口
        let deduped: [ExtractedFrame]
        if settings.enableDuplicateFilter && extractedFrames.count > 1 {
            logs.append("[\(timestamp())] 开始内容去重，阈值: \(String(format: "%.2f", settings.duplicateThreshold))")
            deduped = filterDuplicateFrames(extractedFrames, threshold: settings.duplicateThreshold)
            logs.append("[\(timestamp())] 去重完成：\(extractedFrames.count) → \(deduped.count) 帧")
        } else {
            deduped = extractedFrames
        }

        // 3) 筛选+去重：先质量筛选，再去重
        let qualityAndDeduped: [ExtractedFrame]
        if settings.enableQualityCheck && settings.enableDuplicateFilter && qualityFiltered.count > 1 {
            qualityAndDeduped = filterDuplicateFrames(qualityFiltered, threshold: settings.duplicateThreshold)
            logs.append("[\(timestamp())] 筛选+去重：\(extractedFrames.count) → \(qualityAndDeduped.count) 帧")
        } else if settings.enableQualityCheck {
            qualityAndDeduped = qualityFiltered
        } else if settings.enableDuplicateFilter {
            qualityAndDeduped = deduped
        } else {
            qualityAndDeduped = extractedFrames
        }

        progressHandler(ExtractionProgress(
            current: frameCount,
            total: frameCount,
            status: "提取完成",
            estimatedRemainingTime: 0
        ))

        let totalTime = Date().timeIntervalSince(startTime)
        logs.append("[\(timestamp())] 提取完成，共 \(extractedFrames.count) 帧，耗时 \(String(format: "%.2f", totalTime)) 秒")
        logs.append("[\(timestamp())] 平均速度: \(String(format: "%.2f", Double(extractedFrames.count) / totalTime)) 帧/秒")
        logs.append("[\(timestamp())] 预期 \(frameCount) 帧，实际提取 \(extractedFrames.count) 帧（差异: \(frameCount - extractedFrames.count)）")

        if extractedFrames.isEmpty {
            throw ScreenshotExtractorError.noFramesExtracted
        }

        return ExtractionResult(
            success: true,
            allFrames: extractedFrames,
            qualityFilteredFrames: qualityFiltered,
            dedupedFrames: deduped,
            qualityAndDedupedFrames: qualityAndDeduped,
            outputDirectory: finalOutputDir,
            error: nil,
            logs: logs
        )
    }

    // MARK: - Batch Save

    func saveFrames(_ frames: [ExtractedFrame], to directory: URL, format: ExtractionSettings.OutputFormat) async throws -> [URL] {
        var savedURLs: [URL] = []
        let videoName = "screenshots"
        for (index, frame) in frames.enumerated() {
            let bitmapRep = NSBitmapImageRep(cgImage: frame.image)
            let imageData: Data?
            let fileExtension: String
            switch format {
            case .png:
                imageData = bitmapRep.representation(using: .png, properties: [:])
                fileExtension = "png"
            case .jpeg:
                imageData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
                fileExtension = "jpg"
            }
            guard let data = imageData else { continue }
            let fileName = "\(videoName)_\(formatFileNameTimestamp(frame.time)).\(fileExtension)"
            let fileURL = directory.appendingPathComponent(fileName)
            try data.write(to: fileURL)
            savedURLs.append(fileURL)
        }
        return savedURLs
    }

    // MARK: - Batch Export (ZIP)

    func exportAsZip(files: [URL], outputURL: URL) async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // 将所有文件复制到临时目录
        for file in files {
            let destURL = tempDir.appendingPathComponent(file.lastPathComponent)
            try FileManager.default.copyItem(at: file, to: destURL)
        }

        // 使用系统 zip 命令打包
        let task = Process()
        task.currentDirectoryURL = tempDir
        task.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        task.arguments = ["-r", outputURL.path, "."]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        try task.run()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            throw ScreenshotExtractorError.zipFailed("打包失败")
        }
    }

    // MARK: - Utility Methods

    nonisolated private func timestamp() -> String {
        currentTimestamp()
    }

    nonisolated private func formatTimestamp(_ seconds: Double) -> String {
        formatFileNameTimestamp(seconds)
    }
}
