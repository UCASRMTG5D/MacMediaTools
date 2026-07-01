import Foundation

// MARK: - Similar Video Clustering (Connected Components)

enum SimilarVideoClusterer {

	// MARK: - Public Types

	/// A single video item with its segment hashes.
	struct VideoItem: Sendable {
		let url: URL
		let fileSize: UInt64
		let durationSeconds: Double
		let resolution: CGSize
		let bitrate: Double
		let frameRate: Double
		let creationDate: TimeInterval
		let modificationDate: TimeInterval
		let segmentHashes: [UInt64]
	}

	/// A cluster of similar videos.
	struct Cluster: Identifiable, Sendable {
		let id: String
		let items: [ClusterItem]
		let meanSimilarity: Double
	}

	/// One video within a cluster, with its similarity to the cluster centroid.
	struct ClusterItem: Sendable {
		let url: URL
		let fileSize: UInt64
		let durationSeconds: Double
		let resolution: CGSize
		let bitrate: Double
		let frameRate: Double
		let creationDate: TimeInterval
		let modificationDate: TimeInterval
		let similarityToCentroid: Double
	}

	/// Edge between two videos (used internally).
	private struct Edge: Hashable {
		let a: String // URL.path
		let b: String
	}

	// MARK: - Configuration

	/// Default similarity threshold (0.0–1.0). Two videos match when this fraction of segments agree.
	static let defaultThreshold: Double = 0.5

	/// Hamming distance threshold per segment for a "match".
	private static let segmentHammingThreshold = 10

	// MARK: - Public API

	/// Cluster videos by content similarity.
	/// - Parameters:
	///   - items: All video items with precomputed segment hashes.
	///   - threshold: Minimum segment similarity fraction (0.0–1.0). Two videos are connected when similarity ≥ threshold.
	/// - Returns: Array of cluster groups, sorted by size descending.
	static func cluster(_ items: [VideoItem], threshold: Double = defaultThreshold) -> [Cluster] {
		guard items.count >= 2 else {
			// Single item or empty → no clusters
			return []
		}

		let indexed = Dictionary(uniqueKeysWithValues: items.map { ($0.url.path, $0) })
		let paths = indexed.keys.sorted()

		// Build adjacency edges
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
				let sim = VideoHashCache.segmentSimilarity(itemA.segmentHashes, itemB.segmentHashes)
				if sim >= threshold {
					adjacency[pathA, default: []].insert(pathB)
					adjacency[pathB, default: []].insert(pathA)
				}
			}
		}

		// Find connected components via BFS
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

		// Build Cluster objects with centroid similarity
		return clusters.map { component in
			let centroid = computeCentroid(for: component, indexed: indexed)
			let items = component.map { path -> ClusterItem in
				let item = indexed[path]!
				let sim = VideoHashCache.segmentSimilarity(item.segmentHashes, centroid)
				return ClusterItem(
					url: item.url,
					fileSize: item.fileSize,
					durationSeconds: item.durationSeconds,
					resolution: item.resolution,
					bitrate: item.bitrate,
					frameRate: item.frameRate,
					creationDate: item.creationDate,
					modificationDate: item.modificationDate,
					similarityToCentroid: sim
				)
			}.sorted { $0.similarityToCentroid > $1.similarityToCentroid }

			let meanSim = items.reduce(0.0) { $0 + $1.similarityToCentroid } / Double(items.count)

			return Cluster(
				id: component.joined(separator: "|"),
				items: items,
				meanSimilarity: meanSim
			)
		}.sorted { $0.items.count > $1.items.count }
	}

	/// Compute the centroid — pick the item with highest average similarity to all others.
	private static func computeCentroid(
		for component: [String],
		indexed: [String: VideoItem]
	) -> [UInt64] {
		guard component.count >= 2, let fallback = indexed[component.first!] else {
			return indexed[component.first!]?.segmentHashes ?? []
		}

		var bestPath = component.first!
		var bestAvgSim: Double = -1

		for candidate in component {
			guard let candItem = indexed[candidate] else { continue }
			var totalSim: Double = 0
			var count = 0
			for other in component {
				guard other != candidate, let otherItem = indexed[other] else { continue }
				totalSim += VideoHashCache.segmentSimilarity(candItem.segmentHashes, otherItem.segmentHashes)
				count += 1
			}
			if count > 0 {
				let avg = totalSim / Double(count)
				if avg > bestAvgSim {
					bestAvgSim = avg
					bestPath = candidate
				}
			}
		}

		return indexed[bestPath]?.segmentHashes ?? fallback.segmentHashes
	}
}
