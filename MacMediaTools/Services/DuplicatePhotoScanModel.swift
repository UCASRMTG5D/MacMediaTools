import AppKit
import Combine

// MARK: - Detection Mode

public enum PhotoDetectionMode: String, CaseIterable, Sendable {
	case quick = "快速检测"
	case deep = "精细检测"
}

// MARK: - Scan Model

/// 持有 DuplicatePhotoView 的所有扫描状态与执行逻辑。
/// 由 RootView 以 @StateObject 持有，切换功能再回来时扫描继续运行。
@MainActor
final class DuplicatePhotoScanModel: BaseObservableService {
	
	// --- 通用 ---
	@Published var folderURL: URL?
	@Published var statusText = "请选择一个文件夹（会递归扫描子文件夹）"
	@Published var processedCount = 0
	@Published var totalCount = 0
	@Published var detectionMode: PhotoDetectionMode = .quick
	
	// --- 快速模式 ---
	@Published var quickGroups: [DuplicatePhotoGroup] = []
	
	// --- 精细模式 ---
	@Published var cacheDirectory: URL?
	@Published var createSubfolder = true
	@Published var debugMode = false
	@Published var sampleFraction: Double = 1.0
	/// 相似度严格度旋钮（0=最宽松，1=最严格）。界面调节此值，内部按比例映射为 dHash/pHash 各自阈值。
	@Published var strictness: Double = 0.94
	@Published var deepClusters: [SimilarPhotoClusterer.PhotoCluster] = []
	@Published var deepPhase: String = ""
	@Published var hashExtractionPhase = true  // true=哈希提取中, false=聚类计算中
	
	// MARK: - Computed
	
	var effectiveCacheDir: URL? {
		guard let folder = folderURL else { return nil }
		let base = cacheDirectory ?? folder
		if createSubfolder {
			let sub = base.appendingPathComponent("hash_cache/picture", isDirectory: true)
			try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
			return sub
		} else {
			return base
		}
	}

	/// 将严格度旋钮映射为 dHash / pHash 各自的 Hamming 阈值。
	/// strictness=0 最宽松（阈值最大），strictness=1 最严格（阈值最小）。
	func mappedHashThresholds() -> (dHash: Int, pHash: Int) {
		let s = min(max(strictness, 0), 1)
		let dHash = Int(((1 - s) * 20 + 3).rounded())
		let pHash = Int(((1 - s) * 16 + 2).rounded())
		return (dHash, pHash)
	}
	
	private let photoExts: Set<String> = MediaFileExtensions.photo
	
	private var scanTask: Task<Void, Never>?
	
	// MARK: - Public API
	
	/// 开始扫描。立即返回；进度通过 @Published 属性更新。
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
			// 冲突仲裁与占用登记由 View 层在调用 startScan 前完成（requestStart + registerStarted）。
			// 此处仅负责在任务结束时清除登记。
			defer {
				self.isWorking = false
				WorkManager.shared.finishWork(.duplicatePhotos)
			}

			let files = await Task.detached(priority: .userInitiated) { [photoExts] in
				FolderScanner.scanFiles(in: capturedFolderURL!, allowedExtensions: photoExts)
			}.value
			
