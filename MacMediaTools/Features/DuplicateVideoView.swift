import AppKit
import SwiftUI

struct DuplicateVideoGroup: Identifiable {
	let id: String
	let keyDescription: String
	let files: [URL]
}

struct DuplicateVideoView: View {
	@State private var folderURL: URL?
	@State private var statusText: String = "请选择一个文件夹（会递归扫描子文件夹）"

	@State private var isWorking = false
	@State private var processedCount: Int = 0
	@State private var totalCount: Int = 0
	@State private var groups: [DuplicateVideoGroup] = []
	@State private var errorMessage: String?

	private let videoExts: Set<String> = [
		"mp4", "mov", "m4v", "avi", "mkv"
	]

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			Text("重复视频检测")
				.font(.title2)

			Text("只检测视频文件基本信息（时长 / 文件大小 / 分辨率），暂不支持内容检测～")
				.foregroundStyle(.secondary)

			HStack {
				OpenPanelButton(title: "选择文件夹…", mode: .folder) { urls in
					folderURL = urls.first
					groups = []
					errorMessage = nil
				}
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
									HStack {
										Text(url.path)
											.font(.system(size: 12))
											.lineLimit(2)
											.truncationMode(.middle)
										Spacer()
										Button("在 Finder 中显示") {
											NSWorkspace.shared.activateFileViewerSelecting([url])
										}
										.buttonStyle(.borderless)
									}
								}
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
		statusText = "扫描中：仅按 时长/大小/分辨率 分组"
		defer { isWorking = false }

		let files = FolderScanner.scanFiles(in: folderURL, allowedExtensions: videoExts)
		totalCount = files.count

		var map: [String: (desc: String, urls: [URL])] = [:]

		for (idx, url) in files.enumerated() {
			processedCount = idx + 1

			do {
				let attr = try FileManager.default.attributesOfItem(atPath: url.path)
				let fileSize = (attr[.size] as? NSNumber)?.int64Value ?? 0

				let info = try await VideoToolkit.readDisplayInfo(url: url)
				let durationMs = Int((info.durationSeconds * 1000.0).rounded())
				let w = Int(info.displaySize.width.rounded())
				let h = Int(info.displaySize.height.rounded())

				let key = "\(durationMs)|\(fileSize)|\(w)x\(h)"
				let desc = "时长=\(durationMs)ms 大小=\(fileSize)B 分辨率=\(w)x\(h)"
				map[key, default: (desc: desc, urls: [])].urls.append(url)
			} catch {
				// 忽略单个文件错误
			}
		}

		let dupGroups = map
			.filter { $0.value.urls.count > 1 }
			.map { DuplicateVideoGroup(id: $0.key, keyDescription: $0.value.desc, files: $0.value.urls.sorted(by: { $0.path < $1.path })) }
			.sorted(by: { $0.files.count > $1.files.count })

		groups = dupGroups
		statusText = "完成：共扫描 \(files.count) 个视频，发现 \(groups.count) 组“基本信息重复”"
	}
}

