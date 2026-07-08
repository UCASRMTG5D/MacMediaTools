import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

// MARK: - CanvasStore

/// 画布状态存储（使用 @ObservableObject 以兼容 macOS 13+）
@MainActor
final class CanvasStore: ObservableObject {
	@Published var elements: [CanvasElement] = []
	@Published var selectedElementID: UUID?
	@Published var canvasScale: CGFloat = 1.0
	@Published var canvasOffset: CGSize = .zero
	@Published var settings = CanvasSettings()
	@Published var outputFolder: URL?
	@Published var outputFileName: String = "canvas_composition.mp4"
	@Published var isWorking = false
	@Published var errorMessage: String?
	@Published var lastOutputURL: URL?

	var selectedElement: CanvasElement? {
		get { elements.first { $0.id == selectedElementID } }
		set {
			if let newValue, let index = elements.firstIndex(where: { $0.id == newValue.id }) {
				elements[index] = newValue
			}
		}
	}

	/// 添加媒体文件并创建画布元素
	func addMedia(urls: [URL]) async {
		for url in urls {
			let ext = url.pathExtension.lowercased()
			let mediaType: CanvasMediaType
			if MediaFileExtensions.photo.contains(ext) {
				mediaType = ext == "gif" ? .gif : .image
			} else if MediaFileExtensions.video.contains(ext) {
				mediaType = .video
			} else {
				continue
			}

			let displaySize: CGSize
			let duration: Double

			if mediaType == .image {
				displaySize = await readImageSize(url: url) ?? CGSize(width: 640, height: 480)
				duration = 0
			} else if mediaType == .gif {
				let info = try? await Task.detached { () -> VideoDisplayInfo? in
					try? await VideoToolkit.readDisplayInfo(url: url)
				}.value
				displaySize = info?.displaySize ?? CGSize(width: 320, height: 240)
				duration = info?.durationSeconds ?? 3.0
			} else {
				let info = try? await Task.detached { () -> VideoDisplayInfo? in
					try? await VideoToolkit.readDisplayInfo(url: url)
				}.value
				displaySize = info?.displaySize ?? CGSize(width: 640, height: 480)
				duration = info?.durationSeconds ?? 3.0
			}

			// 随机画布位置（防止重叠）
			let pos = randomCanvasPosition(displaySize: displaySize)
			let element = CanvasElement(
				sourceURL: url,
				mediaType: mediaType,
				displaySize: displaySize,
				duration: duration,
				position: pos,
				zIndex: elements.count
			)
			elements.append(element)
		}
	}

	private func randomCanvasPosition(displaySize: CGSize) -> CGPoint {
		let margin: CGFloat = 20
		let maxX = max(0, settings.canvasSize.width - displaySize.width - margin * 2)
		let maxY = max(0, settings.canvasSize.height - displaySize.height - margin * 2)
		// 基于已有元素数量分散摆放
		let col = elements.count % 3
		let row = elements.count / 3
		return CGPoint(
			x: margin + CGFloat(col) * (displaySize.width + margin * 2),
			y: margin + CGFloat(row) * (displaySize.height + margin * 2)
		)
	}

	private func readImageSize(url: URL) async -> CGSize? {
		await Task.detached {
			guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
			let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
			let w = props?[kCGImagePropertyPixelWidth as String] as? CGFloat
			let h = props?[kCGImagePropertyPixelHeight as String] as? CGFloat
			guard let w, let h else { return nil }
			return CGSize(width: w, height: h)
		}.value
	}

	func removeElement(_ id: UUID) {
		elements.removeAll { $0.id == id }
		if selectedElementID == id { selectedElementID = nil }
	}

	func clearAll() {
		elements.removeAll()
		selectedElementID = nil
		canvasScale = 1.0
		canvasOffset = .zero
		lastOutputURL = nil
		errorMessage = nil
	}

	func removeAllSelected() {
		if let id = selectedElementID {
			removeElement(id)
		}
	}
}

// MARK: - SpatialCanvasView

