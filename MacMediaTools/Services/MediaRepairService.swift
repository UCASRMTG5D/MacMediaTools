import AVFoundation
import CoreServices
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - 问题大类（按图片 / 视频）

enum MediaRepairCategory: String, CaseIterable, Identifiable {
	case image = "图片"
	case video = "视频"

	var id: String { rawValue }

	var icon: String {
		switch self {
		case .image: return "photo"
		case .video: return "film"
		}
	}
}

// MARK: - 具体修复动作（视频分为改扩展名 / 无损 remux 两类，均不转码）

enum MediaRepairAction: String, Sendable {
	case renameImage // 图片：改扩展名（零画质损失）
	case renameVideo // 视频：改扩展名（容器/扩展名写错）
	case remuxVideo // 视频：无损 remux 到 QuickTime 兼容容器（不重编码）
}

// MARK: - 检测结果项

struct MediaRepairItem: Identifiable, Sendable {
	let id = UUID()
	let url: URL
	let category: MediaRepairCategory
	let action: MediaRepairAction
	let currentLabel: String // 人类可读的问题描述
	let suggestedAction: String // 建议的修复动作
	let targetExtension: String? // 改扩展名时的目标扩展名；remux 为 nil
}

// MARK: - 检测结果

struct MediaRepairResult: Sendable {
	let imageItems: [MediaRepairItem]
	let videoItems: [MediaRepairItem]
	let scannedCount: Int
	let skippedCount: Int // 不在检测范围内，或已无问题的文件数
}

// MARK: - 检测范围

enum MediaRepairScope: String, CaseIterable, Identifiable {
	case all = "全部"
	case image = "仅图片"
	case video = "仅视频"

	var id: String { rawValue }
}

// MARK: - 错误

enum MediaRepairError: LocalizedError {
	case remuxFailed(String)
	case unsupportedFormat
	case noVideoTrack
	case renameFailed(String)

	var errorDescription: String? {
		switch self {
		case .remuxFailed(let message): return "无损封装失败：\(message)"
		case .unsupportedFormat: return "不支持的文件格式"
		case .noVideoTrack: return "未找到视频轨道"
		case .renameFailed(let message): return "重命名失败：\(message)"
		}
	}
}

// MARK: - 媒体修复服务（无 UI 依赖，不转码）

enum MediaRepair {

	// 真实格式 UTI -> 规范扩展名
	private static let utiToExtension: [String: String] = [
		"public.jpeg": "jpeg",
		"public.png": "png",
		"public.heic": "heic",
		"public.heif": "heif",
		"public.tiff": "tiff",
		"com.compuserve.gif": "gif",
		"org.webmproject.webp": "webp",
		"public.webp": "webp",
	]

	// QuickTime 原生可打开的容器扩展名（remux 目标）
	private static let quickTimeContainers: Set<String> = ["mp4", "mov", "m4v"]

	// 支持的图片/视频扩展名（与 MediaFileExtensions 保持一致）
	private static let photoExtensions: Set<String> = [
		"jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp", "gif", "webp",
	]
	private static let videoExtensions: Set<String> = [
		"mp4", "mov", "m4v", "avi", "mkv", "wmv", "flv", "webm", "3gp",
	]

	// MARK: 检测（只读，不修改任何文件）

	static func detect(urls: [URL], scope: MediaRepairScope = .all) async -> MediaRepairResult {
		await Task.detached(priority: .userInitiated) {
			let scanImage = scope == .all || scope == .image
			let scanVideo = scope == .all || scope == .video

			// 并发分析：每个文件独立检测，放到后台 TaskGroup 并行执行，
			// 避免在大文件夹上串行读取导致主线程等待 / 进度缓慢。
			let found = await withTaskGroup(of: MediaRepairItem?.self) { group in
				for url in urls {
					group.addTask(priority: .userInitiated) {
						let ext = url.pathExtension.lowercased()
						if scanImage, Self.photoExtensions.contains(ext) {
							return detectImageIssue(url: url, currentExt: ext)
						} else if scanVideo, Self.videoExtensions.contains(ext) {
							return await detectVideoIssue(url: url, currentExt: ext)
						}
						return nil
					}
				}
				var collected: [MediaRepairItem?] = []
				for await item in group {
					collected.append(item)
				}
				return collected
			}

			var imageItems: [MediaRepairItem] = []
			var videoItems: [MediaRepairItem] = []
			var scanned = 0
			var skipped = 0
			for item in found {
				scanned += 1
				if let item {
					switch item.category {
					case .image: imageItems.append(item)
					case .video: videoItems.append(item)
					}
				} else {
					skipped += 1
				}
			}

			return MediaRepairResult(
				imageItems: imageItems,
				videoItems: videoItems,
				scannedCount: scanned,
				skippedCount: skipped
			)
		}.value
	}

	private static func detectImageIssue(url: URL, currentExt: String) -> MediaRepairItem? {
		guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
		      let uti = CGImageSourceGetType(source) as String? else {
			return nil
		}
		guard let realExt = utiToExtension[uti] else {
			// 无法识别真实格式，不标记
			return nil
		}
		if realExt == currentExt {
			return nil
		}
		let label = "实际格式 \(realExt.uppercased())，扩展名误标为 .\(currentExt)"
		let action = "改扩展名为 .\(realExt)（零画质损失）"
		return MediaRepairItem(
			url: url,
			category: .image,
			action: .renameImage,
			currentLabel: label,
			suggestedAction: action,
			targetExtension: realExt
		)
	}

