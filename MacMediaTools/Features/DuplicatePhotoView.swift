import AppKit
import SwiftUI

struct DuplicatePhotoGroup: Identifiable {
	let id: String // hash
	let files: [URL]
}

struct DuplicatePhotoView: View {
	@State private var folderURL: URL?
	@State private var statusText: String = "请选择一个文件夹（会递归扫描子文件夹）"

	@State private var isWorking = false
	@State private var processedCount: Int = 0
	@State private var totalCount: Int = 0
	@State private var groups: [DuplicatePhotoGroup] = []
	@State private var errorMessage: String?

	private let photoExts: Set<String> = [
		"jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp", "gif", "webp"
	]

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			Text("重复照片检测")
				.font(.title2)

			HStack {
				OpenPanelButton(title: "选择文件夹…", mode: .folder) { urls in
					folderURL = urls.first
					groups = []
					errorMessage = nil
				}
				.disabled(isWorking)
				Text(folderURL?.path ?? "未选择")
					.lineLimit(1)
					.truncationMode(.middle)
			}

			Text(statusText)
				.foregroundStyle(.secondary)

			HStack(spacing: 12) {
				Button(isWorking ? "扫描中…" : "开始扫描") {
					Task { await run() }
				}
				.disabled(isWorking || folderURL == nil)

				if isWorking {
					ProgressView()
					Text("\(processedCount)/\(totalCount)")
						.monospacedDigit()
						.foregroundStyle(.secondary)
				}
			}

			if let errorMessage {
				Text(errorMessage)
					.foregroundStyle(.red)
			}

			Divider()

			Text("重复组数：\(groups.count)")
				.foregroundStyle(.secondary)

			ScrollView {
				LazyVStack(alignment: .leading, spacing: 10) {
					ForEach(groups) { group in
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
											deleteFile(url)
										}
										.foregroundColor(.red)
										.buttonStyle(.borderless)
									}
								}
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
				}
			}

			Spacer()
		}
	}

	@MainActor
	private func run() async {
		guard let folderURL else { return }
		isWorking = true
		processedCount = 0
		totalCount = 0
		groups = []
		errorMessage = nil
		statusText = "扫描中：正在读取文件列表…"

		let folder = folderURL
		let exts = photoExts

		Task.detached(priority: .userInitiated) { [folder, exts] in
			let files = FolderScanner.scanFiles(in: folder, allowedExtensions: exts)
			await MainActor.run {
				totalCount = files.count
				processedCount = 0
				statusText = "扫描中：将按 SHA256 判定“完全相同文件”"
			}

			var map: [String: [URL]] = [:]

			for (idx, url) in files.enumerated() {
				if Task.isCancelled { return }

				do {
					let hash = try FileHasher.sha256(url: url)
					map[hash, default: []].append(url)
				} catch {
				}

				if idx % 10 == 0 || idx + 1 == files.count {
					await MainActor.run { processedCount = idx + 1 }
				}
			}

			let dupGroups = map
				.filter { $0.value.count > 1 }
				.map { DuplicatePhotoGroup(id: $0.key, files: $0.value.sorted(by: { $0.path < $1.path })) }
				.sorted(by: { $0.files.count > $1.files.count })

			await MainActor.run {
				groups = dupGroups
				statusText = "完成：共扫描 \(files.count) 张图片，发现 \(groups.count) 组重复"
				isWorking = false
			}
		}
	}

	private func deleteFile(_ url: URL) {
		let alert = NSAlert()
		alert.messageText = "确认删除文件"
		alert.informativeText = "确定要删除文件 \"\(url.lastPathComponent)\" 吗？此操作无法撤销。"
		alert.alertStyle = .warning
		alert.addButton(withTitle: "删除")
		alert.addButton(withTitle: "取消")
		
		if alert.runModal() == .alertFirstButtonReturn {
			do {
				try FileManager.default.removeItem(at: url)
				groups = groups.map { group in
					let remaining = group.files.filter { $0 != url }
					return DuplicatePhotoGroup(id: group.id, files: remaining)
				}.filter { $0.files.count > 1 }
			} catch {
				errorMessage = "删除失败：\(error.localizedDescription)"
			}
		}
	}
}
