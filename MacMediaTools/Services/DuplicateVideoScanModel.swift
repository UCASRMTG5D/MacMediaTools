import AppKit
import AVKit
import Combine

// MARK: - Detection Mode (moved out of DuplicateVideoView for shared access)

public enum VideoDetectionMode: String, CaseIterable, Sendable {
	case quick = "快速检测"
	case deep = "精细检测"
}

// MARK: - Scan Model

/// Owns all scan state and execution for DuplicateVideoView.
/// Lives in RootView as @StateObject; survives view deinit so a running
/// scan continues when the user switches to another feature and back.
@MainActor
final class DuplicateVideoScanModel: BaseObservableService {
	
	// --- Shared ---
	@Published var folderURL: URL?
	@Published var statusText = "请选择一个文件夹（会递归扫描子文件夹）"
	@Published var processedCount = 0
	@Published var totalCount = 0
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
			let sub = base.appendingPathComponent("hash_cache/video", isDirectory: true)
			try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
			return sub
		} else {
			return base
		}
	}
	
	private let videoExts: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "gif"]
	
	private func countGIFs(in files: [URL]) -> Int {
		files.filter { $0.pathExtension.lowercased() == "gif" }.count
	}
	
	private var scanTask: Task<Void, Never>?
	
	// MARK: - Public API
	
	/// Start a scan. Returns immediately; progress updates via @Published properties.
	func startScan() {
		guard folderURL != nil else { return }
		scanTask?.cancel()
		clear()
		
		let targetFolder = folderURL  // capture for background access
		
		scanTask = runAsync(priority: .userInitiated) { [weak self] reportProgress in
			guard let self else { return }

			// 冲突仲裁与占用登记由 View 层在调用前完成（requestStart + registerStarted）。
			// 此处仅负责在任务结束时清除登记。
			defer {
				WorkManager.shared.finishWork(.duplicateVideos)
			}

			await MainActor.run {
				self.isWorking = true
				self.statusText = "正在扫描文件夹…"
				self.deepPhase = "读取文件列表中"
			}
			
			// Phase 0: scan files in background
			let files = await Task.detached(priority: .userInitiated) { [videoExts] in
				FolderScanner.scanFiles(in: targetFolder!, allowedExtensions: videoExts)
			}.value
			
			guard !Task.isCancelled else { return }
			guard !files.isEmpty else {
				await MainActor.run {
					self.statusText = "未找到视频或GIF文件"
				}
				return
			}
			
			await MainActor.run {
				self.progress = ProgressInfo(current: 0, total: files.count, phase: "准备中")
			}
			
			switch self.detectionMode {
			case .quick: await self.runQuick(files: files) { info in
				self.progress = info
			}
			case .deep:  await self.runDeep(files: files) { info in
				self.progress = info
			}
			}
		}
	}
	
	/// Cancel a running scan.
	func cancelScan() {
		cancel()
	}
	
	/// 清除结果（不取消）
	func clearResults() {
		quickGroups = []
		deepClusters = []
		deepPhase = ""
		errorMessage = nil
		progress = .zero
	}
	
	// MARK: - Quick Mode
	
	private func runQuick(files: [URL], reportProgress: @escaping (ProgressInfo) -> Void) async {
		await MainActor.run {
			statusText = "扫描中：仅按 时长/大小/分辨率 分组"
		}
		
		var map: [String: (desc: String, urls: [URL])] = [:]
		
		for (idx, url) in files.enumerated() {
			guard !Task.isCancelled else { return }
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
			} catch { }
			
			if idx % 5 == 0 || idx + 1 == files.count {
				await MainActor.run { }
				reportProgress(ProgressInfo(current: idx + 1, total: files.count, phase: "快速分组中"))
			}
		}
		
		let groups = map
			.filter { $0.value.urls.count > 1 }
			.map { DuplicateVideoGroup(id: $0.key, keyDescription: $0.value.desc, files: $0.value.urls.sorted { $0.path < $1.path }) }
			.sorted { $0.files.count > $1.files.count }
		
		await MainActor.run {
			quickGroups = groups
			let gifCount = files.filter { $0.pathExtension.lowercased() == "gif" }.count
			let videoCount = files.count - gifCount
			if gifCount > 0 {
				statusText = "完成：共扫描 \(videoCount) 个视频、\(gifCount) 个GIF，发现 \(groups.count) 组重复"
			} else {
				statusText = "完成：共扫描 \(files.count) 个视频，发现 \(groups.count) 组重复"
			}
		}
	}
	
	// MARK: - Deep Mode
	
	private func runDeep(files: [URL], reportProgress: @escaping (ProgressInfo) -> Void) async {
		await MainActor.run {
			let scGifCount = files.filter { $0.pathExtension.lowercased() == "gif" }.count
			let scVideoCount = files.count - scGifCount
			if scGifCount > 0 {
				statusText = "扫描中：\(scVideoCount) 个视频、\(scGifCount) 个GIF"
			} else {
				statusText = "扫描中：\(files.count) 个视频文件"
			}
			deepPhase = "准备哈希缓存…"
		}
		
		guard let cacheDir = effectiveCacheDir else {
			await MainActor.run { errorMessage = "无法确定缓存路径" }
			return
		}
		
		let effectiveFraction: Double = debugMode ? min(sampleFraction, 1.0) : 1.0
		let workingCount: Int = effectiveFraction >= 1.0 ? files.count : max(1, Int(Double(files.count) * effectiveFraction))
		
		await MainActor.run {
			deepPhase = "哈希提取: 0/\(workingCount)"
		}
		
		guard !Task.isCancelled else { return }
		
		var extractionResult: (MediaHashCache.CacheData, [MediaHashCache.ExtractedHashes])?
		do {
			extractionResult = try await MediaHashCache.buildOrUpdateCache(
				videos: files,
				cacheDir: cacheDir,
				sampleFraction: effectiveFraction,
				skipCacheSave: debugMode,
				progress: { [weak self] current, total, phase in
					Task { @MainActor [weak self] in
						guard let self else { return }
						self.progress = ProgressInfo(current: current, total: total, phase: phase)
						self.deepPhase = phase
					}
				}
			)
		} catch {
			await MainActor.run { errorMessage = "哈希提取失败: \(error.localizedDescription)" }
			return
		}
		
		guard !Task.isCancelled else { return }
		
		guard let (_, extracted) = extractionResult, extracted.count >= 2 else {
			await MainActor.run { statusText = "完成：需要至少 2 个有效媒体文件才能聚类" }
			return
		}
		
		await MainActor.run { deepPhase = "聚类计算中…" }
		
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
		
		await MainActor.run {
			deepClusters = clusters
			deepPhase = ""
			let scGifCount = files.filter { $0.pathExtension.lowercased() == "gif" }.count
			let scVideoCount = files.count - scGifCount
			if scGifCount > 0 {
				statusText = "完成：共扫描 \(scVideoCount) 个视频、\(scGifCount) 个GIF，发现 \(clusters.count) 组内容相似"
			} else {
				statusText = "完成：共扫描 \(files.count) 个视频，发现 \(clusters.count) 组内容相似"
			}
		}
	}
}