	private static func detectVideoIssue(url: URL, currentExt: String) async -> MediaRepairItem? {
		let asset = AVURLAsset(url: url)
		guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
			return nil
		}
		guard let desc = try? await track.load(.formatDescriptions).first else {
			return nil
		}
		let fourcc = CMFormatDescriptionGetMediaSubType(desc)
		let codec = fourCCString(fourcc).lowercased()

		// 情况一：扩展名写错（容器实际是 QuickTime 兼容的，但扩展名标成了非常规后缀）
		// 例如内容是 MP4 却命名为 .avi —— 只需改扩展名即可，无需 remux。
		if quickTimeContainers.contains(currentExt) {
			// 容器本身 QuickTime 可打开，编码也基本可控，无需修复
			return nil
		}

		// 情况二：容器是 QuickTime 打不开的（avi/mkv/wmv/flv/webm/3gp）
		// 修复方式：无损 remux 到 MP4（拷贝音视频流，不重编码）
		let codecName = codecDisplayName(codec)
		let label = "编码 \(codecName) 封装于 .\(currentExt)，QuickTime 无法打开"
		let action = "无损封装为 .mp4（不转码，拷贝音视频流）"
		return MediaRepairItem(
			url: url,
			category: .video,
			action: .remuxVideo,
			currentLabel: label,
			suggestedAction: action,
			targetExtension: nil
		)
	}

	private static func fourCCString(_ value: FourCharCode) -> String {
		let bytes = [
			UInt8((value >> 24) & 0xFF),
			UInt8((value >> 16) & 0xFF),
			UInt8((value >> 8) & 0xFF),
			UInt8(value & 0xFF),
		]
		return String(bytes: bytes, encoding: .ascii) ?? "\(value)"
	}

	private static func codecDisplayName(_ codec: String) -> String {
		switch codec {
		case "hvc1", "hev1": return "HEVC"
		case "av01": return "AV1"
		case "vp09": return "VP9"
		case "avc1", "avc3", "h264": return "H.264"
		case "mp4v": return "MPEG-4"
		case "m4v ": return "MPEG-4"
		default: return codec.uppercased()
		}
	}

	// MARK: 修复（仅处理传入的项，需先经人工确认；不转码）

	static func repair(
		_ item: MediaRepairItem,
		progress: (@Sendable (Double) -> Void)? = nil
	) async throws {
		progress?(0.0)
		switch item.action {
		case .renameImage, .renameVideo:
			try rename(item)
		case .remuxVideo:
			try await remuxVideo(item)
		}
		progress?(1.0)
	}

	private static func rename(_ item: MediaRepairItem) throws {
		guard let targetExt = item.targetExtension else {
			throw MediaRepairError.unsupportedFormat
		}
		let newURL = uniqueURL(for: item.url, targetExtension: targetExt)
		do {
			try FileManager.default.moveItem(at: item.url, to: newURL)
		} catch {
			throw MediaRepairError.renameFailed(error.localizedDescription)
		}
	}

	/// 无损 remux：用 AVAssetExportSession + Passthrough 预设拷贝音视频流到 MP4，不重编码
	private static func remuxVideo(_ item: MediaRepairItem) async throws {
		let asset = AVURLAsset(url: item.url)
		guard let _ = try? await asset.loadTracks(withMediaType: .video).first else {
			throw MediaRepairError.noVideoTrack
		}

		let outputURL = uniqueURL(for: item.url, targetExtension: "mp4")
		try? FileManager.default.removeItem(at: outputURL)

		// Passthrough：尽可能流拷贝，不做转码
		guard let session = AVAssetExportSession(
			asset: asset,
			presetName: AVAssetExportPresetPassthrough
		) else {
			throw MediaRepairError.remuxFailed("无法创建导出会话")
		}
		session.outputURL = outputURL
		session.outputFileType = .mp4
		session.shouldOptimizeForNetworkUse = true

		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			session.exportAsynchronously {
				switch session.status {
				case .completed:
					continuation.resume()
				case .failed:
					continuation.resume(throwing: MediaRepairError.remuxFailed(
						session.error?.localizedDescription ?? "未知错误"))
				case .cancelled:
					continuation.resume(throwing: MediaRepairError.remuxFailed("已取消"))
				default:
					continuation.resume(throwing: MediaRepairError.remuxFailed(
						"导出状态异常：\(session.status.rawValue)"))
				}
			}
		}
	}

	/// 生成不覆盖已有文件的目标 URL：同名则追加 _repaired 编号
	private static func uniqueURL(for url: URL, targetExtension: String) -> URL {
		let parent = url.deletingLastPathComponent()
		let base = url.deletingPathExtension().lastPathComponent
		var candidate = parent.appendingPathComponent("\(base).\(targetExtension)")
		if !FileManager.default.fileExists(atPath: candidate.path) {
			return candidate
		}
		var counter = 1
		repeat {
			candidate = parent.appendingPathComponent("\(base)_repaired\(counter).\(targetExtension)")
			counter += 1
		} while FileManager.default.fileExists(atPath: candidate.path)
		return candidate
	}
}
