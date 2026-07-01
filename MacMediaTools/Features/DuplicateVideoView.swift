import AppKit
import SwiftUI

// MARK: - Quick Mode Group

struct DuplicateVideoGroup: Identifiable {
	let id: String
	let keyDescription: String
	let files: [URL]
}

// MARK: - Main View

struct DuplicateVideoView: View {

	/// The model is owned by RootView so a running scan survives view switches.
	@ObservedObject var scanModel: DuplicateVideoScanModel

	// --- UI-only state (resets when view is deinited) ---
	@State private var ignoredQuickSet: Set<String> = []
	@State private var ignoredDeepSet: Set<String> = []
	@State private var expandedComparisonClusterID: String? = nil

	// MARK: - Computed

	private var displayedQuickGroups: [DuplicateVideoGroup] {
		scanModel.quickGroups.filter { !ignoredQuickSet.contains($0.id) }
	}

	private var displayedDeepClusters: [SimilarVideoClusterer.Cluster] {
		scanModel.deepClusters.filter { !ignoredDeepSet.contains($0.id) }
	}

	// MARK: - Body

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 14) {
				modePicker
				folderRow
				statusTextRow
				actionRow
				if scanModel.detectionMode == .deep { deepConfigSection }
				if let errorMessage = scanModel.errorMessage { errorRow(msg: errorMessage) }
				Divider()
				resultsSection
			}
			.padding()
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.scrollIndicators(.visible)
		.background(Color(NSColor.controlBackgroundColor))
	}

	// MARK: - Subviews

	private var modePicker: some View {
		Picker("检测模式", selection: $scanModel.detectionMode) {
			ForEach(VideoDetectionMode.allCases, id: \.self) { mode in
				Text(mode.rawValue).tag(mode)
			}
		}
		.pickerStyle(.segmented)
		.frame(width: 280)
		.disabled(scanModel.isWorking)
		.onChange(of: scanModel.detectionMode) { _ in
			scanModel.clearResults()
			ignoredQuickSet = []
			ignoredDeepSet = []
		}
	}

	private var folderRow: some View {
		HStack {
			OpenPanelButton(title: "选择文件夹…", mode: .folder) { urls in
				scanModel.folderURL = urls.first
				scanModel.clearResults()
				ignoredQuickSet = []
				ignoredDeepSet = []
			}
			.disabled(scanModel.isWorking)
			Text(scanModel.folderURL?.path ?? "未选择")
				.lineLimit(1)
				.truncationMode(.middle)
		}
	}

	private var statusTextRow: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(scanModel.statusText)
				.foregroundStyle(.secondary)
			if scanModel.detectionMode == .deep && scanModel.isWorking && !scanModel.deepPhase.isEmpty {
				Text(scanModel.deepPhase)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
	}

	private var actionRow: some View {
		HStack(spacing: 12) {
			Button(scanModel.isWorking ? "扫描中…" : "开始扫描") {
				scanModel.startScan()
			}
			.disabled(scanModel.isWorking || scanModel.folderURL == nil)

			if scanModel.isWorking {
				ProgressView()
				Text("\(scanModel.processedCount)/\(scanModel.totalCount)")
					.monospacedDigit()
					.foregroundStyle(.secondary)
			}
		}
	}

	@ViewBuilder
	private var deepConfigSection: some View {
		GroupBox {
			VStack(alignment: .leading, spacing: 10) {
				// Cache directory
				HStack {
					Text("缓存目录")
					OpenPanelButton(title: "选择目录…", mode: .folder) { urls in
						scanModel.cacheDirectory = urls.first
					}
					.buttonStyle(.borderless)
					if scanModel.cacheDirectory == nil {
						Text("（默认：视频目录下）")
							.foregroundStyle(.secondary)
							.font(.caption)
					} else {
						Text(scanModel.cacheDirectory?.path ?? "")
							.lineLimit(1)
							.truncationMode(.middle)
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}

				// Subfolder toggle
				Toggle("在缓存目录中新建文件夹存放", isOn: $scanModel.createSubfolder)
					.disabled(scanModel.isWorking)

				Text("哈希缓存可大幅加速后续重复检测，仅存储视频的数字指纹（每部约 700 字节），占用空间极小。")
					.font(.caption)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)

				Divider()

				// Debug mode
				Toggle("调试模式（仅检测部分视频，不修改缓存）", isOn: $scanModel.debugMode)
					.disabled(scanModel.isWorking)

				if scanModel.debugMode {
					HStack {
						Text("采样比例: \(Int(scanModel.sampleFraction * 100))%")
							.font(.caption)
						Slider(value: $scanModel.sampleFraction, in: 0.1...1.0, step: 0.1)
					}
					.padding(.leading, 20)
				}
			}
			.padding(8)
		} label: {
			Label("精细检测设置", systemImage: "gearshape")
				.font(.headline)
		}
	}

	private func errorRow(msg: String) -> some View {
		Text(msg)
			.foregroundStyle(.red)
	}

	@ViewBuilder
	private var resultsSection: some View {
		switch scanModel.detectionMode {
		case .quick:
			quickResultsView
		case .deep:
			deepResultsView
		}
	}

	// MARK: - Quick Results

	@ViewBuilder
	private var quickResultsView: some View {
		VStack(alignment: .leading, spacing: 6) {
			let groups = displayedQuickGroups
			Text("重复组数：\(groups.count)\(ignoredQuickSet.isEmpty ? "" : "（已忽略 \(ignoredQuickSet.count) 组）")")
				.foregroundStyle(.secondary)

			if !groups.isEmpty {
				LazyVStack(alignment: .leading, spacing: 10) {
					ForEach(groups) { group in
						quickGroupRow(group)
					}
				}
			}
		}
	}

	private func quickGroupRow(_ group: DuplicateVideoGroup) -> some View {
		DisclosureGroup {
			VStack(alignment: .leading, spacing: 6) {
				ForEach(group.files, id: \.self) { url in
					HStack(spacing: 12) {
						Text(url.path)
							.font(.system(size: 12))
							.lineLimit(2)
							.truncationMode(.middle)
						Spacer()
						Button("在 Finder 中显示") {
							NSWorkspace.shared.activateFileViewerSelecting([url])
						}
						.buttonStyle(.borderless)
						Button("删除") {
							deleteQuickFile(url)
						}
						.foregroundStyle(.red)
						.buttonStyle(.borderless)
					}
				}
				Divider()
				Button("本次忽略") {
					ignoreQuickGroup(group)
				}
				.foregroundStyle(.orange)
				.buttonStyle(.borderless)
			}
			.padding(.top, 6)
		} label: {
			Text("重复 \(group.files.count) 个（\(group.keyDescription)）")
				.font(.system(.body, design: .monospaced))
		}
		.padding(10)
		.background(.quaternary.opacity(0.6))
		.clipShape(RoundedRectangle(cornerRadius: 8))
	}

	// MARK: - Deep Results

	@ViewBuilder
	private var deepResultsView: some View {
		VStack(alignment: .leading, spacing: 6) {
			let clusters = displayedDeepClusters
			Text("相似组数：\(clusters.count)\(ignoredDeepSet.isEmpty ? "" : "（已忽略 \(ignoredDeepSet.count) 组）")")
				.foregroundStyle(.secondary)
			if scanModel.debugMode {
				Text("（调试模式：仅检测部分视频，缓存不会被修改）")
					.font(.caption)
					.foregroundStyle(.orange)
			}

			if !clusters.isEmpty {
				LazyVStack(alignment: .leading, spacing: 10) {
					ForEach(clusters) { cluster in
						deepClusterRow(cluster)
					}
				}
			}
		}
	}

	private func deepClusterRow(_ cluster: SimilarVideoClusterer.Cluster) -> some View {
		let similarityText = "相似 \(cluster.items.count) 个（平均相似度 \(Int(cluster.meanSimilarity * 100))%）"
		let isComparing = expandedComparisonClusterID == cluster.id
		return DisclosureGroup {
			VStack(alignment: .leading, spacing: 6) {
				Button {
					withAnimation(.easeInOut(duration: 0.2)) {
						if isComparing {
							expandedComparisonClusterID = nil
						} else {
							expandedComparisonClusterID = cluster.id
						}
					}
				} label: {
					HStack(spacing: 6) {
						Image(systemName: isComparing ? "chevron.down" : "play.rectangle.on.rectangle")
						Text(isComparing ? "收起对比预览" : "展开对比预览")
							.font(.subheadline)
					}
				}
				.buttonStyle(.borderless)

				if isComparing {
					VideoComparisonPanel(items: cluster.items)
						.frame(minHeight: 220)
						.transition(.opacity.combined(with: .scale(scale: 0.96)))
				}

				Divider().padding(.vertical, 4)

				ForEach(cluster.items) { item in
					HStack(spacing: 12) {
						VStack(alignment: .leading, spacing: 2) {
							Text(item.url.path)
								.font(.system(size: 12))
								.lineLimit(2)
								.truncationMode(.middle)
							let meta = metaString(for: item)
							Text(meta)
								.font(.caption)
								.foregroundStyle(.secondary)
						}
						Spacer()
						Button("在 Finder 中显示") {
							NSWorkspace.shared.activateFileViewerSelecting([item.url])
						}
						.buttonStyle(.borderless)
						Button("移到废纸篓") {
							deleteDeepItem(item, from: cluster)
						}
						.foregroundStyle(.red)
						.buttonStyle(.borderless)
					}
				}
				Divider()
				Button("本次忽略") {
					ignoreDeepCluster(cluster)
				}
				.foregroundStyle(.orange)
				.buttonStyle(.borderless)
			}
			.padding(.top, 6)
		} label: {
			Text(similarityText)
				.font(.system(.body, design: .monospaced))
		}
		.padding(10)
		.background(.quaternary.opacity(0.6))
		.clipShape(RoundedRectangle(cornerRadius: 8))
	}

	private func fileSizeString(_ bytes: UInt64) -> String {
		let b = Double(bytes)
		if b < 1024 {
			return "\(bytes) B"
		} else if b < 1024 * 1024 {
			return String(format: "%.1f KB", b / 1024)
		} else if b < 1024 * 1024 * 1024 {
			return String(format: "%.1f MB", b / (1024 * 1024))
		} else {
			return String(format: "%.2f GB", b / (1024 * 1024 * 1024))
		}
	}

	private func metaString(for item: SimilarVideoClusterer.ClusterItem) -> String {
		let w = Int(item.resolution.width.rounded())
		let h = Int(item.resolution.height.rounded())
		let resolutionStr = "\(w)×\(h)"

		let bitrateStr: String
		if item.bitrate > 1_000_000 {
			bitrateStr = String(format: "%.1f Mbps", item.bitrate / 1_000_000)
		} else if item.bitrate > 1_000 {
			bitrateStr = String(format: "%.0f Kbps", item.bitrate / 1_000)
		} else {
			bitrateStr = "N/A"
		}

		let fpsStr = item.frameRate > 1 ? String(format: "%.2f fps", item.frameRate) : "N/A"

		let df = DateFormatter()
		df.dateFormat = "yyyy-MM-dd"
		let createStr = item.creationDate > 0 ? df.string(from: Date(timeIntervalSince1970: item.creationDate)) : "N/A"
		let modStr = item.modificationDate > 0 ? df.string(from: Date(timeIntervalSince1970: item.modificationDate)) : "N/A"

		return "相似度 \(Int(item.similarityToCentroid * 100))%  ·  大小 \(fileSizeString(item.fileSize))  ·  \(formatTime(item.durationSeconds))  ·  \(resolutionStr)  ·  \(bitrateStr)  ·  \(fpsStr)  ·  创建 \(createStr)  ·  修改 \(modStr)"
	}

	// MARK: - Ignore (Quick)

	private func ignoreQuickGroup(_ group: DuplicateVideoGroup) {
		let alert = NSAlert()
		alert.messageText = "本次忽略"
		alert.informativeText = """
			确定要忽略这组重复视频吗？

			这组视频将从当前结果中隐藏，但下次检测时仍会被检出。
			"""
		alert.alertStyle = .informational
		alert.addButton(withTitle: "确定")
		alert.addButton(withTitle: "取消")

		if alert.runModal() == .alertFirstButtonReturn {
			ignoredQuickSet.insert(group.id)
		}
	}

	// MARK: - Ignore (Deep)

	private func ignoreDeepCluster(_ cluster: SimilarVideoClusterer.Cluster) {
		let alert = NSAlert()
		alert.messageText = "本次忽略"
		alert.informativeText = """
			确定要忽略这组相似视频吗？

			这组视频将从当前结果中隐藏，但下次检测时仍会被检出。
			"""
		alert.alertStyle = .informational
		alert.addButton(withTitle: "确定")
		alert.addButton(withTitle: "取消")

		if alert.runModal() == .alertFirstButtonReturn {
			ignoredDeepSet.insert(cluster.id)
		}
	}

	// MARK: - Delete (Quick)

	private func deleteQuickFile(_ url: URL) {
		let alert = NSAlert()
		alert.messageText = "确认移到废纸篓"
		alert.informativeText = "确定要将文件 \"\(url.lastPathComponent)\" 移到废纸篓吗？"
		alert.alertStyle = .warning
		alert.addButton(withTitle: "移到废纸篓")
		alert.addButton(withTitle: "取消")

		if alert.runModal() == .alertFirstButtonReturn {
			do {
				try FileManager.default.trashItem(at: url, resultingItemURL: nil)
				scanModel.quickGroups = scanModel.quickGroups.compactMap { group in
					let remaining = group.files.filter { $0 != url }
					guard remaining.count > 1 else { return nil }
					return DuplicateVideoGroup(id: group.id, keyDescription: group.keyDescription, files: remaining)
				}
			} catch {
				scanModel.errorMessage = "移到废纸篓失败：\(error.localizedDescription)"
			}
		}
	}

	// MARK: - Delete (Deep)

	private func deleteDeepItem(_ item: SimilarVideoClusterer.ClusterItem, from cluster: SimilarVideoClusterer.Cluster) {
		let alert = NSAlert()
		alert.messageText = "确认移到废纸篓"
		alert.informativeText = "确定要将文件 \"\(item.url.lastPathComponent)\" 移到废纸篓吗？"
		alert.alertStyle = .warning
		alert.addButton(withTitle: "移到废纸篓")
		alert.addButton(withTitle: "取消")

		if alert.runModal() == .alertFirstButtonReturn {
			do {
				try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)

				// Remove from display
				let clusterId = cluster.id
				scanModel.deepClusters = scanModel.deepClusters.compactMap { c in
					guard c.id == clusterId else { return c }
					let remaining = c.items.filter { $0.url != item.url }
					guard remaining.count >= 2 else { return nil }
					// Recompute mean similarity
					let meanSim = remaining.reduce(0.0) { $0 + $1.similarityToCentroid } / Double(remaining.count)
					return SimilarVideoClusterer.Cluster(id: c.id, items: remaining, meanSimilarity: meanSim)
				}
			} catch {
				scanModel.errorMessage = "移到废纸篓失败：\(error.localizedDescription)"
			}
		}
	}
}

// MARK: - ClusterItem Identifiable conformance

extension SimilarVideoClusterer.ClusterItem: Identifiable {
	var id: String { url.path }
}
