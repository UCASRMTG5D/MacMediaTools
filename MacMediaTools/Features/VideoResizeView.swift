import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct VideoResizeView: View {
	@State private var inputURL: URL?
	@State private var infoText: String = "请选择一个视频文件"
	@State private var originalSize: CGSize?

	@State private var targetWidth: String = ""
	@State private var targetHeight: String = ""
	@State private var scaleMode: VideoScaleMode = .stretch

	@State private var outputFolder: URL?
	@State private var outputFileName: String = ""

	@State private var isWorking = false
	@State private var lastOutputURL: URL?
	@State private var errorMessage: String?

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			Text("视频尺寸修改")
				.font(.title2)

			HStack(spacing: 12) {
				OpenPanelButton(
					title: "选择视频…",
					mode: .file(allowedTypes: [.movie], allowsMultipleSelection: false)
				) { urls in
					guard let url = urls.first else { return }
					selectInput(url)
				}

				Text(inputURL?.path ?? "未选择")
					.lineLimit(1)
					.truncationMode(.middle)

				if let inputURL {
					Button("在 Finder 中显示") {
						NSWorkspace.shared.activateFileViewerSelecting([inputURL])
					}
					.buttonStyle(.borderless)
				}
			}

			Text(infoText)
				.foregroundStyle(.secondary)

			Divider()

			Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
				GridRow {
					Text("新宽度")
					TextField("例如 1440", text: $targetWidth)
						.frame(width: 160)
					Text("新高度")
					TextField("例如 1080", text: $targetHeight)
						.frame(width: 160)
				}

				GridRow {
					Text("缩放策略")
					Picker("", selection: $scaleMode) {
						ForEach(VideoScaleMode.allCases) { mode in
							Text(mode.rawValue).tag(mode)
						}
					}
					.frame(maxWidth: 460, alignment: .leading)
					.gridCellColumns(3)
				}

				GridRow {
					Text("输出目录")
					HStack {
						OpenPanelButton(title: "选择目录…", mode: .folder) { urls in
							outputFolder = urls.first
						}
						Text(outputFolder?.path ?? "(默认：原视频同目录)")
							.lineLimit(1)
							.truncationMode(.middle)
					}
					.gridCellColumns(3)
				}

				GridRow {
					Text("输出文件名")
					TextField("例如 xxx_1.mp4", text: $outputFileName)
						.frame(maxWidth: 520)
						.gridCellColumns(3)
				}
			}

			HStack(spacing: 12) {
				Button(isWorking ? "处理中…" : "开始处理") {
					Task { await run() }
				}
				.disabled(isWorking || inputURL == nil || parseTargetSize() == nil)

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

	private func selectInput(_ url: URL) {
		inputURL = url
		errorMessage = nil
		lastOutputURL = nil

		Task {
			do {
				let info = try await VideoToolkit.readDisplayInfo(url: url)
				originalSize = info.displaySize
				infoText = "原始宽高：\(Int(info.displaySize.width)) × \(Int(info.displaySize.height))"

				if targetWidth.isEmpty { targetWidth = String(Int(info.displaySize.width)) }
				if targetHeight.isEmpty { targetHeight = String(Int(info.displaySize.height)) }

				if outputFolder == nil {
					outputFolder = url.deletingLastPathComponent()
				}
				if outputFileName.isEmpty {
					outputFileName = defaultOutputName(for: url)
				}
			} catch {
				infoText = "读取视频信息失败：\(error.localizedDescription)"
			}
		}
	}

	private func parseTargetSize() -> CGSize? {
		guard let w = Double(targetWidth), let h = Double(targetHeight), w > 2, h > 2 else { return nil }
		return CGSize(width: w, height: h)
	}

	private func defaultOutputName(for input: URL) -> String {
		let base = input.deletingPathExtension().lastPathComponent
		return "\(base)_1.mp4"
	}

	private func buildOutputURL() -> URL? {
		guard let inputURL else { return nil }
		let folder = outputFolder ?? inputURL.deletingLastPathComponent()
		let name = outputFileName.isEmpty ? defaultOutputName(for: inputURL) : outputFileName
		return folder.appendingPathComponent(name)
	}

	@MainActor
	private func run() async {
		guard let inputURL, let target = parseTargetSize(), let outURL = buildOutputURL() else { return }
		isWorking = true
		errorMessage = nil
		lastOutputURL = nil
		defer { isWorking = false }

		do {
			try await VideoToolkit.exportResized(
				inputURL: inputURL,
				outputURL: outURL,
				targetSize: target,
				scaleMode: scaleMode
			)
			lastOutputURL = outURL
		} catch {
			errorMessage = error.localizedDescription
		}
	}
}

