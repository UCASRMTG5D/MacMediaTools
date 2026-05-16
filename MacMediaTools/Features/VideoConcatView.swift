import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct VideoConcatView: View {
	@State private var videos: [URL] = []
	@State private var selection = Set<URL>()
	@State private var draggingURL: URL?

	@State private var outputFolder: URL?
	@State private var outputFileName: String = "merged_1.mp4"

	@State private var isWorking = false
	@State private var lastOutputURL: URL?
	@State private var errorMessage: String?

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			Text("多个视频拼接")
				.font(.title2)

			HStack(spacing: 10) {
				OpenPanelButton(
					title: "批量选择视频…",
					mode: .file(allowedTypes: [.movie], allowsMultipleSelection: true)
				) { urls in
					addVideos(urls)
				}

				Button("清空") { videos.removeAll() }
					.disabled(videos.isEmpty)
			}

			Text("已选择：\(videos.count) 个（在列表里可拖动调整顺序）")
				.foregroundStyle(.secondary)

			List(selection: $selection) {
				ForEach(videos, id: \.self) { url in
					HStack {
						Text(url.lastPathComponent)
						Spacer()
						Text(url.deletingLastPathComponent().lastPathComponent)
							.foregroundStyle(.secondary)
					}
					.lineLimit(1)
					.truncationMode(.middle)
					.tag(url)
					.contextMenu {
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
							draggingURL: $draggingURL
						)
					)
				}
				.onMove(perform: move)
				.onDelete(perform: delete)
			}
			.frame(height: 280)
			.onDeleteCommand(perform: deleteSelection)

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
				.disabled(isWorking || videos.count < 2)

				if let lastOutputURL {
					Button("在 Finder 中显示结果") {
						NSWorkspace.shared.activateFileViewerSelecting([lastOutputURL])
					}
				}
			}

			if let errorMessage {
				Text(errorMessage)
					.foregroundStyle(.red)
			}

			Spacer()
		}
	}

	private func addVideos(_ urls: [URL]) {
		errorMessage = nil
		lastOutputURL = nil

		// 去重、保持顺序
		for url in urls {
			if !videos.contains(url) {
				videos.append(url)
			}
		}

		if outputFolder == nil, let first = videos.first {
			outputFolder = first.deletingLastPathComponent()
		}
	}

	private func move(from source: IndexSet, to destination: Int) {
		videos.move(fromOffsets: source, toOffset: destination)
	}

	private func delete(at offsets: IndexSet) {
		videos.remove(atOffsets: offsets)
		for url in selection where !videos.contains(url) {
			selection.remove(url)
		}
	}

	private func deleteSelection() {
		guard !selection.isEmpty else { return }
		let offsets = IndexSet(videos.indices.filter { selection.contains(videos[$0]) })
		guard !offsets.isEmpty else { return }
		videos.remove(atOffsets: offsets)
		selection.removeAll()
	}

	private func delete(_ url: URL) {
		guard let index = videos.firstIndex(of: url) else { return }
		videos.remove(at: index)
		selection.remove(url)
	}

	private func buildOutputURL() -> URL? {
		guard let first = videos.first else { return nil }
		let folder = outputFolder ?? first.deletingLastPathComponent()
		let name = outputFileName.isEmpty ? "merged_1.mp4" : outputFileName
		return folder.appendingPathComponent(name)
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
				outputURL: outURL
			)
			lastOutputURL = outURL
		} catch {
			errorMessage = error.localizedDescription
		}
	}
}

private struct VideoURLDropDelegate: DropDelegate {
	let item: URL
	@Binding var videos: [URL]
	@Binding var draggingURL: URL?

	func dropEntered(info: DropInfo) {
		guard let draggingURL, draggingURL != item else { return }
		guard let fromIndex = videos.firstIndex(of: draggingURL) else { return }
		guard let toIndex = videos.firstIndex(of: item) else { return }

		withAnimation {
			videos.move(
				fromOffsets: IndexSet(integer: fromIndex),
				toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
			)
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