struct SpatialCanvasView: View {
	@StateObject private var store = CanvasStore()
	@State private var isImporting = false
	@State private var isExporting = false
	@State private var editMode: CanvasEditMode = .move

	enum CanvasEditMode: String, CaseIterable {
		case move = "移动"
		case resize = "缩放"
		case crop = "裁切"

		var id: String { rawValue }
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 14) {
				// 导入区域
				importSection

				// 编辑模式选择
				if !store.elements.isEmpty {
					editModeSection
				}

				// 画布区域
				if !store.elements.isEmpty {
					canvasSection
						.frame(minHeight: 400)
				}

				// 选中元素的属性面板
				if let el = store.selectedElement {
					inspectorSection(element: el)
				}

				Divider()

				// 输出设置
				outputSection
			}
			.padding()
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.scrollIndicators(.visible)
		.background(Color(NSColor.controlBackgroundColor))
	}

	// MARK: - Import Section

	private var importSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Label("素材导入", systemImage: "plus.square.dashed")
				.font(.headline)

			HStack(spacing: 10) {
				OpenPanelButton(
					title: isImporting ? "加载中…" : "选择媒体文件…",
					mode: .mediaFiles
				) { urls in
					guard !urls.isEmpty else { return }
					isImporting = true
					Task {
						await store.addMedia(urls: urls)
						isImporting = false
					}
				}
				.disabled(isImporting || isExporting)

				if !store.elements.isEmpty {
					Button("清空画布", role: .destructive) {
						store.clearAll()
					}
				}
			}

			if !store.elements.isEmpty {
				Text("已导入 \(store.elements.count) 个素材（点击画布中的元素可选中编辑）")
					.font(.caption)
					.foregroundStyle(.secondary)
			} else {
				Text("尚无素材，请点击上方按钮导入图片、视频或 GIF 文件")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
	}

	// MARK: - Edit Mode

	private var editModeSection: some View {
		HStack(spacing: 8) {
			Text("编辑模式：")
				.font(.subheadline)

			Picker("模式", selection: $editMode) {
				ForEach(CanvasEditMode.allCases, id: \.self) { mode in
					Text(mode.rawValue).tag(mode)
				}
			}
			.pickerStyle(.segmented)
			.frame(width: 240)

			Text("切换编辑模式以进行不同的操作")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
	}

	// MARK: - Canvas Section

	private var canvasSection: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack {
				Label("画布", systemImage: "square.grid.3x3")
					.font(.headline)
				Spacer()
				Text("\(Int(store.settings.canvasSize.width)) × \(Int(store.settings.canvasSize.height)) px")
					.font(.caption)
					.foregroundStyle(.secondary)
				Button("适应画布") { resetCanvasView() }
					.buttonStyle(.borderless)
					.font(.caption)
			}

			// 画布 ZStack
			ZStack {
				// 背景
				Rectangle()
					.fill(Color.black)
					.frame(width: canvasDisplaySize.width, height: canvasDisplaySize.height)

				// 元素层
				ForEach(store.elements) { element in
					CanvasElementView(
						element: element,
						isSelected: element.id == store.selectedElementID
					)
					.onTapGesture {
						store.selectedElementID = element.id
					}
					.gesture(editMode == .move ? dragGesture(for: element) : nil)
				}

				// 选中元素的手柄层
				if let el = store.selectedElement,
				   let index = store.elements.firstIndex(where: { $0.id == el.id }),
				   editMode == .resize {
					CanvasResizeHandles(
						element: Binding<CanvasElement>(
							get: { store.elements[index] },
							set: { store.elements[index] = $0 }
						)
					)
				}

				Color.clear
					.contentShape(Rectangle())
					.highPriorityGesture(
						MagnificationGesture()
							.onChanged { value in
								let newScale = max(0.3, min(3.0, store.canvasScale * value))
								store.canvasScale = newScale
							}
					)
			}
			.coordinateSpace(name: "canvas")
			.clipShape(RoundedRectangle(cornerRadius: 4))
			.overlay(
				RoundedRectangle(cornerRadius: 4)
					.stroke(Color.secondary.opacity(0.3))
			)
			.scaleEffect(store.canvasScale)
			.offset(store.canvasOffset)
			.gesture(
				DragGesture()
					.onChanged { value in
						store.canvasOffset = value.translation
					}
					.onEnded { value in
						store.canvasOffset = value.translation
					}
			)
			.frame(width: min(canvasDisplaySize.width * store.canvasScale, 800),
				   height: min(canvasDisplaySize.height * store.canvasScale, 500))
			.clipped()
			.background(Color(NSColor.textBackgroundColor).opacity(0.05))
		}
	}

	private var canvasDisplaySize: CGSize {
		let maxDisplay: CGFloat = 760
		let cs = store.settings.canvasSize
		if cs.width > maxDisplay {
			let ratio = maxDisplay / cs.width
			return CGSize(width: maxDisplay, height: cs.height * ratio)
		}
		return cs
	}

	private func resetCanvasView() {
		store.canvasScale = 1.0
		store.canvasOffset = .zero
	}

	// MARK: - Drag Gesture

	private func dragGesture(for element: CanvasElement) -> some Gesture {
		DragGesture(coordinateSpace: .named("canvas"))
			.onChanged { value in
				guard let index = store.elements.firstIndex(where: { $0.id == element.id }) else { return }
				store.elements[index].position = CGPoint(
					x: element.position.x + value.translation.width / store.canvasScale,
					y: element.position.y + value.translation.height / store.canvasScale
				)
				store.selectedElementID = element.id
			}
			.onEnded { _ in
				// 最终位置已经更新
			}
	}

	// MARK: - Inspector Section

	private func inspectorSection(element: CanvasElement) -> some View {
		GroupBox {
			VStack(alignment: .leading, spacing: 8) {
				Label("元素属性", systemImage: "slider.horizontal.3")
					.font(.headline)

				HStack {
					Text(element.sourceURL.lastPathComponent)
						.font(.caption)
						.foregroundStyle(.secondary)
					Spacer()
					Button("删除", role: .destructive) {
						store.removeElement(element.id)
					}
					.buttonStyle(.borderless)
					.font(.caption)
				}

				Divider()

				Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
					GridRow {
						Text("位置 X")
						textFieldBinding(value: Binding<Double>(
							get: { Double(element.position.x) },
							set: { newVal in updateElement(id: element.id) { $0.position.x = max(0, CGFloat(newVal)) } }
						))
						Text("Y")
						textFieldBinding(value: Binding<Double>(
							get: { Double(element.position.y) },
							set: { newVal in updateElement(id: element.id) { $0.position.y = max(0, CGFloat(newVal)) } }
						))
					}

					GridRow {
						Text("缩放")
						Slider(value: Binding<CGFloat>(
							get: { element.scale },
							set: { newVal in updateElement(id: element.id) { $0.scale = max(0.1, min(10, newVal)) } }
						), in: 0.1...10, step: 0.1)
						.frame(width: 120)
						Text(String(format: "%.1f×", element.scale))
							.font(.caption)
							.frame(width: 40)
					}

					GridRow {
						Text("音量")
						Slider(value: Binding<CGFloat>(
							get: { CGFloat(element.volume) },
							set: { newVal in updateElement(id: element.id) { $0.volume = Double(max(0, min(1, newVal))) } }
						), in: 0...1, step: 0.05)
						.frame(width: 120)
						Text(element.mediaType == .image ? "N/A" : "\(Int(element.volume * 100))%")
							.font(.caption)
							.frame(width: 40)
							.foregroundStyle(element.mediaType == .image ? .secondary : .primary)
					}
				}
			}
			.padding(8)
		}
	}

	private func updateElement(id: UUID, mutate: (inout CanvasElement) -> Void) {
		guard let index = store.elements.firstIndex(where: { $0.id == id }) else { return }
		var el = store.elements[index]
		mutate(&el)
		store.elements[index] = el
	}

	private func textFieldBinding(value: Binding<Double>) -> some View {
		TextField("", value: value, format: .number)
			.textFieldStyle(.roundedBorder)
			.frame(width: 70)
	}

	// MARK: - Output Section

	private var outputSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Label("导出", systemImage: "square.and.arrow.up")
				.font(.headline)

			if store.elements.isEmpty {
				Text("请先导入素材")
					.font(.caption)
					.foregroundStyle(.secondary)
			} else {
				Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
					GridRow {
						Text("画布尺寸")
						Picker("宽", selection: Binding<Int>(
							get: { Int(store.settings.canvasSize.width) },
							set: { store.settings.canvasSize.width = CGFloat($0) }
						)) {
							Text("1920").tag(1920)
							Text("1280").tag(1280)
							Text("1080").tag(1080)
							Text("720").tag(720)
							Text("自定义").tag(0)
						}
						.pickerStyle(.menu)
						.frame(width: 100)

						Text("×")

						Picker("高", selection: Binding<Int>(
							get: { Int(store.settings.canvasSize.height) },
							set: { store.settings.canvasSize.height = CGFloat($0) }
						)) {
							Text("1080").tag(1080)
							Text("720").tag(720)
							Text("1920").tag(1920)
							Text("1280").tag(1280)
							Text("自定义").tag(0)
						}
						.pickerStyle(.menu)
						.frame(width: 100)
					}

					GridRow {
						Text("输出目录")
						HStack {
							OpenPanelButton(title: "选择…", mode: .folder) { urls in
								store.outputFolder = urls.first
							}
							Text(store.outputFolder?.path ?? "(默认：桌面)")
								.lineLimit(1)
								.truncationMode(.middle)
						}
						.gridCellColumns(3)
					}

					GridRow {
						Text("文件名")
						TextField("canvas_composition.mp4", text: $store.outputFileName)
							.frame(maxWidth: 300)
							.gridCellColumns(3)
					}
				}

				HStack(spacing: 10) {
					Button(isExporting ? "导出中…" : "开始导出") {
						Task { await exportCanvas() }
					}
					.disabled(store.elements.isEmpty || isExporting)

					if let errorMsg = store.errorMessage {
						Text(errorMsg)
							.foregroundStyle(.red)
							.font(.caption)
					}

					if let lastURL = store.lastOutputURL {
						Button("在 Finder 中显示") {
							NSWorkspace.shared.activateFileViewerSelecting([lastURL])
						}
						.buttonStyle(.borderless)
						.font(.caption)
					}
				}
			}
		}
	}

	// MARK: - Export

	private func exportCanvas() async {
		guard await WorkManager.shared.requestStart(.spatialCanvas) else { return }
		isExporting = true
		store.isWorking = true
		store.errorMessage = nil
		defer {
			isExporting = false
			store.isWorking = false
			WorkManager.shared.finishWork(.spatialCanvas)
		}

		let inputs = store.elements.map { el in
			CanvasElementInput(
				sourceURL: el.sourceURL,
				mediaType: el.mediaType,
				displaySize: el.displaySize,
				duration: el.duration,
				position: el.position,
				effectiveSize: el.effectiveSize,
				cropRect: el.cropRect,
				volume: el.volume,
				zIndex: el.zIndex
			)
		}

		let folder = store.outputFolder ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
		let name = store.outputFileName.isEmpty ? "canvas_composition.mp4" : store.outputFileName
		let outputURL = folder.appendingPathComponent(name)

		// 检查文件是否已存在
		if FileManager.default.fileExists(atPath: outputURL.path) {
			store.errorMessage = "文件已存在，请更改文件名或选择其他目录"
			return
		}

		do {
			try await SpatialCanvasToolkit.shared.exportCanvas(
				inputs: inputs,
				canvasSize: store.settings.canvasSize,
				outputURL: outputURL
			)
			store.lastOutputURL = outputURL
		} catch {
			store.errorMessage = error.localizedDescription
		}
	}
}
