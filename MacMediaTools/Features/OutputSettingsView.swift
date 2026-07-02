import AppKit
import SwiftUI

struct OutputSettingsView: View {
	// MARK: - Output bindings
	@Binding var outputFolder: URL?
	@Binding var outputFileName: String
	@Binding var isWorking: Bool
	@Binding var lastOutputURL: URL?
	@Binding var errorMessage: String?
	@Binding var showDeleteConfirmation: Bool

	// MARK: - Read-only state
	let canExport: Bool
	let inputURL: URL?
	let enableResize: Bool
	let effectiveTargetSize: CGSize?
	let stretchPreviewResult: NSImage?
	let sourceSize: CGSize?
	let thumbnailImage: NSImage

	// MARK: - Callbacks
	let onExport: () async -> Void
	let onDeleteSourceFile: () -> Void

	var body: some View {
		stretchPreviewSection

		Divider()

		outputSection
		actionButtons
	}

	// MARK: - Stretch Preview

	@ViewBuilder
	private var stretchPreviewSection: some View {
		if enableResize, effectiveTargetSize != nil, let result = stretchPreviewResult {
			GroupBox {
				VStack(alignment: .leading, spacing: 8) {
					Text("拉伸效果预览")
						.font(.subheadline).bold()

					HStack(spacing: 12) {
						VStack(spacing: 4) {
							Text("裁剪后画面")
								.font(.caption)
								.foregroundStyle(.secondary)
							if sourceSize != nil {
								Image(nsImage: thumbnailImage)
									.resizable()
									.aspectRatio(contentMode: .fit)
									.frame(maxHeight: 160)
									.cornerRadius(4)
							}
						}

						Image(systemName: "arrow.right")
							.foregroundStyle(.secondary)

						VStack(spacing: 4) {
							Text("调整后 (\(Int(effectiveTargetSize?.width ?? 0))×\(Int(effectiveTargetSize?.height ?? 0)))")
								.font(.caption)
								.foregroundStyle(.secondary)
							Image(nsImage: result)
								.resizable()
								.aspectRatio(contentMode: .fit)
								.frame(maxHeight: 160)
								.cornerRadius(4)
						}
					}
				}
			} label: {
				Label("预览", systemImage: "eye")
					.font(.headline)
			}
		}
	}

	// MARK: - Output

	private var outputSection: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("输出设置")
				.font(.headline)

			Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
				GridRow {
					Text("输出目录")
					HStack {
						OpenPanelButton(title: "选择目录…", mode: .folder) { urls in
							outputFolder = urls.first
						}
						Text(outputFolder?.path ?? "(默认：原文件同目录)")
							.lineLimit(1)
							.truncationMode(.middle)
					}
					.gridCellColumns(3)
				}

				GridRow {
					Text("输出文件名")
					TextField("例如 xxx_output.mp4", text: $outputFileName)
						.frame(maxWidth: 520)
						.gridCellColumns(3)
				}
			}
		}
	}

	// MARK: - Actions

	private var actionButtons: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 12) {
				Button(isWorking ? "处理中…" : "开始导出") {
					Task {
						guard await WorkManager.shared.requestStart(.videoCropResize) else { return }
						isWorking = true
						defer {
							isWorking = false
							WorkManager.shared.finishWork(.videoCropResize)
						}
						await onExport()
					}
				}
				.disabled(!canExport)

				if let lastOutputURL {
					Button("在 Finder 中显示结果") {
						NSWorkspace.shared.activateFileViewerSelecting([lastOutputURL])
					}
				}

				if lastOutputURL != nil, let inputURL, FileManager.default.fileExists(atPath: inputURL.path) {
					Button("删除所有源文件", role: .destructive) {
						showDeleteConfirmation = true
					}
				}
			}

			if let errorMessage {
				Text(errorMessage)
					.foregroundStyle(.red)
			}
		}
		.alert("删除所有源文件", isPresented: $showDeleteConfirmation) {
			Button("取消", role: .cancel) { }
			Button("删除", role: .destructive) {
				onDeleteSourceFile()
			}
		} message: {
			Text("是否真的要删除所有源文件？将文件移到废纸篓。")
		}
	}
}
