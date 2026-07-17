import SwiftUI
import UniformTypeIdentifiers

// MARK: - 统一布局模板

/// 所有 Feature View 的标准容器
/// 使用方式：
/// StandardFeatureView {
///     // 你的内容
/// }
public struct StandardFeatureView<Content: View>: View {
	let content: Content
	let scrollIndicators: ScrollIndicatorVisibility
	
	public init(
		scrollIndicators: ScrollIndicatorVisibility = .visible,
		@ViewBuilder content: () -> Content
	) {
		self.content = content()
		self.scrollIndicators = scrollIndicators
	}
	
	public var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 14) {
				content
			}
			.padding()
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.scrollIndicators(scrollIndicators)
		.background(Color(NSColor.controlBackgroundColor))
	}
}

// MARK: - 标准 Section 容器

/// 标准分组框
public struct StandardSection<Content: View>: View {
	let label: String
	let systemImage: String?
	let content: Content
	
	public init(
		_ label: String,
		systemImage: String? = nil,
		@ViewBuilder content: () -> Content
	) {
		self.label = label
		self.systemImage = systemImage
		self.content = content()
	}
	
	public var body: some View {
		GroupBox {
			VStack(alignment: .leading, spacing: 10) {
				content
			}
			.padding(8)
		} label: {
			HStack(spacing: 4) {
				if let systemImage {
					Image(systemName: systemImage)
				}
				Text(label)
					.font(.headline)
			}
		}
	}
}

// MARK: - 标准 Action Row

/// 统一的操作按钮行
public struct StandardActionRow: View {
	let primaryTitle: String
	let primaryAction: () -> Void
	let primaryDisabled: Bool
	let isWorking: Bool
	let secondaryTitle: String?
	let secondaryAction: (() -> Void)?
	let progress: Double?
	let progressText: String?
	
	public init(
		primaryTitle: String,
		primaryAction: @escaping () -> Void,
		primaryDisabled: Bool = false,
		isWorking: Bool = false,
		secondaryTitle: String? = nil,
		secondaryAction: (() -> Void)? = nil,
		progress: Double? = nil,
		progressText: String? = nil
	) {
		self.primaryTitle = primaryTitle
		self.primaryAction = primaryAction
		self.primaryDisabled = primaryDisabled
		self.isWorking = isWorking
		self.secondaryTitle = secondaryTitle
		self.secondaryAction = secondaryAction
		self.progress = progress
		self.progressText = progressText
	}
	
	public var body: some View {
		HStack(spacing: 12) {
			Button(isWorking ? "执行中…" : primaryTitle) {
				primaryAction()
			}
			.disabled(primaryDisabled || isWorking)
			.buttonStyle(.borderedProminent)
			
			if let progress {
				ProgressView(value: progress)
					.frame(maxWidth: 150)
				if let progressText {
					Text(progressText)
						.monospacedDigit()
						.foregroundStyle(.secondary)
				}
			} else if isWorking {
				ProgressView()
			}
			
			if let secondaryTitle, let secondaryAction {
				Button(secondaryTitle, action: secondaryAction)
					.buttonStyle(.borderless)
			}
		}
	}
}

// MARK: - 标准文件/文件夹选择器

/// 统一风格的打开面板按钮
public struct StandardOpenPanelButton: View {
	public enum Mode {
		case file(allowedTypes: [UTType], allowsMultipleSelection: Bool)
		case folder
		case mediaFiles
	}
	
	let title: String
	let mode: Mode
	let action: ([URL]) -> Void
	let disabled: Bool
	
	public init(
		_ title: String,
		mode: Mode,
		disabled: Bool = false,
		action: @escaping ([URL]) -> Void
	) {
		self.title = title
		self.mode = mode
		self.disabled = disabled
		self.action = action
	}
	
	public var body: some View {
		Button(title) {
			let panel = NSOpenPanel()
			switch mode {
			case .file(let types, let multiple):
				panel.allowedContentTypes = types
				panel.allowsMultipleSelection = multiple
			case .folder:
				panel.canChooseDirectories = true
				panel.canChooseFiles = false
			case .mediaFiles:
				panel.allowedContentTypes = [.movie, .image, .mpeg4Movie, .quickTimeMovie, .jpeg, .png, .heic, .gif, .tiff, .bmp]
				panel.allowsMultipleSelection = true
			}
			panel.canCreateDirectories = true
			if panel.runModal() == .OK {
				action(panel.urls)
			}
		}
		.disabled(disabled)
	}
}

