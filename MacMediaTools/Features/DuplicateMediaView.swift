import AppKit
import SwiftUI

struct DuplicateMediaView: View {
	@State private var folderURL: URL?
	@State private var statusText: String = "请选择一个文件夹（会递归扫描子文件夹）"
	@State private var isWorking = false
	@State private var processedCount: Int = 0
	@State private var totalCount: Int = 0
	@State private var currentPhase: String = ""
	@State private var groups: [DuplicateGroup] = []
	@State private var errorMessage: String?
	@State private var selectedMediaType: MediaFilter = .all

	enum MediaFilter: String, CaseIterable {
		case all = "全部"
		case photos = "仅照片"
		case videos = "仅视频"
	}

	var filteredGroups: [DuplicateGroup] {
		switch selectedMediaType {
		case .all:
			return groups
		case .photos:
			return groups.filter { $0.mediaType == .photo }
		case .videos:
			return groups.filter { $0.mediaType == .video }
		}
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			Text("重复媒体检测")
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

				Spacer()

				Picker("筛选", selection: $selectedMediaType) {
					ForEach(MediaFilter.allCases, id: \.self) { filter in
						Text(filter.rawValue).tag(filter)
					}
				}
				.pickerStyle(.segmented)
				.frame(width: 200)
				.disabled(isWorking)
			}

			if let errorMessage {
				Text(errorMessage)
					.foregroundStyle(.red)
			}

			Divider()

			HStack {
				Text("重复组数：\(filteredGroups.count)")
					.foregroundStyle(.secondary)

				Spacer()

				let totalDuplicateFiles = filteredGroups.reduce(0) { $0 + $1.files.count }
				Text("重复文件数：\(totalDuplicateFiles)")
					.foregroundStyle(.secondary)
			}

			if !filteredGroups.isEmpty {
				ScrollView {
					LazyVStack(alignment: .leading, spacing: 10) {
						ForEach(filteredGroups) { group in
							DuplicateGroupView(group: group)
						}
					}
				}
			} else if !isWorking && groups.isEmpty && folderURL != nil {
				VStack(spacing: 12) {
					Image(systemName: "checkmark.circle")
						.font(.system(size: 48))
						.foregroundStyle(.green)
					Text("未发现重复文件")
						.font(.headline)
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
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

		await Task.detached(priority: .userInitiated) { [folder] in
			let detector = await DuplicateDetector.shared

			let files = await detector.scanMediaFiles(in: folder)

			var photoCount = 0
			var videoCount = 0
			for file in files {
				if await detector.isPhotoFile(file) {
					photoCount += 1
				} else if await detector.isVideoFile(file) {
					videoCount += 1
				}
			}

			await MainActor.run {
				totalCount = files.count
				processedCount = 0
				statusText = "扫描中：发现 \(photoCount) 张照片和 \(videoCount) 个视频"
			}

			let dupGroups = await detector.findAllDuplicates(in: folder) { current, total, phase in
				Task { @MainActor in
					processedCount = current
					totalCount = total
					currentPhase = phase
					statusText = phase
				}
			}

			await MainActor.run {
				groups = dupGroups
				let photoDupes = dupGroups.filter { $0.mediaType == .photo }.count
				let videoDupes = dupGroups.filter { $0.mediaType == .video }.count
				statusText = "完成：共扫描 \(files.count) 个媒体文件，发现 \(dupGroups.count) 组重复（照片\(photoDupes)组，视频\(videoDupes)组）"
				isWorking = false
			}
		}.value
	}
}

struct DuplicateGroupView: View {
	let group: DuplicateGroup
	@State private var isExpanded = false

	var body: some View {
		DisclosureGroup(isExpanded: $isExpanded) {
			VStack(alignment: .leading, spacing: 6) {
				ForEach(group.files, id: \.self) { url in
					HStack {
						ThumbnailView(url: url, mediaType: group.mediaType)
							.frame(width: 40, height: 40)
							.clipShape(RoundedRectangle(cornerRadius: 4))

						Text(url.path)
							.font(.system(size: 12))
							.lineLimit(2)
							.truncationMode(.middle)

						Spacer()

						Button("显示") {
							NSWorkspace.shared.activateFileViewerSelecting([url])
						}
						.buttonStyle(.borderless)
					}
				}
			}
			.padding(.top, 6)
		} label: {
			HStack {
				Image(systemName: group.mediaType == .photo ? "photo" : "video")
					.foregroundStyle(group.mediaType == .photo ? .blue : .purple)
				Text("重复 \(group.files.count) 个")
				Text("(\(group.matchReason))")
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			.font(.system(.body, design: .monospaced))
		}
		.padding(10)
		.background(.quaternary.opacity(0.6))
		.clipShape(RoundedRectangle(cornerRadius: 8))
	}
}

struct ThumbnailView: View {
	let url: URL
	let mediaType: DuplicateGroup.MediaType
	@State private var thumbnail: NSImage?

	var body: some View {
		Group {
			if let thumbnail {
				Image(nsImage: thumbnail)
					.resizable()
					.aspectRatio(contentMode: .fill)
			} else {
				Rectangle()
					.fill(Color.gray.opacity(0.3))
					.overlay {
						Image(systemName: mediaType == .photo ? "photo" : "video")
							.foregroundStyle(.gray)
					}
			}
		}
		.onAppear {
			loadThumbnail()
		}
	}

	private func loadThumbnail() {
		Task.detached(priority: .utility) {
			let image = NSWorkspace.shared.icon(forFile: url.path)
			image.size = NSSize(width: 40, height: 40)
			await MainActor.run {
				thumbnail = image
			}
		}
	}
}