import AppKit
import AVKit
import SwiftUI

struct CropSettingsView: View {
	@Binding var enableCrop: Bool
	@Binding var normalizedRect: CGRect
	@Binding var cropWidthText: String
	@Binding var cropHeightText: String
	@Binding var isSyncingCropField: Bool

	let player: AVPlayer?
	let cachedCGImage: CGImage?
	let isVideo: Bool
	let displaySize: CGSize?
	let sourceSize: CGSize?

	let onSchedulePreviewGeneration: () -> Void

	var body: some View {
		GroupBox {
			VStack(alignment: .leading, spacing: 10) {
				Toggle("启用裁剪", isOn: $enableCrop)
					.toggleStyle(.switch)
					.onChange(of: enableCrop) { newValue in
						if !newValue {
							if isVideo { player?.play() }
						} else {
							syncRectToFields()
						}
						onSchedulePreviewGeneration()
					}

				if enableCrop {
					cropPreviewArea

					HStack {
						if let src = sourceSize {
							Text("裁剪后: \(Int(src.width)) × \(Int(src.height))")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
						Spacer()
						Button("重置为全屏") {
							withAnimation { normalizedRect = CGRect(x: 0, y: 0, width: 1, height: 1) }
						}
						.buttonStyle(.borderless)
						.font(.caption)
					}

					HStack(spacing: 8) {
						Text("裁剪宽高")
							.font(.caption)
							.foregroundStyle(.secondary)
						TextField("宽", text: $cropWidthText)
							.frame(width: 80)
							.textFieldStyle(.roundedBorder)
						Text("×")
							.font(.caption)
							.foregroundStyle(.secondary)
						TextField("高", text: $cropHeightText)
							.frame(width: 80)
							.textFieldStyle(.roundedBorder)
						Text("px")
							.font(.caption)
							.foregroundStyle(.secondary)

						Button("应用") {
							commitCropFields()
						}
						.buttonStyle(.borderedProminent)
						.controlSize(.small)
						.disabled(cropWidthText.isEmpty || cropHeightText.isEmpty)
					}
				}
			}
		} label: {
			Label("第一步：尺寸裁剪", systemImage: "crop")
				.font(.headline)
		}
	}

	private var cropPreviewArea: some View {
		GeometryReader { geo in
			let container = geo.size
			let video = displaySize ?? container
			let scale = min(
				container.width / max(video.width, 1),
				container.height / max(video.height, 1)
			)
			let fitted = CGSize(width: video.width * scale, height: video.height * scale)
			let origin = CGPoint(
				x: (container.width - fitted.width) / 2,
				y: (container.height - fitted.height) / 2
			)

			ZStack(alignment: .topLeading) {
				if isVideo {
					VideoPlayer(player: player)
						.onDisappear { player?.pause() }
				} else if let cgImage = cachedCGImage {
					let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
					Image(nsImage: nsImage)
						.resizable()
						.aspectRatio(contentMode: .fit)
				}

				CropOverlay(normalizedRect: $normalizedRect)
					.frame(width: fitted.width, height: fitted.height)
					.position(x: origin.x + fitted.width / 2, y: origin.y + fitted.height / 2)
					.allowsHitTesting(true)
			}
		}
		.frame(height: 320)
		.clipped()
		.cornerRadius(8)
	}

	// MARK: - Crop Field Sync

	private func syncRectToFields() {
		guard let d = displaySize else { return }
		isSyncingCropField = true
		cropWidthText = String(Int(normalizedRect.width * d.width))
		cropHeightText = String(Int(normalizedRect.height * d.height))
		DispatchQueue.main.async { isSyncingCropField = false }
	}

	private func commitCropFields() {
		guard let d = displaySize else { return }
		guard let w = Double(cropWidthText), let h = Double(cropHeightText), w > 2, h > 2 else { return }
		isSyncingCropField = true

		var newRect = normalizedRect
		newRect.size.width = min(w / d.width, 1 - newRect.origin.x)
		newRect.size.height = min(h / d.height, 1 - newRect.origin.y)
		newRect.size.width = max(newRect.size.width, 0.08)
		newRect.size.height = max(newRect.size.height, 0.08)
		normalizedRect = newRect

		DispatchQueue.main.async { isSyncingCropField = false }
		onSchedulePreviewGeneration()
	}
}
