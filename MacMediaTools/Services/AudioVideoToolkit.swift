import AVFoundation
import CoreGraphics

actor AudioVideoToolkit {
    static let shared = AudioVideoToolkit()
    
    private init() {}
    
    struct TrackInfo {
        let url: URL
        let duration: Double
        let type: TrackType
        
        enum TrackType {
            case video
            case audio
        }
    }
    
    struct MergeSettings {
        var videoStartOffset: Double = 0
        var audioStartOffset: Double = 0
        var videoSpeed: Double = 1.0
        var audioSpeed: Double = 1.0
    }
    
    func getTrackInfo(url: URL) async throws -> TrackInfo {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        
        let tracks = try await asset.loadTracks(withMediaType: .video)
        if !tracks.isEmpty {
            return TrackInfo(url: url, duration: duration.seconds, type: .video)
        }
        
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if !audioTracks.isEmpty {
            return TrackInfo(url: url, duration: duration.seconds, type: .audio)
        }
        
        throw NSError(domain: "AudioVideoToolkit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported file type"])
    }
    
    func mergeAudioVideo(
        videoURL: URL,
        audioURL: URL,
        outputURL: URL,
        settings: MergeSettings,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        
        guard let videoTrack = videoTracks.first, let audioTrack = audioTracks.first else {
            throw NSError(domain: "AudioVideoToolkit", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to load tracks"])
        }
        
        let videoDuration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        
        let composition = AVMutableComposition()
        
        let videoCompTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioCompTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        let videoTimeRange = CMTimeRange(start: CMTime(seconds: settings.videoStartOffset, preferredTimescale: 600), duration: videoDuration - CMTime(seconds: settings.videoStartOffset, preferredTimescale: 600))
        let audioTimeRange = CMTimeRange(start: CMTime(seconds: settings.audioStartOffset, preferredTimescale: 600), duration: audioDuration - CMTime(seconds: settings.audioStartOffset, preferredTimescale: 600))
        
        try videoCompTrack?.insertTimeRange(videoTimeRange, of: videoTrack, at: .zero)
        try audioCompTrack?.insertTimeRange(audioTimeRange, of: audioTrack, at: .zero)
        
        if settings.videoSpeed != 1.0 {
            let videoRate = AVMutableVideoCompositionLayerInstruction(assetTrack: videoCompTrack!)
            let scale = CGAffineTransform(scaleX: CGFloat(settings.videoSpeed), y: CGFloat(settings.videoSpeed))
            videoRate.setTransform(scale, at: CMTime.zero)
            
            let adjustedDuration = CMTime(seconds: videoDuration.seconds / settings.videoSpeed, preferredTimescale: videoDuration.timescale)
            let videoInstruction = AVMutableVideoCompositionInstruction()
            videoInstruction.timeRange = CMTimeRange(start: CMTime.zero, duration: adjustedDuration)
            videoInstruction.layerInstructions = [videoRate]
            
            let videoComposition = AVMutableVideoComposition()
            videoComposition.instructions = [videoInstruction]
            videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
            
            let videoSize = try await videoTrack.load(.naturalSize)
            videoComposition.renderSize = videoSize
            
            try await export(composition: composition, videoComposition: videoComposition, outputURL: outputURL, progressHandler: progressHandler)
        } else {
            try await export(composition: composition, videoComposition: nil, outputURL: outputURL, progressHandler: progressHandler)
        }
    }
    
    func extractAudio(from videoURL: URL, outputURL: URL, progressHandler: @escaping (Double) -> Void) async throws {
        let asset = AVURLAsset(url: videoURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        
        guard let audioTrack = audioTracks.first else {
            throw NSError(domain: "AudioVideoToolkit", code: -3, userInfo: [NSLocalizedDescriptionKey: "No audio track found"])
        }
        
        let composition = AVMutableComposition()
        let audioCompTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        let duration = try await asset.load(.duration)
        try audioCompTrack?.insertTimeRange(CMTimeRangeMake(start: .zero, duration: duration), of: audioTrack, at: .zero)
        
        let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A)!
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        
        try await performExport(session: exportSession, progressHandler: progressHandler)
    }
    
    func extractVideo(from videoURL: URL, outputURL: URL, progressHandler: @escaping (Double) -> Void) async throws {
        let asset = AVURLAsset(url: videoURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        
        guard let videoTrack = videoTracks.first else {
            throw NSError(domain: "AudioVideoToolkit", code: -4, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        
        let composition = AVMutableComposition()
        let videoCompTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        let duration = try await asset.load(.duration)
        try videoCompTrack?.insertTimeRange(CMTimeRangeMake(start: .zero, duration: duration), of: videoTrack, at: .zero)
        
        let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)!
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        
        try await performExport(session: exportSession, progressHandler: progressHandler)
    }
    
    private func export(
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition?,
        outputURL: URL,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)!
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        
        if let videoComposition {
            exportSession.videoComposition = videoComposition
        }
        
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
                    continuation.resume(throwing: NSError(domain: "AudioVideoToolkit", code: -5, userInfo: [NSLocalizedDescriptionKey: "Export failed"]))
                }
            }
        }
    }
}
