import AppKit
import AVFoundation
import CoreGraphics
import SwiftUI

// MARK: - View

/// 搜索状态与执行逻辑由 RootView 持有的 FileSearchModel（@StateObject）提供，
/// 切换功能再回来时搜索继续运行、结果不丢失。
struct FileSearchView: View {
	@ObservedObject var model: FileSearchModel
	@State private var thumbSize: CGFloat = 120

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 14) {
				// Control row
				controlRow

				// Thumbnail size slider
				thumbSizeRow

				// Error
				if let msg = model.errorMessage {
					Text(msg)
						.foregroundStyle(.red)
						.font(.subheadline)
				}

				Divider()

				// Results
				if !model.isSearching {
					if model.searchResult != nil {
						resultsSection
					} else if model.folderURL == nil {
						emptyHint
					}
				} else {
					searchingHint
				}
			}
			.padding()
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.scrollIndicators(.visible)
		.background(Color(NSColor.controlBackgroundColor))
	}

	// MARK: - Subviews

	private var controlRow: some View {
		HStack(spacing: 12) {
			OpenPanelButton(title: "选择文件夹…", mode: .folder) { urls in
				model.selectFolder(urls.first)
			}
			if let url = model.folderURL {
				Text(url.path)
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			TextField("输入关键词…", text: $model.keyword)
				.textFieldStyle(.roundedBorder)
				.frame(width: 200)
			Button(action: model.startSearch) {
				if model.isSearching {
					ProgressView()
						.controlSize(.small)
				} else {
					Text("搜索")
				}
			}
			.buttonStyle(.borderedProminent)
			.disabled(model.folderURL == nil || model.isSearching)
		}
	}

	private var thumbSizeRow: some View {
		HStack(spacing: 8) {
			Text("缩略图大小")
				.font(.subheadline)
				.foregroundStyle(.secondary)
			Slider(value: $thumbSize, in: 60...200, step: 10)
				.frame(maxWidth: 200)
			Text("\(Int(thumbSize))")
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.frame(width: 40, alignment: .leading)
		}
	}

	@ViewBuilder
	private var resultsSection: some View {
		if let result = model.searchResult {
			if result.images.isEmpty && result.videos.isEmpty {
				Text("未找到匹配的文件")
					.foregroundStyle(.secondary)
			} else {
				VStack(alignment: .leading, spacing: 12) {
					if !result.images.isEmpty {
						sectionTitle(text: "图片（\(result.images.count) 个）")
						thumbnailGrid(items: result.images)
					}
					if !result.videos.isEmpty {
						if !result.images.isEmpty { Divider() }
						sectionTitle(text: "视频（\(result.videos.count) 个）")
						thumbnailGrid(items: result.videos)
					}
				}
			}
		}
	}

	private func sectionTitle(text: String) -> some View {
		Text(text)
			.font(.headline)
			.padding(.top, 4)
	}

	private func thumbnailGrid(items: [FinderSearchService.SearchItem]) -> some View {
		LazyVGrid(columns: [GridItem(.adaptive(minimum: thumbSize, maximum: thumbSize + 20), spacing: 8)],
		          spacing: 8) {
			ForEach(items.indices, id: \.self) { i in
				let item = items[i]
				MediaThumbnailView(url: item.url, size: thumbSize, isVideo: isVideoExt(item.url), creationDate: item.creationDate)
					.onTapGesture(count: 2) {
						NSWorkspace.shared.open(item.url)
					}
					.contextMenu {
						Button("打开") {
							NSWorkspace.shared.open(item.url)
						}
						Button("在 Finder 中显示") {
							NSWorkspace.shared.activateFileViewerSelecting([item.url])
						}
					}
			}
		}
	}

	private var emptyHint: some View {
		Text("请选择文件夹并输入关键词后搜索")
			.foregroundStyle(.secondary)
			.font(.subheadline)
	}

	private var searchingHint: some View {
		HStack {
			ProgressView()
			Text("搜索中…")
				.foregroundStyle(.secondary)
		}
	}

	// MARK: - Helpers

	private func isVideoExt(_ url: URL) -> Bool {
		FinderSearchService.videoExts.contains(url.pathExtension.lowercased())
	}
}

// MARK: - MediaThumbnailView

private struct MediaThumbnailView: View {
	let url: URL
	let size: CGFloat
	let isVideo: Bool
	let creationDate: Date?

	@State private var image: NSImage?
	@State private var isLoading = true

	var body: some View {
		VStack(spacing: 4) {
			Group {
				if let nsImage = image {
					Image(nsImage: nsImage)
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
						.overlay(
							Group {
								if isVideo {
									Image(systemName: "film")
										.font(.system(size: size * 0.3))
										.foregroundStyle(.secondary)
								} else {
									ProgressView().scaleEffect(0.6)
								}
							}
						)
				} else {
					RoundedRectangle(cornerRadius: 6)
						.fill(Color.secondary.opacity(0.1))
						.frame(width: size, height: size)
						.overlay(
							Image(systemName: isVideo ? "film" : "photo")
								.font(.system(size: size * 0.3))
								.foregroundStyle(.secondary)
						)
				}
			}
			Text(url.lastPathComponent)
				.font(.caption)
				.lineLimit(2)
				.truncationMode(.middle)
			if let dateStr = dateStr {
				Text(dateStr)
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
		}
		.task {
			await loadThumbnail()
		}
	}

	private var dateStr: String? {
		guard let d = creationDate else { return nil }
		return Formatter.dateFormatter.string(from: d)
	}

	private func loadThumbnail() async {
		let img = await Task.detached(priority: .userInitiated) { () -> NSImage? in
			if self.isVideo {
				return self.loadVideoFrame()
			} else {
				return self.loadImageThumbnail()
			}
		}.value
		await MainActor.run {
			self.image = img
			self.isLoading = false
		}
	}

	private func loadImageThumbnail() -> NSImage? {
		let options: NSDictionary = [:]
		guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { return nil }
		let thumbnailOptions: [CFString: Any] = [
			kCGImageSourceThumbnailMaxPixelSize: max(size * 2, 200),
			kCGImageSourceCreateThumbnailWithTransform: true,
			kCGImageSourceCreateThumbnailFromImageAlways: true
		]
		guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
			return nil
		}
		return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
	}

	private func loadVideoFrame() -> NSImage? {
		let asset = AVURLAsset(url: url)
		let gen = AVAssetImageGenerator(asset: asset)
		gen.appliesPreferredTrackTransform = true
		gen.maximumSize = CGSize(width: size * 2, height: size * 2)
		let tolerance = CMTime.zero
		gen.requestedTimeToleranceBefore = tolerance
		gen.requestedTimeToleranceAfter = tolerance
		do {
			let cgImage = try gen.copyCGImage(at: CMTime(seconds: 0, preferredTimescale: 600), actualTime: nil)
			return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
		} catch {
			return nil
		}
	}
}

// MARK: - Date Formatter Extension

private extension Formatter {
	static var dateFormatter: DateFormatter = {
		let f = DateFormatter()
		f.dateFormat = "yyyy-MM-dd"
		return f
	}()
}
