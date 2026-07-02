import AVFoundation
import AppKit
import Foundation
import ImageIO

// MARK: - dHash Per-frame Fingerprint

enum VideoHashCache {

	// MARK: - Public Types

	struct CacheData: Codable {
		let version: Int
		var entries: [String: Entry]
	}

	struct Entry: Codable {
		let fileSize: UInt64
		let modificationDate: TimeInterval
		let durationSeconds: Double
		let resolutionWidth: Double
		let resolutionHeight: Double
		let bitrate: Double
		let frameRate: Double
		let creationDate: TimeInterval
		let segmentHashes: [UInt64]
	}

	struct ExtractedHashes: Sendable {
		let url: URL
		let fileSize: UInt64
		let modificationDate: TimeInterval
		let durationSeconds: Double
		let resolution: CGSize
		let bitrate: Double
		let frameRate: Double
		let creationDate: TimeInterval
		let segmentHashes: [UInt64]
	}

	enum Error: Swift.Error, LocalizedError {
		case cacheDecodeFailed(String)
		case cacheEncodeFailed(String)
		case frameExtractionFailed(String)
		case noVideoTrack

		var errorDescription: String? {
			switch self {
			case .cacheDecodeFailed(let msg): return "缓存解码失败: \(msg)"
			case .cacheEncodeFailed(let msg): return "缓存编码失败: \(msg)"
			case .frameExtractionFailed(let msg): return "帧提取失败: \(msg)"
			case .noVideoTrack: return "未找到视频轨道"
			}
		}
	}

	// MARK: - Configuration

	/// Segments per video (uniform positions). Public so UI can display it.
	static let segmentCount = 10

	/// Fraction of the frame to keep centered (0.0–1.0); discarding edges reduces watermark influence.
	private static let centerCropFraction: CGFloat = 0.70

	/// dHash output size: width+1 × height = 9×8 → 64 bits.
	private static let hashWidth = 9
	private static let hashHeight = 8

	/// Cache file prefix (visible JSON files).
	static let cacheFilePrefix = "macmediatools_hash_cache_"
	/// Max entries per shard file.
	static let entriesPerShard = 500

	// MARK: - dHash Computation

