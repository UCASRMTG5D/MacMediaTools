import AppKit
import AVFoundation
import SwiftUI

struct MediaRepairView: View {
	@ObservedObject var mediaRepair: MediaRepairModel

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 14) {
				Text("检测只读取文件、不修改任何内容。勾选需要修复的项目后点击「开始修复」才会写盘。视频修复均为无损操作（改扩展名 / 无损封装，不转码）。")
					.font(.caption)
					.foregroundStyle(.secondary)

				HStack {
					OpenPanelButton(title: "选择文件…", mode: .mediaFiles) { urls in
						mediaRepair.selectFiles(urls)
					}
					.disabled(mediaRepair.isDetecting || mediaRepair.isRepairing)
					OpenPanelButton(title: "选择文件夹…", mode: .folder) { urls in
						guard let folder = urls.first else { return }
						mediaRepair.selectFolder(folder)
					}
					.disabled(mediaRepair.isDetecting || mediaRepair.isRepairing)
					Text(mediaRepair.selectedFiles.isEmpty ? "未选择" : "已选择 \(mediaRepair.selectedFiles.count) 个文件")
						.lineLimit(1)
						.truncationMode(.middle)
						.foregroundStyle(.secondary)
				}

				HStack(spacing: 8) {
					Text("检测范围")
						.foregroundStyle(.secondary)
					Picker("", selection: $mediaRepair.scope) {
						ForEach(MediaRepairScope.allCases) { s in
							Text(s.rawValue).tag(s)
						}
					}
					.pickerStyle(.segmented)
					.disabled(mediaRepair.isDetecting || mediaRepair.isRepairing)
					Spacer()
				}

				HStack(spacing: 12) {
					Button(mediaRepair.isDetecting ? "检测中…" : "开始检测") {
						mediaRepair.startDetection()
					}
					.disabled(mediaRepair.isDetecting || mediaRepair.isRepairing || mediaRepair.selectedFiles.isEmpty)

					if mediaRepair.isDetecting {
						ProgressView()
					}
				}

				Text(mediaRepair.statusText)
					.foregroundStyle(.secondary)

				if let result = mediaRepair.result {
					resultSections(result)
				}

				if !mediaRepair.checkedIDs.isEmpty && !mediaRepair.isRepairing {
					Button("开始修复（已选 \(mediaRepair.checkedIDs.count) 项）") {
						mediaRepair.startRepair()
					}
					.disabled(mediaRepair.isRepairing || mediaRepair.isDetecting)
				}

				if mediaRepair.isRepairing {
					HStack(spacing: 12) {
						ProgressView(value: mediaRepair.repairProgress)
							.frame(maxWidth: 200)
						Text("\(Int(mediaRepair.repairProgress * 100))%")
							.monospacedDigit()
							.foregroundStyle(.secondary)
					}
					if !mediaRepair.currentFileName.isEmpty {
						Text("正在修复: \(mediaRepair.currentFileName)")
							.foregroundStyle(.secondary)
					}
				}

				if !mediaRepair.logText.isEmpty {
					VStack(alignment: .leading, spacing: 4) {
						Text("操作日志")
							.font(.headline)
						ScrollView {
							Text(mediaRepair.logText)
								.font(.system(.caption, design: .monospaced))
								.foregroundStyle(.secondary)
						}
						.frame(maxHeight: 150)
						.background(Color(nsColor: .controlBackgroundColor))
						.cornerRadius(6)
					}
				}
			}
			.padding()
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.scrollIndicators(.visible)
		.background(Color(NSColor.controlBackgroundColor))
	}

	// MARK: - 分组结果展示（按图片 / 视频 两大类列出）

	@ViewBuilder
	private func resultSections(_ result: MediaRepairResult) -> some View {
		let total = result.imageItems.count + result.videoItems.count
		Text("检测完成：共扫描 \(result.scannedCount) 个文件，发现 \(total) 处可修复问题（已跳过 \(result.skippedCount) 个）。")
			.foregroundStyle(.secondary)

		categorySection(
			category: .image,
			items: result.imageItems
		)

		categorySection(
			category: .video,
			items: result.videoItems
		)
	}

	@ViewBuilder
	private func categorySection(category: MediaRepairCategory, items: [MediaRepairItem]) -> some View {
		let title = "\(category.rawValue)（\(items.count)）"
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text(title)
					.font(.headline)
				Spacer()
				if !items.isEmpty {
					Button(mediaRepair.sectionAllChecked(items) ? "取消全选" : "全选") {
						mediaRepair.toggleSection(items)
					}
					.buttonStyle(.borderless)
				}
			}

			if items.isEmpty {
				Text("未发现此类问题")
					.font(.caption)
					.foregroundStyle(.secondary)
					.padding(.leading, 4)
			} else {
				ForEach(items) { item in
					HStack(alignment: .top, spacing: 10) {
						Toggle("", isOn: Binding(
							get: { mediaRepair.checkedIDs.contains(item.id) },
							set: { checked in
								if checked { mediaRepair.checkedIDs.insert(item.id) }
								else { mediaRepair.checkedIDs.remove(item.id) }
							}
						))
						.labelsHidden()
						VStack(alignment: .leading, spacing: 3) {
							Text(item.url.lastPathComponent)
								.font(.subheadline)
							Text(item.currentLabel)
								.font(.caption)
								.foregroundStyle(.secondary)
							Text(item.suggestedAction)
								.font(.caption)
								.foregroundStyle(.orange)
						}
						Spacer()
						Button("在 Finder 中显示") {
							NSWorkspace.shared.activateFileViewerSelecting([item.url])
						}
						.buttonStyle(.borderless)
					}
					.padding(8)
					.background(Color.orange.opacity(0.08))
					.cornerRadius(6)
				}
			}
		}
	}
}
