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
				fileSelectionSection
				infoSection

				if inputURL != nil {
					CropSettingsView(
						enableCrop: $enableCrop,
						normalizedRect: $normalizedRect,
						cropWidthText: $cropWidthText,
						cropHeightText: $cropHeightText,
						isSyncingCropField: $isSyncingCropField,
						player: player,
						cachedCGImage: cachedCGImage,
						isVideo: isVideo,
						displaySize: displaySize,
						sourceSize: sourceSize,
						onSchedulePreviewGeneration: schedulePreviewGeneration
					)

					ResizeSettingsView(
						enableResize: $enableResize,
						targetWidth: $targetWidth,
						targetHeight: $targetHeight,
						scaleMode: $scaleMode,
						sourceSize: sourceSize,
						onSchedulePreviewGeneration: schedulePreviewGeneration
					)

					OutputSettingsView(
						outputFolder: $outputFolder,
						outputFileName: $outputFileName,
						isWorking: $isWorking,
						lastOutputURL: $lastOutputURL,
						errorMessage: $errorMessage,
						showDeleteConfirmation: $showDeleteConfirmation,
						canExport: canExport,
						inputURL: inputURL,
						enableResize: enableResize,
						effectiveTargetSize: effectiveTargetSize,
						stretchPreviewResult: stretchPreviewResult,
						sourceSize: sourceSize,
						thumbnailImage: thumbnailFromDisplay(),
						onExport: run,
						onDeleteSourceFile: deleteSourceFile
					)
				}

				Spacer()
			}
			.padding()
			.frame(maxWidth: .infinity)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(Color(NSColor.controlBackgroundColor))
	}

	// MARK: - Subviews

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
				// Sync crop fields after display size is known
				if enableCrop, let d = displaySize {
					cropWidthText = String(Int(normalizedRect.width * d.width))
					cropHeightText = String(Int(normalizedRect.height * d.height))
				}
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
