import AppKit
import SwiftUI

// MARK: - Models

struct DuplicatePhotoGroup: Identifiable {
	let id: String // hash
	let files: [URL]
}

struct DuplicatePhotoView: View {
	@ObservedObject var scanModel: DuplicatePhotoScanModel

	@State private var ignoredQuickSet: Set<String> = []
	@State private var ignoredDeepSet: Set<String> = []

	// MARK: - Computed

	private var displayedQuickGroups: [DuplicatePhotoGroup] {
		scanModel.quickGroups.filter { !ignoredQuickSet.contains($0.id) }
	}

	private var displayedDeepClusters: [SimilarPhotoClusterer.PhotoCluster] {
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
			ForEach(PhotoDetectionMode.allCases, id: \.self) { mode in
				Text(mode.rawValue).tag(mode)
			}
		}
		.pickerStyle(.segmented)
		.frame(width: 280)
		.disabled(scanModel.isWorking)
		.onChange(of: scanModel.detectionMode) { _ in
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
				if scanModel.detectionMode == .quick {
					Text("\(scanModel.processedCount)/\(scanModel.totalCount)")
						.monospacedDigit()
						.foregroundStyle(.secondary)
				}
			}
		}
	}

	@ViewBuilder
	private var deepConfigSection: some View {
		GroupBox {
			VStack(alignment: .leading, spacing: 10) {
				// 缓存目录
				HStack {
					Text("缓存目录")
					OpenPanelButton(title: "选择目录…", mode: .folder) { urls in
						scanModel.cacheDirectory = urls.first
					}
					.buttonStyle(.borderless)
					if scanModel.cacheDirectory == nil {
						Text("（默认：照片目录下）")
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

				// 子文件夹
				Toggle("在目录中新建文件夹存放", isOn: $scanModel.createSubfolder)
					.disabled(scanModel.isWorking)

				Text("哈希缓存可大幅加速后续重复检测，仅存储照片的数字指纹（每张约 8 字节），占用空间极小。")
					.font(.caption)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)

				Divider()

				// 调试模式
				Toggle("调试模式（仅检测部分照片，不修改缓存）", isOn: $scanModel.debugMode)
					.disabled(scanModel.isWorking)

				if scanModel.debugMode {
					HStack {
						Text("采样比例: \(Int(scanModel.sampleFraction * 100))%")
							.font(.caption)
						Slider(value: $scanModel.sampleFraction, in: 0.1...1.0, step: 0.1)
					}
					.padding(.leading, 20)
				}

				Divider()

			// 相似度严格度（多哈希融合）
			HStack {
				Text("相似度严格度: \(Int(scanModel.strictness * 100))%")
					.font(.subheadline)
				Slider(value: $scanModel.strictness, in: 0...1, step: 0.05)
			}

			Text("滑块向右越严格、误报越少（但可能漏掉部分真实重复），向左越宽松、召回越多（但可能误报）。采用 dHash + pHash 双哈希融合判定（两者都相似才视为重复），可有效抵抗平台统一暗水印导致的误判。阈值由内部按比例分配，无需手动设置。")
				.font(.caption)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)

				Divider()

				// 清除照片缓存
				Button(role: .destructive) {
					scanModel.clearPhotoCache()
				} label: {
					Label("清除照片缓存", systemImage: "trash")
				}
				.buttonStyle(.borderless)
				.disabled(scanModel.isWorking)
				.help("删除当前缓存目录下的所有哈希缓存分片文件（不影响视频缓存）")
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

	private func quickGroupRow(_ group: DuplicatePhotoGroup) -> some View {
		DisclosureGroup {
			VStack(alignment: .leading, spacing: 8) {
				// Thumbnail preview row
				ScrollView(.horizontal, showsIndicators: false) {
					LazyHStack(spacing: 8) {
						ForEach(group.files, id: \.self) { url in
							AsyncThumbnailView(url: url, size: 100)
						}
					}
					.padding(.vertical, 4)
				}

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
			Text("重复 \(group.files.count) 张（SHA256: \(group.id.prefix(10))…）")
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
				Text("（调试模式：仅检测部分照片，缓存不会被修改）")
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

	private func deepClusterRow(_ cluster: SimilarPhotoClusterer.PhotoCluster) -> some View {
		let meanDistStr = String(format: "%.1f", cluster.meanHammingDistance)
		return DisclosureGroup {
			VStack(alignment: .leading, spacing: 8) {
				// Thumbnail preview row
				ScrollView(.horizontal, showsIndicators: false) {
					LazyHStack(spacing: 8) {
						ForEach(cluster.items) { item in
							AsyncThumbnailView(url: item.url, size: 100)
						}
					}
					.padding(.vertical, 4)
				}

				ForEach(cluster.items) { item in
					HStack(spacing: 12) {
						VStack(alignment: .leading, spacing: 2) {
							Text(item.url.path)
								.font(.system(size: 12))
								.lineLimit(2)
								.truncationMode(.middle)
							Text(metaString(for: item))
								.font(.caption)
								.foregroundStyle(.secondary)
						}
						Spacer()
						Button("打开") {
							openInDefaultApp(item.url)
						}
						.buttonStyle(.borderless)
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
			Text("相似 \(cluster.items.count) 张（平均 Hamming 距离 \(meanDistStr)）")
				.font(.system(.body, design: .monospaced))
		}
		.padding(10)
		.background(.quaternary.opacity(0.6))
		.clipShape(RoundedRectangle(cornerRadius: 8))
	}

	// MARK: - Helpers

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

	private func metaString(for item: SimilarPhotoClusterer.PhotoClusterItem) -> String {
		let w = Int(item.resolution.width.rounded())
		let h = Int(item.resolution.height.rounded())
		let resolutionStr = w > 0 && h > 0 ? "\(w)×\(h)" : "N/A"

		let df = DateFormatter()
		df.dateFormat = "yyyy-MM-dd"
		let createStr = item.creationDate > 0 ? df.string(from: Date(timeIntervalSince1970: item.creationDate)) : "N/A"
		let modStr = item.modificationDate > 0 ? df.string(from: Date(timeIntervalSince1970: item.modificationDate)) : "N/A"

		return "Hamming 距离 \(item.hammingDistanceToCentroid)  ·  大小 \(fileSizeString(item.fileSize))  ·  分辨率 \(resolutionStr)  ·  创建 \(createStr)  ·  修改 \(modStr)"
	}

	// MARK: - Ignore (Quick)

	private func ignoreQuickGroup(_ group: DuplicatePhotoGroup) {
		let alert = NSAlert()
		alert.messageText = "本次忽略"
		alert.informativeText = "确定要忽略这组重复照片吗？\n\n这组照片将从当前结果中隐藏，但下次检测时仍会被检出。"
		alert.alertStyle = .informational
		alert.addButton(withTitle: "确定")
		alert.addButton(withTitle: "取消")

		if alert.runModal() == .alertFirstButtonReturn {
			ignoredQuickSet.insert(group.id)
		}
	}

	// MARK: - Ignore (Deep)

	private func ignoreDeepCluster(_ cluster: SimilarPhotoClusterer.PhotoCluster) {
		let alert = NSAlert()
		alert.messageText = "本次忽略"
		alert.informativeText = "确定要忽略这组相似照片吗？\n\n这组照片将从当前结果中隐藏，但下次检测时仍会被检出。"
		alert.alertStyle = .informational
		alert.addButton(withTitle: "确定")
		alert.addButton(withTitle: "取消")

		if alert.runModal() == .alertFirstButtonReturn {
			ignoredDeepSet.insert(cluster.id)
		}
	}

	// MARK: - Delete (Quick)

	private func deleteQuickFile(_ url: URL) {
		guard confirmAndTrash(url: url) else { return }
		scanModel.deleteQuickPhoto(url)
	}

	// MARK: - Delete (Deep)

	private func deleteDeepItem(_ item: SimilarPhotoClusterer.PhotoClusterItem, from cluster: SimilarPhotoClusterer.PhotoCluster) {
		guard confirmAndTrash(url: item.url) else { return }
		scanModel.deleteDeepPhoto(item, from: cluster)
	}

	/// 用系统默认软件打开图片
	private func openInDefaultApp(_ url: URL) {
		NSWorkspace.shared.open(url)
	}
}

// MARK: - Async Thumbnail View

/// 异步加载并显示图片缩略图
private struct AsyncThumbnailView: View {
	let url: URL
	let size: CGFloat

	@State private var image: NSImage?
	@State private var isLoading = true

	var body: some View {
		Group {
			if let image {
				Image(nsImage: image)
					.resizable()
					.aspectRatio(contentMode: .fill)
					.frame(width: size, height: size)
					.clipped()
					.cornerRadius(6)
					.overlay(
						RoundedRectangle(cornerRadius: 6)
							.stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
					)
			} else if isLoading {
				RoundedRectangle(cornerRadius: 6)
					.fill(Color.secondary.opacity(0.1))
					.frame(width: size, height: size)
					.overlay(ProgressView().scaleEffect(0.6))
			} else {
				RoundedRectangle(cornerRadius: 6)
					.fill(Color.secondary.opacity(0.1))
					.frame(width: size, height: size)
					.overlay(
						Image(systemName: "photo")
							.font(.system(size: size * 0.4))
							.foregroundStyle(.secondary)
					)
			}
		}
		.task {
			await loadThumbnail()
		}
	}

	private func loadThumbnail() async {
		// Load off main thread
		let thumbnail = await Task.detached(priority: .userInitiated) { () -> NSImage? in
			let emptyOptions = NSDictionary()
			guard let source = CGImageSourceCreateWithURL(self.url as CFURL, emptyOptions) else { return nil }
			let options: [CFString: Any] = [
				kCGImageSourceThumbnailMaxPixelSize: max(self.size * 2, 200),
				kCGImageSourceCreateThumbnailWithTransform: true,
				kCGImageSourceCreateThumbnailFromImageAlways: true
			]
			guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
			return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
		}.value

		await MainActor.run {
			self.image = thumbnail
			self.isLoading = false
		}
	}
}