// MARK: - 标准状态行

/// 统一的状态文本显示
public struct StandardStatusRow: View {
	let status: String
	let phase: String?
	let isWorking: Bool
	
	public init(
		status: String,
		phase: String? = nil,
		isWorking: Bool = false
	) {
		self.status = status
		self.phase = phase
		self.isWorking = isWorking
	}
	
	public var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(status)
				.foregroundStyle(.secondary)
			
			if isWorking, let phase, !phase.isEmpty {
				Text(phase)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
	}
}

// MARK: - 标准错误行

public struct StandardErrorRow: View {
	let message: String
	let actionTitle: String?
	let action: (() -> Void)?
	
	public init(
		_ message: String,
		actionTitle: String? = nil,
		action: (() -> Void)? = nil
	) {
		self.message = message
		self.actionTitle = actionTitle
		self.action = action
	}
	
	public var body: some View {
		HStack {
			Image(systemName: "exclamationmark.triangle.fill")
				.foregroundStyle(.red)
			Text(message)
				.foregroundStyle(.red)
			Spacer()
			if let actionTitle, let action {
				Button(actionTitle, action: action)
					.buttonStyle(.borderless)
					.foregroundStyle(.red)
			}
		}
		.padding(8)
		.background(Color.red.opacity(0.1))
		.cornerRadius(6)
	}
}

// MARK: - 标准忽略/删除确认对话框

/// 统一的确认对话框工具
public enum StandardAlert {
	/// 显示"忽略本组"确认
	@MainActor
	public static func confirmIgnore(
		title: String = "本次忽略",
		message: String,
		confirmTitle: String = "确定",
		cancelTitle: String = "取消",
		onConfirm: @escaping () -> Void
	) {
		let alert = NSAlert()
		alert.messageText = title
		alert.informativeText = message
		alert.alertStyle = .informational
		alert.addButton(withTitle: confirmTitle)
		alert.addButton(withTitle: cancelTitle)
		if alert.runModal() == .alertFirstButtonReturn {
			onConfirm()
		}
	}
	
	/// 显示删除确认
	@MainActor
	public static func confirmDelete(
		itemName: String,
		message: String? = nil,
		confirmTitle: String = "删除",
		cancelTitle: String = "取消",
		onConfirm: @escaping () -> Void
	) {
		let alert = NSAlert()
		alert.messageText = "确认删除"
		alert.informativeText = message ?? "确定要将 \"\(itemName)\" 移到废纸篓吗？此操作可在废纸篓中撤销。"
		alert.alertStyle = .warning
		alert.addButton(withTitle: confirmTitle)
		alert.addButton(withTitle: cancelTitle)
		if alert.runModal() == .alertFirstButtonReturn {
			onConfirm()
		}
	}
	
	/// 显示批量删除确认
	@MainActor
	public static func confirmBatchDelete(
		count: Int,
		message: String? = nil,
		confirmTitle: String = "删除",
		cancelTitle: String = "取消",
		onConfirm: @escaping () -> Void
	) {
		let alert = NSAlert()
		alert.messageText = "删除 \(count) 个文件"
		alert.informativeText = message ?? "是否真的要将这 \(count) 个文件移到废纸篓？"
		alert.alertStyle = .warning
		alert.addButton(withTitle: confirmTitle)
		alert.addButton(withTitle: cancelTitle)
		if alert.runModal() == .alertFirstButtonReturn {
			onConfirm()
		}
	}
	
	/// 显示错误信息
	@MainActor
	public static func showError(_ message: String) {
		let alert = NSAlert()
		alert.messageText = "错误"
		alert.informativeText = message
		alert.alertStyle = .critical
		alert.addButton(withTitle: "确定")
		alert.runModal()
	}
}

// MARK: - 标准缩略图视图

/// 异步加载显示缩略图，带占位符和错误状态
public struct StandardThumbnailView: View {
	let url: URL
	let size: CGFloat
	let cornerRadius: CGFloat
	
	@State private var image: NSImage?
	@State private var isLoading = true
	
	public init(url: URL, size: CGFloat = 100, cornerRadius: CGFloat = 6) {
		self.url = url
		self.size = size
		self.cornerRadius = cornerRadius
	}
	
