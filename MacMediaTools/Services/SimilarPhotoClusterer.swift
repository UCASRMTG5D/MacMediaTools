import Foundation

// MARK: - 照片相似聚类（连通分量 + Hamming 距离）

enum SimilarPhotoClusterer {

	// MARK: - 公开类型

	/// 单张照片的哈希条目（dHash + pHash 融合）
	struct PhotoItem: Sendable {
		let url: URL
		let fileSize: UInt64
		let modificationDate: TimeInterval
		let creationDate: TimeInterval
		let resolution: CGSize
		let photoDHash: UInt64   // 差分哈希
		let photoHash: UInt64    // pHash (感知哈希)
	}

	/// 一组相似照片的聚类
	struct PhotoCluster: Identifiable, Sendable {
		let id: String
		let items: [PhotoClusterItem]
		let meanHammingDistance: Double
		/// 簇内平均相似度（0–1，越大越相似），由融合距离换算
		let similarity: Double
	}

	/// 聚类中的单张照片，附带与质心的 Hamming 距离
	struct PhotoClusterItem: Sendable {
		let url: URL
		let fileSize: UInt64
		let modificationDate: TimeInterval
		let creationDate: TimeInterval
		let resolution: CGSize
		let hammingDistanceToCentroid: Int
	}

	// MARK: - 配置

	/// 默认 dHash Hamming 距离阈值（差分哈希，宽松度高于 pHash）
	static let defaultDHashThreshold: Int = 15
	/// 默认 pHash Hamming 距离阈值（感知哈希，对全局扰动更敏感）
	static let defaultPHashThreshold: Int = 12

	// MARK: - 公开 API

	/// 按内容相似度聚类照片（dHash + pHash 融合，AND 逻辑）
	/// - Parameters:
	///   - items: 所有已提取双哈希的照片条目
	///   - dHashThreshold: dHash 距离上限，≤ 此值才进入候选
	///   - pHashThreshold: pHash 距离上限，≤ 此值才进入候选
	///   - 两者都 ≤ 各自阈值（AND）才建立边，降低统一水印导致的误判
	/// - Returns: 聚类数组，按成员数量降序排列
	static func cluster(
		_ items: [PhotoItem],
		dHashThreshold: Int = defaultDHashThreshold,
		pHashThreshold: Int = defaultPHashThreshold
	) -> [PhotoCluster] {
		guard items.count >= 2 else { return [] }

		let indexed = Dictionary(uniqueKeysWithValues: items.map { ($0.url.path, $0) })
		let paths = indexed.keys.sorted()

		// 融合距离（用于质心选择与展示）：取两哈希距离的均值
		func fusedDistance(_ a: PhotoItem, _ b: PhotoItem) -> Double {
			let d = VideoHashCache.hammingDistance(a.photoDHash, b.photoDHash)
			let p = VideoHashCache.hammingDistance(a.photoHash, b.photoHash)
			return Double(d + p) / 2.0
		}

		// 构建邻接表：dHash 与 pHash 均 ≤ 各自阈值（AND）才建立边
		var adjacency: [String: Set<String>] = [:]
		for path in paths {
			adjacency[path] = []
		}

		for i in 0..<paths.count {
			let pathA = paths[i]
			guard let itemA = indexed[pathA] else { continue }
			for j in (i + 1)..<paths.count {
				let pathB = paths[j]
				guard let itemB = indexed[pathB] else { continue }
				let dDist = VideoHashCache.hammingDistance(itemA.photoDHash, itemB.photoDHash)
				let pDist = VideoHashCache.hammingDistance(itemA.photoHash, itemB.photoHash)
				if dDist <= dHashThreshold && pDist <= pHashThreshold {
					adjacency[pathA, default: []].insert(pathB)
					adjacency[pathB, default: []].insert(pathA)
				}
			}
		}

		// BFS 找连通分量
		var visited = Set<String>()
		var clusters: [[String]] = []

		for path in paths {
			guard !visited.contains(path) else { continue }
			var component: [String] = []
			var queue = [path]
			visited.insert(path)

			while !queue.isEmpty {
				let current = queue.removeFirst()
				component.append(current)
				for neighbor in adjacency[current, default: []] {
					if !visited.contains(neighbor) {
						visited.insert(neighbor)
						queue.append(neighbor)
					}
				}
			}

			if component.count >= 2 {
				clusters.append(component)
			}
		}

		// 构建 PhotoCluster，计算质心与各成员的融合距离
		return clusters.map { component in
			let centroidItem = computeCentroid(for: component, indexed: indexed, distance: fusedDistance)
			let clusterItems = component.map { path -> PhotoClusterItem in
				let item = indexed[path]!
				let dist = Int(round(fusedDistance(item, centroidItem)))
				return PhotoClusterItem(
					url: item.url,
					fileSize: item.fileSize,
					modificationDate: item.modificationDate,
					creationDate: item.creationDate,
					resolution: item.resolution,
					hammingDistanceToCentroid: dist
				)
			}.sorted { $0.hammingDistanceToCentroid < $1.hammingDistanceToCentroid }

			let meanDist = Double(clusterItems.reduce(0) { $0 + $1.hammingDistanceToCentroid }) / Double(clusterItems.count)
			// 融合距离最大可能值 = 两哈希各 64 位 → 均值上限 64；相似度越高越靠前
			let similarity = max(0, 1 - meanDist / 64.0)

			return PhotoCluster(
				id: component.joined(separator: "|"),
				items: clusterItems,
				meanHammingDistance: meanDist,
				similarity: similarity
			)
		}
		// 按相似度降序、成员数量降序排列（最相似的一组排最前）
		.sorted {
			if abs($0.similarity - $1.similarity) > 1e-9 {
				return $0.similarity > $1.similarity
			}
			return $0.items.count > $1.items.count
		}
	}

	// MARK: - 质心计算

	/// 选取与分量内所有其他成员平均融合距离最小的条目作为质心
	private static func computeCentroid(
		for component: [String],
		indexed: [String: PhotoItem],
		distance: (PhotoItem, PhotoItem) -> Double
	) -> PhotoItem {
		guard let fallback = indexed[component.first!] else {
			fatalError("component 为空，调用方已保证 count >= 2")
		}
		guard component.count >= 2 else { return fallback }

		var bestItem = fallback
		var bestAvgDist: Double = .infinity

		for candidate in component {
			guard let candItem = indexed[candidate] else { continue }
			var totalDist = 0.0
			var count = 0
			for other in component {
				guard other != candidate, let otherItem = indexed[other] else { continue }
				totalDist += distance(candItem, otherItem)
				count += 1
			}
			if count > 0 {
				let avg = totalDist / Double(count)
				if avg < bestAvgDist {
					bestAvgDist = avg
					bestItem = candItem
				}
			}
		}

		return bestItem
	}
}

// MARK: - Identifiable 遵循

extension SimilarPhotoClusterer.PhotoClusterItem: Identifiable {
	var id: String { url.path }
}