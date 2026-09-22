import SwiftUI

struct ResizeSettingsView: View {
	@Binding var enableResize: Bool
	@Binding var targetWidth: String
	@Binding var targetHeight: String
	@Binding var scaleMode: VideoScaleMode

	let sourceSize: CGSize?

	let onSchedulePreviewGeneration: () -> Void

	var body: some View {
		GroupBox {
			VStack(alignment: .leading, spacing: 10) {
				Toggle("启用尺寸调整", isOn: $enableResize)
					.toggleStyle(.switch)
					.onChange(of: enableResize) { newValue in
						if newValue, let src = sourceSize {
							if targetWidth.isEmpty { targetWidth = String(Int(src.width)) }
							if targetHeight.isEmpty { targetHeight = String(Int(src.height)) }
						}
						onSchedulePreviewGeneration()
					}

				if enableResize {
					resizeForm
				}
			}
		} label: {
			Label("第二步：尺寸调整", systemImage: "rectangle.arrowtriangle.2.outward")
				.font(.headline)
		}
	}

	private var resizeForm: some View {
		VStack(alignment: .leading, spacing: 10) {
			if let src = sourceSize {
				Text("来源分辨率: \(Int(src.width)) × \(Int(src.height))")
					.font(.caption)
					.foregroundStyle(.secondary)
			}

			Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
				GridRow {
					Text("目标宽度")
					TextField("例如 1920", text: $targetWidth)
						.frame(width: 160)
						.onChange(of: targetWidth) { _ in onSchedulePreviewGeneration() }
					Text("目标高度")
					TextField("例如 1080", text: $targetHeight)
						.frame(width: 160)
						.onChange(of: targetHeight) { _ in onSchedulePreviewGeneration() }
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
					.onChange(of: scaleMode) { _ in onSchedulePreviewGeneration() }
				}
			}

			HStack(spacing: 8) {
				Text("宽高比预设")
					.font(.caption)
					.foregroundStyle(.secondary)

				ForEach(AspectRatioPreset.all) { preset in
					Button(preset.label) { applyAspectPreset(preset) }
						.buttonStyle(.bordered)
						.controlSize(.small)
						.font(.caption)
				}

				Button("恢复原始尺寸") { restoreOriginalSize() }
					.buttonStyle(.bordered)
					.controlSize(.small)
					.font(.caption)
					.disabled(sourceSize == nil)
			}
		}
		.padding(.leading, 4)
	}

	private func applyAspectPreset(_ preset: AspectRatioPreset) {
		// 在来源分辨率内取满足比例且面积最大的整数尺寸
		guard let src = sourceSize else { return }
		var w = src.width
		var h = w / preset.ratio
		if h > src.height { h = src.height; w = h * preset.ratio }
		targetWidth = String(Int(w.rounded()))
		targetHeight = String(Int(h.rounded()))
		onSchedulePreviewGeneration()
	}

	private func restoreOriginalSize() {
		guard let src = sourceSize else { return }
		targetWidth = String(Int(src.width))
		targetHeight = String(Int(src.height))
		onSchedulePreviewGeneration()
	}
}
