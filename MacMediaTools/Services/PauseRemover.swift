import AVFoundation
import Foundation

enum PauseRemoverError: LocalizedError {
    case noAudioTrack
    case noVideoTrack
    case failedToCreateComposition
    case failedToCreateExportSession
    case outputAlreadyExists
    case exportFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "未找到音频轨道"
        case .noVideoTrack:
            return "未找到视频轨道"
        case .failedToCreateComposition:
            return "创建合成失败"
        case .failedToCreateExportSession:
            return "创建导出会话失败"
        case .outputAlreadyExists:
            return "输出文件已存在"
        case .exportFailed(let message):
            return "导出失败：\(message)"
        }
    }
}

struct PauseAnalysisResult: Sendable {
    let originalDuration: Double
    let keptDuration: Double
    let silenceRanges: [CMTimeRange]
    let keepSegments: [CMTimeRange]
    
    var removedDuration: Double {
        originalDuration - keptDuration
    }
    
    var removedRatio: Double {
        originalDuration > 0 ? removedDuration / originalDuration : 0
    }
}

actor PauseRemover {
    static let shared = PauseRemover()
    private init() {}
    
    func analyze(url: URL, thresholdDB: Float, minSilenceSeconds: Double = 0.5, windowSeconds: Double = 0.02) async throws -> PauseAnalysisResult {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { throw PauseRemoverError.noAudioTrack }
        
        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let audioOutput = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: outputSettings)
        audioOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(audioOutput) else {
            throw PauseRemoverError.exportFailed("无法添加音频输出")
        }
        reader.add(audioOutput)
        guard reader.startReading() else {
            if let e = reader.error { throw PauseRemoverError.exportFailed(e.localizedDescription) }
            throw PauseRemoverError.exportFailed("读取音频失败")
        }
        
        let total = duration.seconds
        var silenceRanges: [CMTimeRange] = []
        var sampleRate: Double = 44100.0
        if let formatDesc = audioTracks[0].formatDescriptions.first {
            let desc = formatDesc as! CMAudioFormatDescription
            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                sampleRate = Double(asbd.pointee.mSampleRate)
                if sampleRate <= 0 { sampleRate = 44100.0 }
            }
        }
        let windowFrames = max(1, Int(sampleRate * windowSeconds))
        var window: [Float] = []
        window.reserveCapacity(windowFrames)
        var isInSilence = false
        var silenceStartSec: Double = 0
        var processedFrames: Int = 0
        while let sbuf = audioOutput.copyNextSampleBuffer() {
            if let block = CMSampleBufferGetDataBuffer(sbuf) {
                let length = CMBlockBufferGetDataLength(block)
                var data = Data(count: length)
                _ = data.withUnsafeMutableBytes { ptr in
                    CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
                }
                data.withUnsafeBytes { bytes in
                    let floats = bytes.bindMemory(to: Float.self)
                    for v in floats {
                        window.append(v)
                        processedFrames += 1
                        if window.count == windowFrames {
                            var sum: Double = 0
                            for val in window { sum += Double(val) * Double(val) }
                            let rms = sqrt(max(sum / Double(window.count), 1e-18))
                            let db = 20.0 * log10(rms)
                            let curSec = Double(processedFrames - windowFrames) / sampleRate
                            if db < Double(thresholdDB) {
                                if !isInSilence {
                                    isInSilence = true
                                    silenceStartSec = curSec
                                }
                            } else {
                                if isInSilence {
                                    let endSec = Double(processedFrames) / sampleRate
                                    let dur = endSec - silenceStartSec
                                    if dur >= minSilenceSeconds {
                                        let s = CMTime(seconds: max(0, silenceStartSec), preferredTimescale: 6000)
                                        let d = CMTime(seconds: dur, preferredTimescale: 6000)
                                        silenceRanges.append(CMTimeRange(start: s, duration: d))
                                    }
                                    isInSilence = false
                                }
                            }
                            window.removeAll(keepingCapacity: true)
                        }
                    }
                }
            }
        }
        if isInSilence && window.count > 0 {
            let endSec = Double(processedFrames) / sampleRate
            let dur = endSec - silenceStartSec
            if dur >= minSilenceSeconds {
                let s = CMTime(seconds: max(0, silenceStartSec), preferredTimescale: 6000)
                let d = CMTime(seconds: dur, preferredTimescale: 6000)
                silenceRanges.append(CMTimeRange(start: s, duration: d))
            }
        }
        var keepSegments: [CMTimeRange] = []
        var cursor: Double = 0
        let tTotal = total
        for sil in silenceRanges.sorted(by: { $0.start.seconds < $1.start.seconds }) {
            let s = sil.start.seconds
            let e = sil.start.seconds + sil.duration.seconds
            if s > cursor + 0.001 {
                let seg = CMTimeRange(start: CMTime(seconds: cursor, preferredTimescale: 6000), duration: CMTime(seconds: s - cursor, preferredTimescale: 6000))
                keepSegments.append(seg)
            }
            let keepEnd = min(s + minSilenceSeconds, e)
            if keepEnd > s + 0.001 {
                let seg = CMTimeRange(start: CMTime(seconds: s, preferredTimescale: 6000), duration: CMTime(seconds: keepEnd - s, preferredTimescale: 6000))
                keepSegments.append(seg)
            }
            cursor = e
        }
        if tTotal > cursor + 0.001 {
            let seg = CMTimeRange(start: CMTime(seconds: cursor, preferredTimescale: 6000), duration: CMTime(seconds: tTotal - cursor, preferredTimescale: 6000))
            keepSegments.append(seg)
        }
        if keepSegments.isEmpty && tTotal > 0 {
            keepSegments = [CMTimeRange(start: .zero, duration: CMTime(seconds: tTotal, preferredTimescale: 6000))]
        }
        var kept: Double = 0
        for seg in keepSegments { kept += seg.duration.seconds }
        return PauseAnalysisResult(originalDuration: total, keptDuration: kept, silenceRanges: silenceRanges, keepSegments: keepSegments)
    }
    func export(inputURL: URL, keepSegments: [CMTimeRange], outputURL: URL, progressHandler: @escaping (Double) -> Void) async throws {
        guard !FileManager.default.fileExists(atPath: outputURL.path) else { throw PauseRemoverError.outputAlreadyExists }
        let asset = AVURLAsset(url: inputURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let videoTrack = videoTracks.first else { throw PauseRemoverError.noVideoTrack }
        guard !audioTracks.isEmpty else { throw PauseRemoverError.noAudioTrack }
        
        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw PauseRemoverError.failedToCreateComposition
        }
        compVideo.preferredTransform = try await videoTrack.load(.preferredTransform)
        
        var compAudios: [AVMutableCompositionTrack] = []
        for _ in audioTracks {
            if let t = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                compAudios.append(t)
            }
        }
        guard compAudios.count == audioTracks.count else {
            throw PauseRemoverError.failedToCreateComposition
        }
        
        var cursor = CMTime.zero
        for seg in keepSegments {
            try compVideo.insertTimeRange(seg, of: videoTrack, at: cursor)
            for i in 0..<audioTracks.count {
                try compAudios[i].insertTimeRange(seg, of: audioTracks[i], at: cursor)
            }
            cursor = cursor + seg.duration
        }
        
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw PauseRemoverError.failedToCreateExportSession
        }
        exportSession.outputURL = outputURL
        let ext = outputURL.pathExtension.lowercased()
        exportSession.outputFileType = (ext == "mov") ? .mov : .mp4
        
        try await performExport(session: exportSession, progressHandler: progressHandler)
    }
    
    private func performExport(session: AVAssetExportSession, progressHandler: @escaping (Double) -> Void) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let progressObserver = session.observe(\.progress) { _, _ in
                progressHandler(Double(session.progress))
            }
            session.exportAsynchronously {
                progressObserver.invalidate()
                if session.status == .completed {
                    progressHandler(1.0)
                    continuation.resume()
                } else if let error = session.error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: PauseRemoverError.exportFailed("未知导出状态"))
                }
            }
        }
    }
}