	/// Compute a 64-bit difference hash for a CGImage.
	/// 1. Center-crop to `centerCropFraction` to reduce watermark impact.
	/// 2. Resize to (hashWidth+1)×hashHeight = 9×8 grayscale.
	/// 3. Compare horizontal neighbours: pixel[x] > pixel[x+1] → set bit.
	static func computeDHash(from image: CGImage) -> UInt64 {
		let w = image.width
		let h = image.height

		// 1. Center crop
		let cropSide = min(CGFloat(w), CGFloat(h)) * centerCropFraction
		let cropRect = CGRect(
			x: (CGFloat(w) - cropSide) / 2,
			y: (CGFloat(h) - cropSide) / 2,
			width: cropSide,
			height: cropSide
		).integral
		let cropped = image.cropping(to: cropRect) ?? image

		// 2. Resize to 9×8 grayscale via CGContext
		let cw = hashWidth    // 9
		let ch = hashHeight   // 8
		guard let ctx = CGContext(
			data: nil,
			width: cw,
			height: ch,
			bitsPerComponent: 8,
			bytesPerRow: cw,
			space: CGColorSpaceCreateDeviceGray(),
			bitmapInfo: CGImageAlphaInfo.none.rawValue
		) else {
			return 0
		}
		ctx.interpolationQuality = .high
		ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: cw, height: ch))

		guard let pixels = ctx.data else { return 0 }
		let buf = pixels.bindMemory(to: UInt8.self, capacity: cw * ch)

		// 3. Compute horizontal differences → 8×8 = 64 bits
		var hash: UInt64 = 0
		for row in 0..<ch {
			for col in 0..<(cw - 1) {
				let left = buf[row * cw + col]
				let right = buf[row * cw + col + 1]
				if left > right {
					let bitIdx = row * (cw - 1) + col
					hash |= (1 << UInt64(bitIdx))
				}
			}
		}
		return hash
	}

	/// Hamming distance (popcount) between two 64-bit hashes.
	static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
		(a ^ b).nonzeroBitCount
	}

	/// Fractional similarity (0.0–1.0) between two hash arrays.
	static func segmentSimilarity(_ a: [UInt64], _ b: [UInt64]) -> Double {
		let minCount = min(a.count, b.count)
		guard minCount > 0 else { return 0 }
		var matchCount = 0
		for i in 0..<minCount {
			if hammingDistance(a[i], b[i]) < 10 {
				matchCount += 1
			}
		}
		return Double(matchCount) / Double(minCount)
	}

	// MARK: - Cache Persistence (Sharded)

	/// Return the shard file URL for a given index inside a directory.
	private static func shardURL(in directory: URL, index: Int) -> URL {
		directory.appendingPathComponent("\(cacheFilePrefix)\(String(format: "%04d", index)).json")
	}

	/// Enumerate all existing shard URLs inside a directory, sorted by index.
	private static func existingShardURLs(in directory: URL) -> [URL] {
		let fm = FileManager.default
		guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
			return []
		}
		return files
			.filter { $0.lastPathComponent.hasPrefix(cacheFilePrefix) && $0.pathExtension == "json" }
			.sorted { $0.lastPathComponent < $1.lastPathComponent }
	}

	/// Load all shards and merge into a single CacheData.
	/// Corrupted shards are automatically deleted.
	static func loadCache(from directory: URL) -> CacheData {
		let shards = existingShardURLs(in: directory)
		var allEntries: [String: Entry] = [:]
		for shardURL in shards {
			if let data = try? Data(contentsOf: shardURL),
			   let shard = try? JSONDecoder().decode(CacheData.self, from: data) {
				for (k, v) in shard.entries {
					allEntries[k] = v
				}
			} else {
				try? FileManager.default.removeItem(at: shardURL)
			}
		}
		return CacheData(version: 1, entries: allEntries)
	}

	/// Save cache as sharded files (entriesPerShard per file).
	/// Stale shard files not in the current set are cleaned up.
	static func saveCache(_ cache: CacheData, to directory: URL) throws {
		let fm = FileManager.default
		if !fm.fileExists(atPath: directory.path) {
			try fm.createDirectory(at: directory, withIntermediateDirectories: true)
		}

		let oldShards = Set(existingShardURLs(in: directory))
		let entries = Array(cache.entries)
		let chunks = stride(from: 0, to: entries.count, by: entriesPerShard).map {
			Dictionary(uniqueKeysWithValues: entries[$0..<min($0 + entriesPerShard, entries.count)].map { ($0.key, $0.value) })
		}

		var currentShards: Set<URL> = []
		for (i, chunk) in chunks.enumerated() {
			let data = try JSONEncoder().encode(CacheData(version: 1, entries: chunk))
			let fileURL = shardURL(in: directory, index: i)
			try data.write(to: fileURL, options: .atomic)
			currentShards.insert(fileURL)
		}

		// Remove old shards no longer in the current set
		for old in oldShards.subtracting(currentShards) {
			try? fm.removeItem(at: old)
		}
	}

	// MARK: - Staleness Check

	/// Check whether a cached entry is still fresh.
	static func isEntryStale(entry: Entry, for url: URL) -> Bool {
		guard let attr = try? FileManager.default.attributesOfItem(atPath: url.path) else {
			return true // file gone
		}
		let currentSize = (attr[.size] as? NSNumber)?.uint64Value ?? 0
		let currentMod = (attr[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
		return currentSize != entry.fileSize || abs(currentMod - entry.modificationDate) > 1
	}

	/// Extract fresh hashes for a single video.
	/// Returns nil if the file can't be read (invalid/missing).
	static func extractHashes(url: URL) async -> ExtractedHashes? {
		guard let attr = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
		let fileSize = (attr[.size] as? NSNumber)?.uint64Value ?? 0
		let modDate = (attr[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
		let createDate = (attr[.creationDate] as? Date)?.timeIntervalSince1970 ?? 0

		if url.pathExtension.lowercased() == "gif" {
			return extractGIFHashes(url: url, fileSize: fileSize, modDate: modDate, createDate: createDate)
		}

		let asset = AVURLAsset(url: url)
		guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else { return nil }
		let duration = try? await asset.load(.duration)
		let durationSeconds = duration?.seconds ?? 0

		guard durationSeconds > 0.5 else { return nil }

		// Resolution
		let naturalSize = try? await videoTrack.load(.naturalSize)
		let preferredTransform = try? await videoTrack.load(.preferredTransform)
		var displaySize = CGSize(width: 0, height: 0)
		if let naturalSize, let preferredTransform {
			let display = naturalSize.applying(preferredTransform)
			displaySize = CGSize(width: abs(display.width), height: abs(display.height))
		}

		let estimatedBitrate = try? await videoTrack.load(.estimatedDataRate)
		let nominalFrameRate = try? await videoTrack.load(.nominalFrameRate)

		let generator = AVAssetImageGenerator(asset: asset)
		generator.appliesPreferredTrackTransform = true
		generator.requestedTimeToleranceBefore = .zero
		generator.requestedTimeToleranceAfter = .zero

		var hashes: [UInt64] = []
		hashes.reserveCapacity(segmentCount)

		for i in 0..<segmentCount {
			let fraction = Double(i + 1) / Double(segmentCount + 1)
			let timeSeconds = durationSeconds * fraction
			let cmTime = CMTime(seconds: timeSeconds, preferredTimescale: 600)
			if let cgImage = try? generator.copyCGImage(at: cmTime, actualTime: nil) {
				hashes.append(computeDHash(from: cgImage))
			}
		}

		guard hashes.count == segmentCount else { return nil }

		return ExtractedHashes(
			url: url,
			fileSize: fileSize,
			modificationDate: modDate,
			durationSeconds: durationSeconds,
			resolution: displaySize,
			bitrate: Double(estimatedBitrate ?? 0),
			frameRate: Double(nominalFrameRate ?? 0),
			creationDate: createDate,
			segmentHashes: hashes
		)
	}

	// MARK: - GIF Frame Extraction

	private static func extractGIFHashes(url: URL, fileSize: UInt64, modDate: TimeInterval, createDate: TimeInterval) -> ExtractedHashes? {
		guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
		let frameCount = CGImageSourceGetCount(source)
		guard frameCount > 0 else { return nil }

		var cumulativeTimes: [Double] = []
		cumulativeTimes.reserveCapacity(frameCount)
		var cumulativeTime: Double = 0

		for i in 0..<frameCount {
			let rawDelay: Double
			if let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
			   let gifDict = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
				rawDelay = gifDict[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double
					?? gifDict[kCGImagePropertyGIFDelayTime as String] as? Double
					?? 0.1
			} else {
				rawDelay = 0.1
			}
			let delay = max(rawDelay, 0.02)
			cumulativeTime += delay
			cumulativeTimes.append(cumulativeTime)
		}

		let totalDuration = cumulativeTimes.last ?? 0
		guard totalDuration > 0.5 else { return nil }

		let w: Double
		let h: Double
		if let firstProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
			w = firstProps[kCGImagePropertyPixelWidth as String] as? Double ?? 0
			h = firstProps[kCGImagePropertyPixelHeight as String] as? Double ?? 0
		} else {
			w = 0; h = 0
		}

		var hashes: [UInt64] = []
		hashes.reserveCapacity(segmentCount)

		for i in 0..<segmentCount {
			let targetTime = totalDuration * Double(i + 1) / Double(segmentCount + 1)

			var lo = 0
			var hi = cumulativeTimes.count - 1
			while lo < hi {
				let mid = (lo + hi) / 2
				if cumulativeTimes[mid] < targetTime {
					lo = mid + 1
				} else {
					hi = mid
				}
			}
			let frameIdx = lo

			if let cgImage = CGImageSourceCreateImageAtIndex(source, frameIdx, nil) {
				hashes.append(computeDHash(from: cgImage))
			}
		}

		guard hashes.count == segmentCount else { return nil }

		return ExtractedHashes(
			url: url,
			fileSize: fileSize,
			modificationDate: modDate,
			durationSeconds: totalDuration,
			resolution: CGSize(width: w, height: h),
			bitrate: 0,
			frameRate: 0,
			creationDate: createDate,
			segmentHashes: hashes
		)
	}

	/// Batch extract: process videos in parallel, update cache, return fresh results.
	/// - `videos`: all video URLs
	/// - `cacheDir`: directory where sharded cache files (*.json) live
	/// - `progress`: callback (processed, total, phaseDescription)
	/// - `sampleFraction`: if < 1.0, randomly sample only that fraction (debug mode)
	/// - `skipCacheSave`: if true, don't persist the cache (debug mode)
	/// - Returns: (cacheData, extractedResults) where extractedResults = fresh hashes for all videos
	static func buildOrUpdateCache(
		videos: [URL],
		cacheDir: URL,
		sampleFraction: Double = 1.0,
		skipCacheSave: Bool = false,
		progress: ((Int, Int, String) -> Void)? = nil
	) async throws -> (CacheData, [ExtractedHashes]) {
		// Load existing cache
		var cache = loadCache(from: cacheDir)

		// Determine which files to process
		let workingSet: [URL]
		if sampleFraction >= 1.0 {
			workingSet = videos
		} else {
			workingSet = Array(videos.shuffled().prefix(max(1, Int(Double(videos.count) * sampleFraction))))
		}

		let total = workingSet.count
		let validURLs = Set(videos.map { $0.path })

		// Remove stale entries for deleted files
		for key in cache.entries.keys {
			if !validURLs.contains(key) {
				cache.entries.removeValue(forKey: key)
			}
		}

		// Process each video: reuse cache or extract fresh
		var results: [ExtractedHashes] = []
		results.reserveCapacity(workingSet.count)

		// Process in parallel batches to control memory
		let batchSize = 8
		var processedCount = 0

		for batchStart in stride(from: 0, to: workingSet.count, by: batchSize) {
			let batchEnd = min(batchStart + batchSize, workingSet.count)
			let batch = Array(workingSet[batchStart..<batchEnd])

			let batchResults = await withTaskGroup(of: ExtractedHashes?.self) { group in
				for url in batch {
					group.addTask {
						// Check cache first
						if let entry = cache.entries[url.path], !isEntryStale(entry: entry, for: url) {
							return ExtractedHashes(
								url: url,
								fileSize: entry.fileSize,
								modificationDate: entry.modificationDate,
								durationSeconds: entry.durationSeconds,
								resolution: CGSize(width: entry.resolutionWidth, height: entry.resolutionHeight),
								bitrate: entry.bitrate,
								frameRate: entry.frameRate,
								creationDate: entry.creationDate,
								segmentHashes: entry.segmentHashes
							)
						}
						// Extract fresh
						return await extractHashes(url: url)
					}
				}

				var collected: [ExtractedHashes] = []
				for await result in group {
					if let r = result {
						collected.append(r)
					}
				}
				return collected
			}

			for r in batchResults {
				results.append(r)
				cache.entries[r.url.path] = Entry(
					fileSize: r.fileSize,
					modificationDate: r.modificationDate,
					durationSeconds: r.durationSeconds,
					resolutionWidth: r.resolution.width,
					resolutionHeight: r.resolution.height,
					bitrate: r.bitrate,
					frameRate: r.frameRate,
					creationDate: r.creationDate,
					segmentHashes: r.segmentHashes
				)
			}

			processedCount += batch.count
			progress?(processedCount, total, "哈希提取: \(processedCount)/\(total)")

			// Persist progressively after each batch (safe — sharded files)
			if !skipCacheSave {
				try saveCache(cache, to: cacheDir)
			}
		}

		progress?(total, total, "哈希缓存完成")
		return (cache, results)
	}
}
