import AppKit
import AVKit
import SwiftUI

// MARK: - Detection Mode (moved out of DuplicateVideoView for shared access)

enum VideoDetectionMode: String, CaseIterable {
	case quick = "快速检测"
	case deep = "精细检测"
}

// MARK: - Scan Model

/// Owns all scan state and execution for DuplicateVideoView.
/// Lives in RootView as @StateObject; survives view deinit so a running
/// scan continues when the user switches to another feature and back.
@MainActor
final class DuplicateVideoScanModel: ObservableObject {

	// --- Shared ---
	@Published var folderURL: URL?
	@Published var statusText = "请选择一个文件夹（会递归扫描子文件夹）"
	@Published var isWorking = false
	@Published var processedCount = 0
	@Published var totalCount = 0
	@Published var errorMessage: String?
	@Published var detectionMode: VideoDetectionMode = .quick

	// --- Quick mode ---
	@Published var quickGroups: [DuplicateVideoGroup] = []

	// --- Deep mode ---
	@Published var cacheDirectory: URL?
	@Published var createSubfolder = true
	@Published var debugMode = false
	@Published var sampleFraction: Double = 1.0
	@Published var deepClusters: [SimilarVideoClusterer.Cluster] = []
	@Published var deepPhase: String = ""

	// MARK: - Computed

	var effectiveCacheDir: URL? {
		guard let folder = folderURL else { return nil }
		let base = cacheDirectory ?? folder
		if createSubfolder {
			let sub = base.appendingPathComponent("hash_cache", isDirectory: true)
			try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
			return sub
		} else {
			return base
		}
	}

	private let videoExts: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv"]
	private var scanTask: Task<Void, Never>?

	// MARK: - Public API

	/// Start a scan. Returns immediately; progress updates via @Published properties.
	func startScan() {
		guard folderURL != nil else { return }
		scanTask?.cancel()
		clearResults()

		isWorking = true
		statusText = "正在扫描文件夹…"
		deepPhase = "读取文件列表中"

		let capturedFolderURL = folderURL
		let capturedMode = detectionMode

		scanTask = Task { @MainActor in
			guard await WorkManager.shared.requestStart(.duplicateVideos) else {
				self.isWorking = false
				return
			}
			defer {
				self.isWorking = false
				WorkManager.shared.finishWork(.duplicateVideos)
			}

			// Phase 0: scan files in background
			let files = await Task.detached(priority: .userInitiated) { [videoExts] in
				FolderScanner.scanFiles(in: capturedFolderURL!, allowedExtensions: videoExts)
			}.value

			guard !Task.isCancelled else { return }
			guard !files.isEmpty else {
				statusText = "未找到视频文件"
				return
			}

			totalCount = files.count
			processedCount = 0

			switch capturedMode {
			case .quick: await runQuick(files: files)
			case .deep:  await runDeep(files: files)
			}
		}
	}

	/// Cancel a running scan.
	func cancelScan() {
		scanTask?.cancel()
		scanTask = nil
		isWorking = false
		statusText = "扫描已取消"
	}

	/// Clear results without cancelling (used before new scan / mode switch).
	func clearResults() {
		quickGroups = []
		deepClusters = []
		deepPhase = ""
		errorMessage = nil
		processedCount = 0
		totalCount = 0
	}

	// MARK: - Quick Mode

	private func runQuick(files: [URL]) async {
		statusText = "扫描中：仅按 时长/大小/分辨率 分组"

		var map: [String: (desc: String, urls: [URL])] = [:]

		for (idx, url) in files.enumerated() {
			do {
				let attr = try FileManager.default.attributesOfItem(atPath: url.path)
				let fileSize = (attr[.size] as? NSNumber)?.int64Value ?? 0
				let info = try await VideoToolkit.readDisplayInfo(url: url)
				let durationMs = Int((info.durationSeconds * 1000.0).rounded())
				let w = Int(info.displaySize.width.rounded())
				let h = Int(info.displaySize.height.rounded())
				let key = "\(durationMs)|\(fileSize)|\(w)x\(h)"
				let desc = "时长=\(durationMs)ms 大小=\(fileSize)B 分辨率=\(w)x\(h)"
				map[key, default: (desc: desc, urls: [])].urls.append(url)
			} catch {}

			if idx % 5 == 0 || idx + 1 == files.count {
				processedCount = idx + 1
			}

			if Task.isCancelled { return }
		}

		let groups = map
			.filter { $0.value.urls.count > 1 }
			.map { DuplicateVideoGroup(id: $0.key, keyDescription: $0.value.desc, files: $0.value.urls.sorted { $0.path < $1.path }) }
			.sorted { $0.files.count > $1.files.count }

		quickGroups = groups
		statusText = "完成：共扫描 \(files.count) 个视频，发现 \(groups.count) 组重复"
	}

	// MARK: - Deep Mode

	private func runDeep(files: [URL]) async {
		totalCount = files.count
		processedCount = 0
		statusText = "扫描中：\(files.count) 个视频文件"
		deepPhase = "准备哈希缓存…"

		guard let cacheDir = effectiveCacheDir else {
			errorMessage = "无法确定缓存路径"
			return
		}

		let effectiveFraction: Double = debugMode ? min(sampleFraction, 1.0) : 1.0
		let workingCount: Int = effectiveFraction >= 1.0 ? files.count : max(1, Int(Double(files.count) * effectiveFraction))

		deepPhase = "哈希提取: 0/\(workingCount)"

		guard !Task.isCancelled else { return }

		var extractionResult: (VideoHashCache.CacheData, [VideoHashCache.ExtractedHashes])?
		do {
			extractionResult = try await VideoHashCache.buildOrUpdateCache(
				videos: files,
				cacheDir: cacheDir,
				sampleFraction: effectiveFraction,
				skipCacheSave: debugMode,
				progress: { [weak self] current, total, phase in
					Task { @MainActor [weak self] in
						guard let self else { return }
						self.processedCount = current
						self.totalCount = total
						self.deepPhase = phase
					}
				}
			)
		} catch {
			errorMessage = "哈希提取失败: \(error.localizedDescription)"
			return
		}

		guard !Task.isCancelled else { return }

		guard let (_, extracted) = extractionResult, extracted.count >= 2 else {
			statusText = "完成：需要至少 2 个有效视频才能聚类"
			return
		}

		deepPhase = "聚类计算中…"

		guard !Task.isCancelled else { return }

		let items = extracted.map { hash in
			SimilarVideoClusterer.VideoItem(
				url: hash.url,
				fileSize: hash.fileSize,
				durationSeconds: hash.durationSeconds,
				resolution: hash.resolution,
				bitrate: hash.bitrate,
				frameRate: hash.frameRate,
				creationDate: hash.creationDate,
				modificationDate: hash.modificationDate,
				segmentHashes: hash.segmentHashes
			)
		}

		let clusters = SimilarVideoClusterer.cluster(items)
		let sampledSuffix = debugMode ? "（调试模式）" : ""

		deepClusters = clusters
		deepPhase = ""
		statusText = "完成：共扫描 \(files.count) 个视频，发现 \(clusters.count) 组内容相似\(sampledSuffix)"
	}
}