			guard !Task.isCancelled else { return }
			guard !files.isEmpty else {
				statusText = "未找到图片文件"
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
	
	/// 取消正在进行的扫描
	func cancelScan() {
		scanTask?.cancel()
		scanTask = nil
		isWorking = false
		statusText = "扫描已取消"
	}
	
	/// 清除结果（不取消）
	func clearResults() {
		quickGroups = []
		deepClusters = []
		deepPhase = ""
		errorMessage = nil
		processedCount = 0
		totalCount = 0
	}

	/// 清除照片哈希缓存（删除 hash_cache/picture/ 目录）
	func clearPhotoCache() {
		guard let cacheDir = effectiveCacheDir else {
			errorMessage = "无法确定缓存路径"
			return
		}
		try? FileManager.default.removeItem(at: cacheDir)
		statusText = "照片缓存已清除，下次扫描将重新计算哈希"
	}
	
	// MARK: - Quick Mode (SHA256)
	
	private func runQuick(files: [URL]) async {
		statusText = "扫描中：将按 SHA256 判定“完全相同文件”"
		
		var map: [String: [URL]] = [:]
		var errorCount = 0
		
		for (idx, url) in files.enumerated() {
			if Task.isCancelled { return }
			do {
				let hash = try FileHasher.sha256(url: url)
				map[hash, default: []].append(url)
			} catch { errorCount += 1 }
			
			if idx % 10 == 0 || idx + 1 == files.count {
				processedCount = idx + 1
			}
		}
		
		let groups = map
			.filter { $0.value.count > 1 }
			.map { DuplicatePhotoGroup(id: $0.key, files: $0.value.sorted { $0.path < $1.path }) }
			.sorted { $0.files.count > $1.files.count }
		
		quickGroups = groups
		statusText = "完成：共扫描 \(files.count) 张照片，发现 \(groups.count) 组重复"
	}
	
	// MARK: - Deep Mode (dHash + Clustering)
	
	private func runDeep(files: [URL]) async {
		statusText = "扫描中：\(files.count) 张照片"
		deepPhase = "准备哈希缓存…"
		hashExtractionPhase = true
		
		guard let cacheDir = effectiveCacheDir else {
			errorMessage = "无法确定缓存路径"
			return
		}
		
		let effectiveFraction: Double = debugMode ? min(sampleFraction, 1.0) : 1.0
		let workingCount: Int = effectiveFraction >= 1.0 ? files.count : max(1, Int(Double(files.count) * effectiveFraction))
		
		deepPhase = "照片哈希提取: 0/\(workingCount)"
		
		guard !Task.isCancelled else { return }
		
		var extractionResult: (MediaHashCache.CacheData, [MediaHashCache.ExtractedHashes])?
		do {
			extractionResult = try await MediaHashCache.buildOrUpdatePhotoCache(
				photos: files,
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
			statusText = "完成：需要至少 2 张有效照片才能聚类"
			return
		}
		
		// 切换到聚类阶段
		hashExtractionPhase = false
		deepPhase = "聚类计算中…"
		
		// 在后台线程执行 O(n²) 聚类计算，避免阻塞主线程
		let items = extracted.compactMap { hash -> SimilarPhotoClusterer.PhotoItem? in
			guard let photoHash = hash.photoPHashes.first else { return nil }
			return SimilarPhotoClusterer.PhotoItem(
				url: hash.url,
				fileSize: hash.fileSize,
				modificationDate: hash.modificationDate,
				creationDate: hash.creationDate,
				resolution: hash.resolution,
				photoDHash: hash.photoDHash,
				photoHash: photoHash
			)
		}

		let (dHashThreshold, pHashThreshold) = mappedHashThresholds()

		let clusters = await Task.detached(priority: .userInitiated) {
			SimilarPhotoClusterer.cluster(items, dHashThreshold: dHashThreshold, pHashThreshold: pHashThreshold)
		}.value
		
		guard !Task.isCancelled else { return }
		
		let sampledSuffix = debugMode ? "（调试模式）" : ""
		
		await MainActor.run {
			self.deepClusters = clusters
			self.deepPhase = ""
			self.statusText = "完成：共扫描 \(files.count) 张照片，发现 \(clusters.count) 组内容相似\(sampledSuffix)"
		}
	}
	
	// MARK: - Delete (Quick)
	
	func deleteQuickPhoto(_ url: URL) {
		quickGroups = quickGroups.compactMap { group in
			let remaining = group.files.filter { $0 != url }
			guard remaining.count > 1 else { return nil }
			return DuplicatePhotoGroup(id: group.id, files: remaining)
		}
	}
	
	// MARK: - Delete (Deep)
	
	func deleteDeepPhoto(_ item: SimilarPhotoClusterer.PhotoClusterItem, from cluster: SimilarPhotoClusterer.PhotoCluster) {
		let clusterId = cluster.id
		deepClusters = deepClusters.compactMap { c in
			guard c.id == clusterId else { return c }
			let remaining = c.items.filter { $0.url != item.url }
			guard remaining.count >= 2 else { return nil }
			let meanDist = Double(remaining.reduce(0) { $0 + $1.hammingDistanceToCentroid }) / Double(remaining.count)
			let similarity = max(0, 1 - meanDist / 64.0)
			return SimilarPhotoClusterer.PhotoCluster(id: c.id, items: remaining, meanHammingDistance: meanDist, similarity: similarity)
		}
	}
	
	// MARK: - Ignore
	
	func ignoreQuickGroup(_ group: DuplicatePhotoGroup) {
		// 忽略逻辑由 View 层维护 Set 处理
	}
	
	func ignoreDeepCluster(_ cluster: SimilarPhotoClusterer.PhotoCluster) {
		// 忽略逻辑由 View 层维护 Set 处理
	}
}