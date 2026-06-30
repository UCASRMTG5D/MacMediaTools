import AppKit
import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct VideoCropResizeView: View {
	// MARK: - Shared
	@State private var inputURL: URL?
	@State private var isVideo: Bool = true
	@State private var player: AVPlayer?
	@State private var displaySize: CGSize?
	@State private var infoText: String = "请选择一个图片或视频文件"
	@State private var cachedCGImage: CGImage?

	// MARK: - Crop
	@State private var enableCrop: Bool = true
	@State private var normalizedRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
	@State private var cropWidthText: String = ""
	@State private var cropHeightText: String = ""
	@State private var isSyncingCropField: Bool = false

	// MARK: - Resize
	@State private var enableResize: Bool = false
	@State private var targetWidth: String = ""
	@State private var targetHeight: String = ""
	@State private var scaleMode: VideoScaleMode = .stretch

	// MARK: - Output
	@State private var outputFolder: URL?
	@State private var outputFileName: String = ""
	@State private var isWorking = false
	@State private var lastOutputURL: URL?
	@State private var errorMessage: String?
	@State private var showDeleteConfirmation = false

	// MARK: - Stretch Preview
	@State private var stretchPreviewResult: NSImage?
	@State private var previewGenTask: Task<Void, Never>?

	// MARK: - Computed
	private var sourceSize: CGSize? {
		guard let display = displaySize else { return nil }
		if enableCrop {
			return CGSize(
				width: normalizedRect.width * display.width,
				height: normalizedRect.height * display.height
			)
		}
		return display
	}

	private var effectiveCropRect: CGRect? {
		guard enableCrop, let display = displaySize else { return nil }
		return CGRect(
			x: normalizedRect.origin.x * display.width,
			y: normalizedRect.origin.y * display.height,
			width: normalizedRect.size.width * display.width,
			height: normalizedRect.size.height * display.height
		).integral
	}

	private var effectiveTargetSize: CGSize? {
		guard enableResize else { return nil }
		guard let w = Double(targetWidth), let h = Double(targetHeight), w > 2, h > 2 else { return nil }
		return CGSize(width: w, height: h)
	}

	private var canExport: Bool {
		inputURL != nil && displaySize != nil && (enableCrop || enableResize) && !isWorking
	}

	var body: some View {
		ScrollView(.vertical, showsIndicators: true) {
			VStack(alignment: .leading, spacing: 16) {
				titleSection
				fileSelectionSection
				infoSection

				if inputURL != nil {
					cropSection
					resizeSection
					stretchPreviewSection
					Divider()
					outputSection
					actionButtons
				}

				Spacer()
			}
			.padding()
			.frame(maxWidth: .infinity)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.navigationTitle("宽高调整")
		.background(Color(NSColor.controlBackgroundColor))
	}

	// MARK: - Subviews

	private var titleSection: some View {
		Text("宽高调整")
			.font(.title2)
	}

	private var fileSelectionSection: some View {
		HStack(spacing: 12) {
			OpenPanelButton(
				title: "选择文件…",
				mode: .file(allowedTypes: [.movie, .image], allowsMultipleSelection: false)
			) { urls in
				guard let url = urls.first else { return }
				selectInput(url)
			}

			Text(inputURL?.path ?? "未选择")
				.lineLimit(1)
				.truncationMode(.middle)

			if let inputURL {
				Button("在 Finder 中显示") {
					NSWorkspace.shared.activateFileViewerSelecting([inputURL])
				}
				.buttonStyle(.borderless)
			}
		}
	}

	private var infoSection: some View {
		Text(infoText)
			.foregroundStyle(.secondary)
	}

	// MARK: - Crop

	private var cropSection: some View {
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
						schedulePreviewGeneration()
					}

				if enableCrop {
					cropPreviewArea

					HStack {
						if let src = sourceSize {
							Text("裁剪后: \(Int(src.width)) × \(Int(src.height))")
								.font(.caption)
								.foregroundColor(.secondary)
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
							.foregroundColor(.secondary)
						TextField("宽", text: $cropWidthText)
							.frame(width: 80)
							.textFieldStyle(.roundedBorder)
						Text("×")
							.font(.caption)
							.foregroundColor(.secondary)
						TextField("高", text: $cropHeightText)
							.frame(width: 80)
							.textFieldStyle(.roundedBorder)
						Text("px")
							.font(.caption)
							.foregroundColor(.secondary)

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

	// MARK: - Resize

	private var resizeSection: some View {
		GroupBox {
			VStack(alignment: .leading, spacing: 10) {
				Toggle("启用尺寸调整", isOn: $enableResize)
					.toggleStyle(.switch)
					.onChange(of: enableResize) { newValue in
						if newValue, let src = sourceSize {
							if targetWidth.isEmpty { targetWidth = String(Int(src.width)) }
							if targetHeight.isEmpty { targetHeight = String(Int(src.height)) }
						}
						schedulePreviewGeneration()
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
					.foregroundColor(.secondary)
			}

			Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
				GridRow {
					Text("目标宽度")
					TextField("例如 1920", text: $targetWidth)
						.frame(width: 160)
						.onChange(of: targetWidth) { _ in schedulePreviewGeneration() }
					Text("目标高度")
					TextField("例如 1080", text: $targetHeight)
						.frame(width: 160)
						.onChange(of: targetHeight) { _ in schedulePreviewGeneration() }
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
					.onChange(of: scaleMode) { _ in schedulePreviewGeneration() }
				}
			}
		}
		.padding(.leading, 4)
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
								.foregroundColor(.secondary)
							if let src = sourceSize {
								Image(nsImage: thumbnailFromDisplay())
									.resizable()
									.aspectRatio(contentMode: .fit)
									.frame(maxHeight: 160)
									.cornerRadius(4)
							}
						}

						Image(systemName: "arrow.right")
							.foregroundColor(.secondary)

						VStack(spacing: 4) {
							Text("调整后 (\(Int(effectiveTargetSize?.width ?? 0))×\(Int(effectiveTargetSize?.height ?? 0)))")
								.font(.caption)
								.foregroundColor(.secondary)
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

	private var actionButtons: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 12) {
				Button(isWorking ? "处理中…" : "开始导出") {
					Task { await run() }
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
				deleteSourceFile()
			}
		} message: {
			Text("是否真的要删除所有源文件？将文件移到废纸篓。")
		}
	}

	// MARK: - Actions

	private func selectInput(_ url: URL) {
		inputURL = url
		errorMessage = nil
		lastOutputURL = nil
		stretchPreviewResult = nil
		cachedCGImage = nil
		normalizedRect = CGRect(x: 0, y: 0, width: 1, height: 1)

		// Detect type
		let utType = detectType(url)
		isVideo = utType?.conforms(to: .video) == true || utType?.conforms(to: .movie) == true

		if isVideo {
			player = AVPlayer(url: url)
			player?.play()
		} else {
			player = nil
			loadCGImage(from: url)
		}

		Task {
			do {
				if isVideo {
					let info = try await VideoToolkit.readDisplayInfo(url: url)
					displaySize = info.displaySize
					infoText = "原始宽高：\(Int(info.displaySize.width)) × \(Int(info.displaySize.height))"
				} else {
					guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
						  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
						throw VideoToolkitError.exportFailed("无法读取图片")
					}
					let sz = CGSize(width: image.width, height: image.height)
					displaySize = sz
					infoText = "原始尺寸：\(Int(sz.width)) × \(Int(sz.height))"
				}

				if outputFolder == nil { outputFolder = url.deletingLastPathComponent() }
				if outputFileName.isEmpty { outputFileName = defaultOutputName(for: url) }

				if let display = displaySize {
					targetWidth = String(Int(display.width))
					targetHeight = String(Int(display.height))
				}
				syncRectToFields()
			} catch {
				infoText = "读取文件信息失败：\(error.localizedDescription)"
				displaySize = nil
			}
		}
	}

	private func detectType(_ url: URL) -> UTType? {
		if let utType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
			return utType
		}
		// Fallback: check extension
		let ext = url.pathExtension.lowercased()
		if ["mp4", "mov", "m4v", "avi", "mkv", "webm"].contains(ext) {
			return .video
		}
		if ["jpg", "jpeg", "png", "tiff", "tif", "bmp", "gif", "heic", "webp"].contains(ext) {
			return .image
		}
		return nil
	}

	private func loadCGImage(from url: URL) {
		guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
			  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
		cachedCGImage = image
	}

	private func defaultOutputName(for input: URL) -> String {
		let base = input.deletingPathExtension().lastPathComponent
		let ext = isVideo ? "mp4" : "png"
		if enableCrop && enableResize { return "\(base)_crop_resize.\(ext)" }
		if enableCrop { return "\(base)_crop.\(ext)" }
		if enableResize { return "\(base)_resized.\(ext)" }
		return "\(base)_output.\(ext)"
	}

	private func buildOutputURL() -> URL? {
		guard let inputURL else { return nil }
		let folder = outputFolder ?? inputURL.deletingLastPathComponent()
		let name = outputFileName.isEmpty ? defaultOutputName(for: inputURL) : outputFileName
		return folder.appendingPathComponent(name)
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
		schedulePreviewGeneration()
	}

	// MARK: - Stretch Preview Generation

	private func schedulePreviewGeneration() {
		previewGenTask?.cancel()
		guard enableResize, let targetSize = effectiveTargetSize,
			  let inputURL, let displaySize else {
			stretchPreviewResult = nil
			return
		}

		previewGenTask = Task {
			let crop = effectiveCropRect ?? CGRect(origin: .zero, size: displaySize)
			let croppedSize = isVideo ? CGSize(width: crop.width, height: crop.height) : displaySize

			let result: CGImage?
			if isVideo {
				let asset = AVURLAsset(url: inputURL)
				let generator = AVAssetImageGenerator(asset: asset)
				generator.appliesPreferredTrackTransform = true
				generator.maximumSize = CGSize(width: displaySize.width, height: displaySize.height)
				if let cgImage = try? await generator.image(at: .zero).image {
					if enableCrop {
						let cropped = cgImage.cropping(to: crop)
						result = VideoToolkit.scaleCGImageStatic(cropped ?? cgImage, to: targetSize, scaleMode: scaleMode)
					} else {
						result = VideoToolkit.scaleCGImageStatic(cgImage, to: targetSize, scaleMode: scaleMode)
					}
				} else {
					result = nil
				}
			} else {
				if cachedCGImage == nil { loadCGImage(from: inputURL) }
				guard let cgImage = cachedCGImage else { return }
				if enableCrop, crop != CGRect(origin: .zero, size: CGSize(width: cgImage.width, height: cgImage.height)) {
					if let cropped = cgImage.cropping(to: crop) {
						result = VideoToolkit.scaleCGImageStatic(cropped, to: targetSize, scaleMode: scaleMode)
					} else {
						result = VideoToolkit.scaleCGImageStatic(cgImage, to: targetSize, scaleMode: scaleMode)
					}
				} else {
					result = VideoToolkit.scaleCGImageStatic(cgImage, to: targetSize, scaleMode: scaleMode)
				}
			}

			if !Task.isCancelled, let result {
				stretchPreviewResult = NSImage(cgImage: result, size: NSSize(width: targetSize.width, height: targetSize.height))
			}
		}
	}

	private func thumbnailFromDisplay() -> NSImage {
		guard let displaySize else { return NSImage(size: .zero) }
		if isVideo {
			if let player, let asset = player.currentItem?.asset {
				let generator = AVAssetImageGenerator(asset: asset)
				generator.appliesPreferredTrackTransform = true
				generator.maximumSize = CGSize(width: 320, height: 320)
				if let cgImage = try? generator.copyCGImage(at: player.currentTime(), actualTime: nil) {
					return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
				}
			}
			return NSImage(size: displaySize)
		} else if let cgImage = cachedCGImage {
			let thumb = VideoToolkit.scaleCGImageStatic(cgImage, to: CGSize(width: 320, height: 320), scaleMode: .aspectFit)
			if let thumb {
				return NSImage(cgImage: thumb, size: NSSize(width: thumb.width, height: thumb.height))
			}
			return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
		}
		return NSImage(size: displaySize)
	}

	// MARK: - Export

	@MainActor
	private func run() async {
		guard let inputURL, let outURL = buildOutputURL() else { return }
		isWorking = true
		errorMessage = nil
		lastOutputURL = nil
		defer { isWorking = false }

		do {
			if isVideo {
				try await VideoToolkit.exportCroppedAndResized(
					inputURL: inputURL,
					outputURL: outURL,
					cropRect: effectiveCropRect,
					targetSize: effectiveTargetSize,
					scaleMode: scaleMode
				)
			} else {
				try await VideoToolkit.exportImageCroppedAndResized(
					inputURL: inputURL,
					outputURL: outURL,
					cropRect: effectiveCropRect,
					targetSize: effectiveTargetSize,
					scaleMode: scaleMode
				)
			}
			lastOutputURL = outURL
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	private func deleteSourceFile() {
		guard let inputURL else { return }
		do {
			try NSWorkspace.shared.recycle([inputURL])
			self.inputURL = nil
			displaySize = nil
			player = nil
			cachedCGImage = nil
			stretchPreviewResult = nil
			normalizedRect = CGRect(x: 0, y: 0, width: 1, height: 1)
			infoText = "源文件已移入废纸篓"
		} catch {
			errorMessage = "删除失败：\(error.localizedDescription)"
		}
	}
}
