import AVFoundation
import CryptoKit
import Foundation

struct DuplicateGroup: Identifiable {
	let id: String
	let mediaType: MediaType
	let matchReason: String
	let files: [URL]

	enum MediaType {
		case photo
		case video
	}
}

struct VideoMatchInfo {
	let durationMs: Int
	let fileSize: Int64
	let resolution: (width: Int, height: Int)
	let hasAudio: Bool
	let codec: String?

	var key: String {
		"\(durationMs)|\(fileSize)|\(resolution.width)x\(resolution.height)"
	}

	var description: String {
		let durationSec = Double(durationMs) / 1000.0
		let sizeStr = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
		return String(format: "时长=%.1fs 大小=%@ 分辨率=%dx%d", durationSec, sizeStr, resolution.width, resolution.height)
	}
}

actor DuplicateDetector {
	static let shared = DuplicateDetector()

	private let photoExts: Set<String> = MediaFileExtensions.photo
	private let videoExts: Set<String> = MediaFileExtensions.video

	func isPhotoFile(_ url: URL) -> Bool {
		photoExts.contains(url.pathExtension.lowercased())
	}

	func isVideoFile(_ url: URL) -> Bool {
		videoExts.contains(url.pathExtension.lowercased())
	}

	func isMediaFile(_ url: URL) -> Bool {
		isPhotoFile(url) || isVideoFile(url)
	}

	func scanMediaFiles(in folder: URL) -> [URL] {
		let fm = FileManager.default
		let keys: [URLResourceKey] = [.isRegularFileKey, .nameKey]
		guard let enumerator = fm.enumerator(
			at: folder,
			includingPropertiesForKeys: keys,
			options: [.skipsHiddenFiles],
			errorHandler: nil
		) else {
			return []
		}

		var results: [URL] = []
		for case let url as URL in enumerator {
			guard let values = try? url.resourceValues(forKeys: Set(keys)),
				  values.isRegularFile == true else { continue }
			if isMediaFile(url) {
				results.append(url)
			}
		}
		return results
	}

	func findDuplicatePhotos(in files: [URL], progressHandler: ((Int, Int) -> Void)? = nil) async -> [DuplicateGroup] {
		var hashMap: [String: [URL]] = [:]
		let total = files.count

		for (idx, url) in files.enumerated() {
			progressHandler?(idx + 1, total)

			do {
				let hash = try await computePhotoHash(url: url)
				hashMap[hash, default: []].append(url)
			} catch {
				continue
			}
		}

		return hashMap
			.filter { $0.value.count > 1 }
			.map { DuplicateGroup(id: $0.key, mediaType: .photo, matchReason: "SHA256哈希值完全相同", files: $0.value.sorted { $0.path < $1.path }) }
			.sorted { $0.files.count > $1.files.count }
	}

	func findDuplicateVideos(in files: [URL], progressHandler: ((Int, Int) -> Void)? = nil) async -> [DuplicateGroup] {
		var keyMap: [String: (info: VideoMatchInfo, urls: [URL])] = [:]
		let total = files.count

		for (idx, url) in files.enumerated() {
			progressHandler?(idx + 1, total)

			do {
				let info = try await computeVideoInfo(url: url)
				let key = info.key
				if keyMap[key] == nil {
					keyMap[key] = (info: info, urls: [])
				}
				keyMap[key]?.urls.append(url)
			} catch {
				continue
			}
		}

		return keyMap
			.filter { $0.value.urls.count > 1 }
			.map { DuplicateGroup(id: $0.key, mediaType: .video, matchReason: $0.value.info.description, files: $0.value.urls.sorted { $0.path < $1.path }) }
			.sorted { $0.files.count > $1.files.count }
	}

	func findAllDuplicates(in folder: URL, progressHandler: ((Int, Int, String) -> Void)? = nil) async -> [DuplicateGroup] {
		let files = scanMediaFiles(in: folder)

		let photos = files.filter { isPhotoFile($0) }
		let videos = files.filter { isVideoFile($0) }

		var allDuplicates: [DuplicateGroup] = []

		if !photos.isEmpty {
			progressHandler?(0, photos.count + videos.count, "检测重复照片…")
			let photoDupes = await findDuplicatePhotos(in: photos) { current, total in
				progressHandler?(current, photos.count + videos.count, "检测重复照片…")
			}
			allDuplicates.append(contentsOf: photoDupes)
		}

		if !videos.isEmpty {
			progressHandler?(photos.count, photos.count + videos.count, "检测重复视频…")
			let videoDupes = await findDuplicateVideos(in: videos) { current, total in
				progressHandler?(photos.count + current, photos.count + videos.count, "检测重复视频…")
			}
			allDuplicates.append(contentsOf: videoDupes)
		}

		return allDuplicates.sorted { $0.files.count > $1.files.count }
	}

	func computePhotoHash(url: URL) async throws -> String {
		return try FileHasher.sha256(url: url)
	}

	func computeVideoInfo(url: URL) async throws -> VideoMatchInfo {
		let asset = AVURLAsset(url: url)

		let duration = try await asset.load(.duration)
		let durationMs = Int((duration.seconds * 1000.0).rounded())

		let attr = try FileManager.default.attributesOfItem(atPath: url.path)
		let fileSize = (attr[.size] as? NSNumber)?.int64Value ?? 0

		let videoTracks = try await asset.loadTracks(withMediaType: .video)
		let audioTracks = try await asset.loadTracks(withMediaType: .audio)

		var resolution = (width: 0, height: 0)
		var codec: String?

		if let videoTrack = videoTracks.first {
			let size = try await videoTrack.load(.naturalSize)
			resolution = (width: Int(size.width.rounded()), height: Int(size.height.rounded()))

			if let formatDescriptions = try? await videoTrack.load(.formatDescriptions),
			   let formatDesc = formatDescriptions.first {
				let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc)
				codec = fourCharCodeToString(mediaSubType)
			}
		}

		return VideoMatchInfo(
			durationMs: durationMs,
			fileSize: fileSize,
			resolution: resolution,
			hasAudio: !audioTracks.isEmpty,
			codec: codec
		)
	}

	private func fourCharCodeToString(_ code: FourCharCode) -> String {
		let bytes: [CChar] = [
			CChar(truncatingIfNeeded: (code >> 24) & 0xFF),
			CChar(truncatingIfNeeded: (code >> 16) & 0xFF),
			CChar(truncatingIfNeeded: (code >> 8) & 0xFF),
			CChar(truncatingIfNeeded: code & 0xFF),
			0
		]
		return String(cString: bytes)
	}

	enum DuplicateDetectorError: Error, LocalizedError {
		case fileAccessFailed(String)
		case invalidMediaFile
		case videoInfoReadFailed

		var errorDescription: String? {
			switch self {
			case .fileAccessFailed(let path): return "无法访问文件: \(path)"
			case .invalidMediaFile: return "无效的媒体文件"
			case .videoInfoReadFailed: return "无法读取视频信息"
			}
		}
	}
}