	public var body: some View {
		Group {
			if let image {
				Image(nsImage: image)
					.resizable()
					.aspectRatio(contentMode: .fill)
					.frame(width: size, height: size)
					.clipped()
					.cornerRadius(cornerRadius)
					.overlay(
						RoundedRectangle(cornerRadius: cornerRadius)
							.stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
					)
			} else if isLoading {
				RoundedRectangle(cornerRadius: cornerRadius)
					.fill(Color.secondary.opacity(0.1))
					.frame(width: size, height: size)
					.overlay(ProgressView().scaleEffect(0.6))
			} else {
				RoundedRectangle(cornerRadius: cornerRadius)
					.fill(Color.secondary.opacity(0.1))
					.frame(width: size, height: size)
					.overlay(
						Image(systemName: "photo")
							.font(.system(size: size * 0.4))
							.foregroundStyle(.secondary)
					)
			}
		}
		.task {
			await loadThumbnail()
		}
	}
	
	private func loadThumbnail() async {
		let thumbnail = await Task.detached(priority: .userInitiated) { () -> NSImage? in
			let options: [CFString: Any] = [
				kCGImageSourceThumbnailMaxPixelSize: max(self.size * 2, 200),
				kCGImageSourceCreateThumbnailWithTransform: true,
				kCGImageSourceCreateThumbnailFromImageAlways: true
			]
			guard let source = CGImageSourceCreateWithURL(self.url as CFURL, nil) else { return nil }
			guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
			return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
		}.value
		
		await MainActor.run {
			self.image = thumbnail
			self.isLoading = false
		}
	}
}

// MARK: - 标准结果列表行

/// 统一的结果项行（用于 DuplicatePhoto/Video 等）
public struct StandardResultRow<Content: View>: View {
	let thumbnail: AnyView?
	let mainContent: Content
	let actions: [StandardRowAction]
	let onTap: (() -> Void)?
	
	public init(
		thumbnail: AnyView? = nil,
		@ViewBuilder mainContent: () -> Content,
		actions: [StandardRowAction] = [],
		onTap: (() -> Void)? = nil
	) {
		self.thumbnail = thumbnail
		self.mainContent = mainContent()
		self.actions = actions
		self.onTap = onTap
	}
	
	public var body: some View {
		HStack(spacing: 12) {
			if let thumbnail {
				thumbnail
			}
			mainContent
			Spacer()
			ForEach(actions) { action in
				Button(action.title, action: action.handler)
					.buttonStyle(.borderless)
					.foregroundStyle(action.style.color)
			}
		}
		.contentShape(Rectangle())
		.onTapGesture { onTap?() }
	}
}

public struct StandardRowAction: Identifiable {
	public let id = UUID()
	public let title: String
	public let handler: () -> Void
	public let style: Style
	
	public enum Style {
		case normal
		case destructive
		case warning
		
		var color: Color {
			switch self {
			case .normal: return .primary
			case .destructive: return .red
			case .warning: return .orange
			}
		}
	}
	
	public init(_ title: String, style: Style = .normal, handler: @escaping () -> Void) {
		self.title = title
		self.style = style
		self.handler = handler
	}
}

// MARK: - 标准空状态视图

public struct StandardEmptyState: View {
	let systemImage: String
	let title: String
	let message: String
	let actionTitle: String?
	let action: (() -> Void)?
	
	public init(
		systemImage: String,
		title: String,
		message: String,
		actionTitle: String? = nil,
		action: (() -> Void)? = nil
	) {
		self.systemImage = systemImage
		self.title = title
		self.message = message
		self.actionTitle = actionTitle
		self.action = action
	}
	
	public var body: some View {
		VStack(spacing: 16) {
			Image(systemName: systemImage)
				.font(.system(size: 48))
				.foregroundStyle(.secondary)
			
			VStack(spacing: 8) {
				Text(title)
					.font(.headline)
				Text(message)
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
			}
			
			if let actionTitle, let action {
				Button(actionTitle, action: action)
					.buttonStyle(.borderedProminent)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.padding()
	}
}

// MARK: - 标准调试/信息标签

public struct StandardInfoBadge: View {
	let text: String
	let color: Color
	
	public init(_ text: String, color: Color = .secondary) {
		self.text = text
		self.color = color
	}
	
	public var body: some View {
		Text(text)
			.font(.caption)
			.padding(.horizontal, 6)
			.padding(.vertical, 2)
			.background(color.opacity(0.15))
			.foregroundStyle(color)
			.cornerRadius(4)
	}
}