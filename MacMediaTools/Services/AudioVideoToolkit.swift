import AVFoundation

enum AudioVideoToolkitError: LocalizedError {
    case unsupportedFileType
    case failedToLoadTracks
    case failedToCreateComposition
    case noAudioTrack
    case noVideoTrack
    case failedToCreateExportSession
    case exportFailed(String)
    case invalidSpeed

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType: return "Unsupported file type"
        case .failedToLoadTracks: return "Failed to load tracks"
        case .failedToCreateComposition: return "Failed to create composition tracks"
        case .noAudioTrack: return "No audio track found"
        case .noVideoTrack: return "No video track found"
        case .failedToCreateExportSession: return "Failed to create export session"
        case .exportFailed(let message): return "Export failed: \(message)"
        case .invalidSpeed: return "播放速度必须大于 0"
        }
    }
}

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

        throw AudioVideoToolkitError.unsupportedFileType
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
            throw AudioVideoToolkitError.failedToLoadTracks
        }

        let videoDuration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)

        guard settings.videoSpeed > 0, settings.audioSpeed > 0 else {
            throw AudioVideoToolkitError.invalidSpeed
        }

        let videoStart = clampedStartTime(settings.videoStartOffset, duration: videoDuration.seconds)
        let audioStart = clampedStartTime(settings.audioStartOffset, duration: audioDuration.seconds)
        let videoRange = safeTimeRange(startSeconds: videoStart, duration: videoDuration.seconds - videoStart)
        let audioRange = safeTimeRange(startSeconds: audioStart, duration: audioDuration.seconds - audioStart)

        let composition = AVMutableComposition()

        let videoCompTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioCompTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        guard let videoCompTrack, let audioCompTrack else {
            throw AudioVideoToolkitError.failedToCreateComposition
        }

        try videoCompTrack.insertTimeRange(videoRange, of: videoTrack, at: .zero)
        try audioCompTrack.insertTimeRange(audioRange, of: audioTrack, at: .zero)

        let videoScaledDuration = scaledDuration(of: videoRange.duration, speed: settings.videoSpeed)
        let audioScaledDuration = scaledDuration(of: audioRange.duration, speed: settings.audioSpeed)

        if settings.videoSpeed != 1.0 {
            try videoCompTrack.scaleTimeRange(CMTimeRange(start: .zero, duration: videoRange.duration), toDuration: videoScaledDuration)
        }

        if settings.audioSpeed != 1.0 {
            try audioCompTrack.scaleTimeRange(CMTimeRange(start: .zero, duration: audioRange.duration), toDuration: audioScaledDuration)
        }

        try await export(composition: composition, outputURL: outputURL, progressHandler: progressHandler)
    }

    func extractAudio(from videoURL: URL, outputURL: URL, progressHandler: @escaping (Double) -> Void) async throws {
        let asset = AVURLAsset(url: videoURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard let audioTrack = audioTracks.first else {
            throw AudioVideoToolkitError.noAudioTrack
        }

        let composition = AVMutableComposition()
        let audioCompTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        let duration = try await asset.load(.duration)
        try audioCompTrack?.insertTimeRange(CMTimeRangeMake(start: .zero, duration: duration), of: audioTrack, at: .zero)

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioVideoToolkitError.failedToCreateExportSession
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        try await performExport(session: exportSession, progressHandler: progressHandler)
    }

    func extractVideo(from videoURL: URL, outputURL: URL, progressHandler: @escaping (Double) -> Void) async throws {
        let asset = AVURLAsset(url: videoURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)

        guard let videoTrack = videoTracks.first else {
            throw AudioVideoToolkitError.noVideoTrack
        }

        let composition = AVMutableComposition()
        let videoCompTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)

        let duration = try await asset.load(.duration)
        try videoCompTrack?.insertTimeRange(CMTimeRangeMake(start: .zero, duration: duration), of: videoTrack, at: .zero)

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw AudioVideoToolkitError.failedToCreateExportSession
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov

        try await performExport(session: exportSession, progressHandler: progressHandler)
    }

    private func export(
        composition: AVMutableComposition,
        outputURL: URL,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw AudioVideoToolkitError.failedToCreateExportSession
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov

        try await performExport(session: exportSession, progressHandler: progressHandler)
    }

    private func clampedStartTime(_ start: Double, duration: Double) -> Double {
        guard duration.isFinite, duration > 0 else { return 0 }
        return min(max(start, 0), max(duration - 0.001, 0))
    }

    private func safeTimeRange(startSeconds: Double, duration: Double) -> CMTimeRange {
        let start = CMTime(seconds: startSeconds, preferredTimescale: 600)
        let clampedDuration = max(duration, 0)
        return CMTimeRange(start: start, duration: CMTime(seconds: clampedDuration, preferredTimescale: 600))
    }

    private func scaledDuration(of duration: CMTime, speed: Double) -> CMTime {
        guard speed != 1.0 else { return duration }
        return CMTime(seconds: duration.seconds / speed, preferredTimescale: duration.timescale == 0 ? 600 : duration.timescale)
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
                    continuation.resume(throwing: AudioVideoToolkitError.exportFailed("Export failed, unknown status"))
                }
            }
        }
    }
}
