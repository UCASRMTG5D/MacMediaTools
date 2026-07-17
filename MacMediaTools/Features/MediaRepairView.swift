import AppKit
import AVFoundation
import SwiftUI

struct MediaRepairView: View {
	@ObservedObject var mediaRepair: MediaRepairModel
	/// 订阅共享日志，日志更新时自动刷新 UI
	@ObservedObject private var logManager = OperationLogManager.shared

	/// 每页条目数（默认 10）
	@State private var pageSize: Int = 10
	/// 每页条目数编辑器临时文本
	@State private var pageSizeText: String = "10"

	/// 各分类当前页码 [categoryId: pageIndex]
	@State private var categoryPages: [String: Int] = [:]

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
					.disabled(mediaRepair.isScanningFolder || mediaRepair.isDetecting || mediaRepair.isRepairing)
					OpenPanelButton(title: "选择文件夹…", mode: .folder) { urls in
						guard let folder = urls.first else { return }
						mediaRepair.selectFolder(folder)
					}
					.disabled(mediaRepair.isScanningFolder || mediaRepair.isDetecting || mediaRepair.isRepairing)
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
					Button(
						mediaRepair.isScanningFolder ? "准备中…" :
						mediaRepair.isDetecting ? "检测中…" : "开始检测"
					) {
						mediaRepair.startDetection()
					}
					.disabled(mediaRepair.isScanningFolder || mediaRepair.isDetecting || mediaRepair.isRepairing || mediaRepair.selectedFiles.isEmpty)

					if mediaRepair.isScanningFolder || mediaRepair.isDetecting {
						ProgressView()
					}
				}

				Text(mediaRepair.statusText)
					.foregroundStyle(.secondary)

				if let result = mediaRepair.result {
					// 每页条目数控制
					HStack {
						Text("每页条目数:")
							.font(.caption)
							.foregroundStyle(.secondary)
						TextField("", text: $pageSizeText)
							.frame(width: 50)
							.textFieldStyle(.roundedBorder)
							.onChange(of: pageSizeText) { newValue in
								if let value = Int(newValue), value > 0 {
									pageSize = value
									// 重置所有分类页码，避免越界
									categoryPages = categoryPages.mapValues { _ in 0 }
								}
							}
						Spacer()
					}
					.padding(.vertical, 4)

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
						ProgressView(value: mediaRepair.progress.fraction)
							.frame(maxWidth: 200)
						Text("\(Int(mediaRepair.progress.fraction * 100))%")
							.monospacedDigit()
							.foregroundStyle(.secondary)
					}
					if !mediaRepair.progress.message.isEmpty {
						Text("正在修复: \(mediaRepair.progress.message)")
							.foregroundStyle(.secondary)
					}
				}

				let logs = OperationLogManager.shared.logs.prefix(50)
				if !logs.isEmpty {
					VStack(alignment: .leading, spacing: 4) {
						Text("操作日志")
							.font(.headline)
						ScrollView {
							VStack(alignment: .leading, spacing: 2) {
								ForEach(logs) { entry in
									Text("[\(Self.timeString(entry.timestamp))] \(entry.message)")
										.font(.system(.caption, design: .monospaced))
										.foregroundStyle(.secondary)
								}
							}
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

	private static func timeString(_ date: Date) -> String {
		let formatter = DateFormatter()
		formatter.dateStyle = .none
		formatter.timeStyle = .medium
		return formatter.string(from: date)
	}

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
		let pageIndex = categoryPages[category.id] ?? 0
		let totalPages = max(1, (items.count + pageSize - 1) / pageSize)
		let pageStart = pageIndex * pageSize
		let pageEnd = min(pageStart + pageSize, items.count)
		let pageItems = items.isEmpty ? [] : Array(items[pageStart..<pageEnd])

		DisclosureGroup(isExpanded: Binding(
			get: { categoryPages[category.id] != nil },
			set: { expanded in
				if expanded {
					categoryPages[category.id] = 0
				} else {
					categoryPages.removeValue(forKey: category.id)
				}
			}
		)) {
			VStack(alignment: .leading, spacing: 8) {
				if items.isEmpty {
					Text("未发现此类问题")
						.font(.caption)
						.foregroundStyle(.secondary)
						.padding(.leading, 4)
				} else {
					ForEach(pageItems) { item in
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

					// 分页控件
					if totalPages > 1 {
						Divider()
						HStack {
							Button("上一页") {
								if pageIndex > 0 {
									categoryPages[category.id] = pageIndex - 1
								}
							}
							.disabled(pageIndex <= 0)
							.buttonStyle(.borderless)

							Text("第 \(pageIndex + 1) / \(totalPages) 页（共 \(items.count) 条）")
								.font(.caption)
								.foregroundStyle(.secondary)

							Button("下一页") {
								if pageIndex < totalPages - 1 {
									categoryPages[category.id] = pageIndex + 1
								}
							}
							.disabled(pageIndex >= totalPages - 1)
							.buttonStyle(.borderless)

							Spacer()

							// 全选/取消全选（作用于当前页）
							Button(mediaRepair.sectionAllChecked(items) ? "取消全选" : "全选") {
								mediaRepair.toggleSection(items)
							}
							.buttonStyle(.borderless)
						}
					}
				}
			}
			.padding(.top, 8)
		} label: {
			HStack {
				Image(systemName: (categoryPages[category.id] != nil) ? "chevron.down" : "chevron.right")
					.font(.caption)
					.foregroundStyle(.secondary)
					.frame(width: 16)
				Text(title)
					.font(.headline)
				Spacer()
				// 折叠时也显示全选/取消全选
				if !items.isEmpty && categoryPages[category.id] != nil {
					Button(mediaRepair.sectionAllChecked(items) ? "取消全选" : "全选") {
						mediaRepair.toggleSection(items)
					}
					.buttonStyle(.borderless)
				}
			}
		}
	}
}
