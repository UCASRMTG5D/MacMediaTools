import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct VideoConcatView: View {
	@State private var videos: [URL] = []
	@State private var selection = Set<URL>()
	@State private var draggingURL: URL?

	@State private var videoInfos: [URL: VideoDisplayInfo] = [:]
	@State private var targetConcatWidth: String = ""
	@State private var targetConcatHeight: String = ""

	@State private var outputFolder: URL?
	@State private var outputFileName: String = "merged_1.mp4"

	@State private var isWorking = false
	@State private var isLoading = false
	@State private var lastOutputURL: URL?
	@State private var errorMessage: String?
	@State private var showDeleteConfirmation = false

	private var computedMaxSize: CGSize? {
		let widths = videoInfos.values.map(\.displaySize.width)
		let heights = videoInfos.values.map(\.displaySize.height)
		guard let mw = widths.max(), let mh = heights.max(), mw > 0, mh > 0 else { return nil }
		return CGSize(width: mw, height: mh)
	}

	private var resolutionsDiffer: Bool {
		let sizes = videoInfos.values.map(\.displaySize)
		guard let first = sizes.first else { return false }
		return sizes.contains { abs($0.width - first.width) > 0.5 || abs($0.height - first.height) > 0.5 }
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			Text("视频片段整合")
				.font(.title2)

			HStack(spacing: 10) {
				OpenPanelButton(
					title: isLoading ? "加载中…" : "批量选择视频…",
					mode: .file(allowedTypes: [.movie], allowsMultipleSelection: true)
				) { urls in
					Task { await addVideos(urls) }
				}
				.disabled(isLoading || isWorking)

				Button("清空") { videos.removeAll(); videoInfos.removeAll() }
					.disabled(videos.isEmpty || isLoading || isWorking)
			}

			if isLoading {
				HStack(spacing: 8) {
					ProgressView()
						.scaleEffect(0.8)
					Text("正在加载视频文件…")
						.foregroundStyle(.secondary)
				}
			}

			Text("已选择：\(videos.count) 个（在列表里可拖动调整顺序）")
				.foregroundStyle(.secondary)

			List(selection: $selection) {
				ForEach(videos, id: \.self) { url in
					HStack {
						Text(url.lastPathComponent)
						if let info = videoInfos[url] {
							Text("(\(Int(info.displaySize.width))×\(Int(info.displaySize.height)))")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
						Spacer()
						Text(url.deletingLastPathComponent().lastPathComponent)
							.foregroundStyle(.secondary)
					}
					.lineLimit(1)
					.truncationMode(.middle)
					.tag(url)
					.contextMenu {
						Button("在 Finder 中显示") {
							NSWorkspace.shared.activateFileViewerSelecting([url])
						}
						Button("删除") { delete(url) }
					}
					.onDrag {
						draggingURL = url
						return NSItemProvider(object: url as NSURL)
					}
					.onDrop(
						of: [.fileURL],
						delegate: VideoURLDropDelegate(
							item: url,
							videos: $videos,
							draggingURL: $draggingURL,
							videoInfos: $videoInfos
						)
					)
				}
				.onMove(perform: move)
				.onDelete(perform: delete)
			}
			.frame(height: 280)
			.onDeleteCommand(perform: deleteSelection)

			if videos.count >= 2 {
				targetResizeSection
			}

			Divider()

			Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
				GridRow {
					Text("输出目录")
					HStack {
						OpenPanelButton(title: "选择目录…", mode: .folder) { urls in
							outputFolder = urls.first
						}
						Text(outputFolder?.path ?? "(默认：第1个视频同目录)")
							.lineLimit(1)
							.truncationMode(.middle)
					}
					.gridCellColumns(3)
				}

				GridRow {
					Text("输出文件名")
					TextField("例如 merged_1.mp4", text: $outputFileName)
						.frame(maxWidth: 520)
						.gridCellColumns(3)
				}
			}

			HStack(spacing: 12) {
				Button(isWorking ? "拼接中…" : "开始拼接") {
					Task { await run() }
				}
				.disabled(isWorking || isLoading || videos.count < 2)

				if let lastOutputURL {
					Button("在 Finder 中显示结果") {
						NSWorkspace.shared.activateFileViewerSelecting([lastOutputURL])
					}
				}

				if lastOutputURL != nil, !videos.isEmpty {
					Button("删除所有源文件", role: .destructive) {
						showDeleteConfirmation = true
					}
				}
			}
			.alert("删除所有源文件", isPresented: $showDeleteConfirmation) {
				Button("取消", role: .cancel) { }
				Button("删除", role: .destructive) {
					deleteAllSourceFiles()
				}
			} message: {
				Text("是否真的要删除所有源文件？将文件移到废纸篓。")
			}

			if let errorMessage {
				Text(errorMessage)
					.foregroundStyle(.red)
			}

			Spacer()
		}
	}

	@ViewBuilder
	private var targetResizeSection: some View {
		GroupBox {
			VStack(alignment: .leading, spacing: 8) {
				HStack(spacing: 8) {
					Text("输出分辨率")
						.font(.subheadline).bold()

					TextField("宽", text: $targetConcatWidth)
						.frame(width: 80)
						.textFieldStyle(.roundedBorder)

					Text("×")
						.foregroundStyle(.secondary)

					TextField("高", text: $targetConcatHeight)
						.frame(width: 80)
						.textFieldStyle(.roundedBorder)

					Text("px")
						.foregroundStyle(.secondary)

					Button("重置为最大值") {
						resetTargetSizeToMax()
					}
					.buttonStyle(.borderless)
					.font(.caption)
					.disabled(computedMaxSize == nil)
				}

				Text(resolutionsDiffer
					? "视频分辨率不一致。小于此值的填充黑边居中，大于此值的裁剪边缘保留中心。"
					: "所有视频分辨率一致，无需裁剪或填充。如需缩放请修改上方数值。")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		} label: {
			Label("统一输出尺寸", systemImage: "rectangle.expand.vertical")
				.font(.headline)
		}
	}

	private func addVideos(_ urls: [URL]) async {
		guard !isLoading else { return }

		await MainActor.run {
			isLoading = true
			errorMessage = nil
			lastOutputURL = nil
		}

		// Process in background to avoid blocking UI
		var newVideos: [URL] = []
		var newInfos: [URL: VideoDisplayInfo] = [:]

		for url in urls {
			guard FileManager.default.fileExists(atPath: url.path) else { continue }
			let ext = url.pathExtension.lowercased()
			guard MediaFileExtensions.video.contains(ext) else { continue }

			newVideos.append(url)
			// Read display info
			if let info = try? await VideoToolkit.readDisplayInfo(url: url) {
				newInfos[url] = info
			}
		}

		await MainActor.run {
			for url in newVideos {
				if !videos.contains(url) {
					videos.append(url)
					if let info = newInfos[url] {
						videoInfos[url] = info
					}
				}
			}

			if outputFolder == nil, let first = videos.first {
				outputFolder = first.deletingLastPathComponent()
			}

			// Set default target size from max dimensions
			if let maxSize = computedMaxSize, targetConcatWidth.isEmpty {
				targetConcatWidth = String(Int(maxSize.width))
				targetConcatHeight = String(Int(maxSize.height))
			}

			isLoading = false
		}
	}

	private func resetTargetSizeToMax() {
		guard let maxSize = computedMaxSize else { return }
		targetConcatWidth = String(Int(maxSize.width))
		targetConcatHeight = String(Int(maxSize.height))
	}

	private func move(from source: IndexSet, to destination: Int) {
		videos.move(fromOffsets: source, toOffset: destination)
	}

	private func delete(at offsets: IndexSet) {
		let removed = offsets.map { videos[$0] }
		videos.remove(atOffsets: offsets)
		for url in removed {
			videoInfos.removeValue(forKey: url)
			selection.remove(url)
		}
	}

	private func deleteSelection() {
		guard !selection.isEmpty else { return }
		let offsets = IndexSet(videos.indices.filter { selection.contains(videos[$0]) })
		guard !offsets.isEmpty else { return }
		let removed = offsets.map { videos[$0] }
		videos.remove(atOffsets: offsets)
		for url in removed {
			videoInfos.removeValue(forKey: url)
		}
		selection.removeAll()
	}

	private func delete(_ url: URL) {
		guard let index = videos.firstIndex(of: url) else { return }
		videos.remove(at: index)
		videoInfos.removeValue(forKey: url)
		selection.remove(url)
	}

	private func buildOutputURL() -> URL? {
		guard let first = videos.first else { return nil }
		let folder = outputFolder ?? first.deletingLastPathComponent()
		let name = outputFileName.isEmpty ? "merged_1.mp4" : outputFileName
		return folder.appendingPathComponent(name)
	}

	private var effectiveTargetSize: CGSize? {
		guard let w = Double(targetConcatWidth), let h = Double(targetConcatHeight),
			  w > 2, h > 2 else { return nil }
		return CGSize(width: w, height: h)
	}

	@MainActor
	private func run() async {
		guard let outURL = buildOutputURL() else { return }
		isWorking = true
		errorMessage = nil
		lastOutputURL = nil
		defer { isWorking = false }

		do {
			try await VideoToolkit.exportConcatenated(
				inputURLs: videos,
				outputURL: outURL,
				targetSize: effectiveTargetSize
			)
			lastOutputURL = outURL
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	private func deleteAllSourceFiles() {
		let urls = videos
		guard !urls.isEmpty else { return }
		var failedCount = 0
		for url in urls {
			do {
				try NSWorkspace.shared.recycle([url])
			} catch {
				failedCount += 1
			}
		}
		videos.removeAll()
		videoInfos.removeAll()
		selection.removeAll()
		lastOutputURL = nil
		if failedCount == 0 {
			errorMessage = nil
		} else {
			errorMessage = "\(failedCount) 个文件删除失败"
		}
	}
}

private struct VideoURLDropDelegate: DropDelegate {
	let item: URL
	@Binding var videos: [URL]
	@Binding var draggingURL: URL?
	@Binding var videoInfos: [URL: VideoDisplayInfo]

	func dropEntered(info: DropInfo) {
		guard let draggingURL, draggingURL != item else { return }
		guard let fromIndex = videos.firstIndex(of: draggingURL) else { return }
		guard let toIndex = videos.firstIndex(of: item) else { return }

		withAnimation {
			videos.move(
				fromOffsets: IndexSet(integer: fromIndex),
				toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
			)
			// videoInfos dict is keyed by URL, so it doesn't need reordering
		}
	}

	func dropUpdated(info: DropInfo) -> DropProposal? {
		DropProposal(operation: .move)
	}

	func performDrop(info: DropInfo) -> Bool {
		draggingURL = nil
		return true
	}
}
