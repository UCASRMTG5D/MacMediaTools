import AVFoundation
import AppKit
import Foundation

actor VideoScreenshotExtractor {
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
        
        enum OutputFormat: String, CaseIterable {
            case png = "PNG"
            case jpeg = "JPEG"
        }
    }
    
    struct ExtractedFrame {
        let time: Double
        let image: CGImage
        let filePath: URL?
        let qualityScore: Double
        let isReplaced: Bool
    }
    
    struct ExtractionResult {
        let success: Bool
        let extractedFrames: [ExtractedFrame]
        let outputDirectory: URL
        let error: String?
        let logs: [String]
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
            throw NSError(domain: "VideoScreenshotExtractor", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "未能找到视频轨道"
            ])
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
        if settings.interval < 0.1 || settings.interval > 60 {
            return "时间间隔必须在0.1秒至60秒之间"
        }
        if settings.qualityThreshold < 0 || settings.qualityThreshold > 1 {
            return "质量阈值必须在0到1之间"
        }
        return nil
    }
    
    // MARK: - Quality Assessment
    
    private func calculateImageSharpness(image: CGImage) -> Double {
        let width = image.width
        let height = image.height
        let bytesPerPixel = image.bitsPerPixel / 8
        let bytesPerRow = image.bytesPerRow
        
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return 0.5
        }
        
        var gradientMagnitude = 0.0
        var pixelCount = 0
        
        for y in 0..<height-1 {
            for x in 0..<width-1 {
                let idx1 = y * bytesPerRow + x * bytesPerPixel
                let idx2 = y * bytesPerRow + (x + 1) * bytesPerPixel
                let idx3 = (y + 1) * bytesPerRow + x * bytesPerPixel
                
                if idx1 + 2 < bytesPerRow * height && idx2 + 2 < bytesPerRow * height && idx3 + 2 < bytesPerRow * height {
                    let r1 = Double(bytes[idx1])
                    let g1 = Double(bytes[idx1 + 1])
                    let b1 = Double(bytes[idx1 + 2])
                    
                    let r2 = Double(bytes[idx2])
                    let g2 = Double(bytes[idx2 + 1])
                    let b2 = Double(bytes[idx2 + 2])
                    
                    let r3 = Double(bytes[idx3])
                    let g3 = Double(bytes[idx3 + 1])
                    let b3 = Double(bytes[idx3 + 2])
                    
                    let dx = sqrt(pow(r2 - r1, 2) + pow(g2 - g1, 2) + pow(b2 - b1, 2))
                    let dy = sqrt(pow(r3 - r1, 2) + pow(g3 - g1, 2) + pow(b3 - b1, 2))
                    
                    gradientMagnitude += dx + dy
                    pixelCount += 1
                }
            }
        }
        
        if pixelCount == 0 {
            return 0.5
        }
        
        let avgGradient = gradientMagnitude / Double(pixelCount)
        let normalizedScore = min(avgGradient / 200.0, 1.0)
        
        return normalizedScore
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
            throw NSError(domain: "VideoScreenshotExtractor", code: -2, userInfo: [
                NSLocalizedDescriptionKey: validationError
            ])
        }
        
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        // 计算时间点
        let timeRange = settings.endTime - settings.startTime
        guard settings.interval > 0 else {
            throw NSError(domain: "VideoScreenshotExtractor", code: -4, userInfo: [
                NSLocalizedDescriptionKey: "时间间隔不能为零"
            ])
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
        
        for (index, targetTime) in timePoints.enumerated() {
            // 检查暂停
            while pauseHandler() {
                if cancelHandler() {
                    logs.append("[\(timestamp())] 用户取消操作")
                    throw NSError(domain: "VideoScreenshotExtractor", code: -3, userInfo: [
                        NSLocalizedDescriptionKey: "用户已取消"
                    ])
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            
            // 检查取消
            if cancelHandler() {
                logs.append("[\(timestamp())] 用户取消操作")
                throw NSError(domain: "VideoScreenshotExtractor", code: -3, userInfo: [
                    NSLocalizedDescriptionKey: "用户已取消"
                ])
            }
            
            let progress = Double(index) / Double(timePoints.count)
            let elapsed = Date().timeIntervalSince(startTime)
            let estimatedRemaining = progress > 0 ? elapsed / progress * (1 - progress) : Double.infinity
            
            progressHandler(ExtractionProgress(
                current: index,
                total: timePoints.count,
                status: "正在提取第 \(index + 1)/\(timePoints.count) 帧...",
                estimatedRemainingTime: estimatedRemaining
            ))
            
            do {
                let time = CMTime(seconds: targetTime, preferredTimescale: 600)
                var image = try generator.copyCGImage(at: time, actualTime: nil)
                var qualityScore = calculateImageSharpness(image: image)
                var isReplaced = false
                var actualTime = targetTime
                
                // 质量检查和智能替换
                if settings.enableQualityCheck && qualityScore < settings.qualityThreshold {
                    logs.append("[\(timestamp())] 帧 \(index + 1) 质量较低 (\(String(format: "%.2f", qualityScore))), 正在寻找替代帧")
                    
                    // 在前后1秒范围内寻找最佳帧
                    let searchRange = 1.0
                    let searchInterval = 0.1
                    var bestImage = image
                    var bestScore = qualityScore
                    var bestTime = targetTime
                    
                    for offset in stride(from: -searchRange, through: searchRange, by: searchInterval) {
                        let searchTime = targetTime + offset
                        if searchTime < settings.startTime || searchTime > settings.endTime {
                            continue
                        }
                        
                        do {
                            let searchCMTime = CMTime(seconds: searchTime, preferredTimescale: 600)
                            let candidateImage = try generator.copyCGImage(at: searchCMTime, actualTime: nil)
                            let candidateScore = calculateImageSharpness(image: candidateImage)
                            
                            if candidateScore > bestScore {
                                bestScore = candidateScore
                                bestImage = candidateImage
                                bestTime = searchTime
                            }
                        } catch {
                            continue
                        }
                    }
                    
                    if bestScore > qualityScore {
                        image = bestImage
                        qualityScore = bestScore
                        actualTime = bestTime
                        isReplaced = true
                        logs.append("[\(timestamp())] 帧 \(index + 1) 已替换为 \(formatTime(actualTime))，质量提升至 \(String(format: "%.2f", qualityScore))")
                    } else {
                        logs.append("[\(timestamp())] 帧 \(index + 1) 未找到更好的替代帧")
                    }
                }
                
                // 保存图片
                let bitmapRep = NSBitmapImageRep(cgImage: image)
                let imageData: Data?
                let fileExtension: String
                
                switch settings.outputFormat {
                case .png:
                    imageData = bitmapRep.representation(using: .png, properties: [:])
                    fileExtension = "png"
                case .jpeg:
                    imageData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: settings.qualityThreshold])
                    fileExtension = "jpg"
                }
                
                guard let data = imageData else {
                    logs.append("[\(timestamp())] 帧 \(index + 1) 编码失败")
                    continue
                }
                
                let fileName = "\(videoName)_\(formatTimestamp(actualTime)).\(fileExtension)"
                let fileURL = finalOutputDir.appendingPathComponent(fileName)
                try data.write(to: fileURL)
                
                extractedFrames.append(ExtractedFrame(
                    time: actualTime,
                    image: image,
                    filePath: fileURL,
                    qualityScore: qualityScore,
                    isReplaced: isReplaced
                ))
                
                logs.append("[\(timestamp())] 帧 \(index + 1) 保存成功 (\(formatTime(actualTime)))")
                
            } catch {
                logs.append("[\(timestamp())] 帧 \(index + 1) 提取失败: \(error.localizedDescription)")
                continue
            }
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
        
        if extractedFrames.isEmpty {
            throw NSError(domain: "VideoScreenshotExtractor", code: -4, userInfo: [
                NSLocalizedDescriptionKey: "未能提取任何截图"
            ])
        }
        
        return ExtractionResult(
            success: true,
            extractedFrames: extractedFrames,
            outputDirectory: finalOutputDir,
            error: nil,
            logs: logs
        )
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
            throw NSError(domain: "VideoScreenshotExtractor", code: -5, userInfo: [
                NSLocalizedDescriptionKey: "打包失败"
            ])
        }
    }
    
    // MARK: - Utility Methods
    
    private func timestamp() -> String {
        currentTimestamp()
    }
    
    private func formatTimestamp(_ seconds: Double) -> String {
        formatFileNameTimestamp(seconds)
    }
}
