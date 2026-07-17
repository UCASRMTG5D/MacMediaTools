import AppKit
import SwiftUI

// MARK: - Photo Comparison Panel (for similar photos side-by-side preview)

struct PhotoComparisonPanel: View {
	let items: [SimilarPhotoClusterer.PhotoClusterItem]

	@State private var thumbnailSize: CGSize = CGSize(width: 200, height: 200)

	init(items: [SimilarPhotoClusterer.PhotoClusterItem]) {
		self.items = items
	}

	var body: some View {
		VStack(spacing: 8) {
			// Global controls
			HStack {
				Text("左右拖动滑动条查看对比，或点击图片在 Finder 中显示")
					.font(.caption)
					.foregroundStyle(.secondary)
				Spacer()
			}
			.padding(.horizontal, 8)

			// Image strip - horizontal scroll
			ScrollView(.horizontal, showsIndicators: true) {
				HStack(spacing: 12) {
					ForEach(items) { item in
						PhotoColumn(item: item, size: thumbnailSize)
					}
				}
				.padding(.horizontal, 8)
				.padding(.vertical, 4)
			}
			.frame(minHeight: 220)

			// Thumbnail size slider
			HStack {
				Text("缩略图大小:")
					.font(.caption)
					.foregroundStyle(.secondary)
				Slider(value: Binding(
					get: { Double(thumbnailSize.width) },
					set: { thumbnailSize = CGSize(width: $0, height: $0) }
				), in: 120...400, step: 10)
				Text("\(Int(thumbnailSize.width))pt")
					.font(.caption)
					.monospacedDigit()
					.foregroundStyle(.secondary)
			}
			.padding(.horizontal, 8)
			.padding(.bottom, 4)
		}
		.frame(minHeight: 220)
	}
}

// MARK: - Single Photo Column

private struct PhotoColumn: View {
	let item: SimilarPhotoClusterer.PhotoClusterItem
	let size: CGSize

	@State private var nsImage: NSImage?

	var body: some View {
		VStack(spacing: 4) {
			ZStack {
				if let nsImage {
					Image(nsImage: nsImage)
						.resizable()
						.aspectRatio(contentMode: .fit)
				} else {
					Color(nsColor: .controlBackgroundColor)
						.overlay(
							ProgressView()
								.scaleEffect(0.7)
						)
				}
			}
			.frame(width: size.width, height: size.height)
			.clipShape(RoundedRectangle(cornerRadius: 6))
			.overlay(
				RoundedRectangle(cornerRadius: 6)
					.stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
			)
			.onTapGesture {
				NSWorkspace.shared.activateFileViewerSelecting([item.url])
			}
			.onAppear(perform: loadThumbnail)
			.help("点击在 Finder 中显示")

			Text(item.url.lastPathComponent)
				.font(.caption2)
				.lineLimit(1)
				.truncationMode(.middle)
				.frame(width: size.width)

			HStack(spacing: 4) {
				Text("距离 \(item.hammingDistanceToCentroid)")
					.font(.caption2)
					.foregroundStyle(.secondary)
				Text("\(Int(item.resolution.width))×\(Int(item.resolution.height))")
					.font(.caption2)
					.foregroundStyle(.secondary)
				Text(fileSizeString(item.fileSize))
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
			.frame(width: size.width)
		}
		.frame(width: size.width)
	}

	private func loadThumbnail() {
		// Load thumbnail in background to avoid blocking UI
		Task.detached(priority: .userInitiated) {
			if let img = NSImage(contentsOf: item.url) {
				// Create a thumbnail for faster display
				let thumb = img.resizeMaintainingAspectRatio(to: size)
				await MainActor.run {
					self.nsImage = thumb
				}
			}
		}
	}

	private func fileSizeString(_ bytes: UInt64) -> String {
		let b = Double(bytes)
		if b < 1024 { return "\(bytes) B" }
		else if b < 1024 * 1024 { return String(format: "%.1f KB", b / 1024) }
		else if b < 1024 * 1024 * 1024 { return String(format: "%.1f MB", b / (1024 * 1024)) }
		else { return String(format: "%.2f GB", b / (1024 * 1024 * 1024)) }
	}
}

// MARK: - NSImage Extension for Thumbnail

private extension NSImage {
	func resizeMaintainingAspectRatio(to targetSize: CGSize) -> NSImage {
		let aspectRatio = size.width / size.height
		let newSize: CGSize

		if targetSize.width / targetSize.height > aspectRatio {
			newSize = CGSize(width: targetSize.height * aspectRatio, height: targetSize.height)
		} else {
			newSize = CGSize(width: targetSize.width, height: targetSize.width / aspectRatio)
		}

		let newImage = NSImage(size: newSize)
		newImage.lockFocus()
		draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1.0)
		newImage.unlockFocus()
		return newImage
	}
}