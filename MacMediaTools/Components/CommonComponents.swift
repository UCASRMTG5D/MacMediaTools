import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 统一文件选择按钮

public struct FilePickerButton: View {
	public enum Mode {
		case file(allowedTypes: [UTType], allowsMultipleSelection: Bool)
		case folder
		case mediaFiles // 图片+视频
		
		var allowsMultiple: Bool {
			switch self {
			case .file(_, let multi): return multi
			case .folder: return false
			case .mediaFiles: return true
			}
		}
		
		var allowedContentTypes: [UTType]? {
			switch self {
			case .file(let types, _): return types.isEmpty ? nil : types
			case .folder: return nil
			case .mediaFiles: return [.image, .movie, .video] + [UTType("public.avi"), UTType("com.microsoft.wmv"), UTType("public.flv")].compactMap { $0 }
			}
		}
	}
	
	let title: String
	let mode: Mode
	let action: ([URL]) -> Void
	
	@State private var isLoading = false
	
	public init(
		title: String,
		mode: Mode = .file(allowedTypes: [], allowsMultipleSelection: false),
		action: @escaping ([URL]) -> Void
	) {
		self.title = title
		self.mode = mode
		self.action = action
	}
	
	public var body: some View {
		Button(title) { showPanel() }
			.disabled(isLoading)
			.buttonStyle(.bordered)
	}
	
	private func showPanel() {
		isLoading = true
		Task {
			let panel: NSOpenPanel
			switch mode {
			case .file, .mediaFiles:
				panel = NSOpenPanel()
				panel.allowsMultipleSelection = mode.allowsMultiple
				panel.canChooseFiles = true
				panel.canChooseDirectories = false
				if let types = mode.allowedContentTypes {
					panel.allowedContentTypes = types
				}
			case .folder:
				panel = NSOpenPanel()
				panel.canChooseFiles = false
				panel.canChooseDirectories = true
				panel.allowsMultipleSelection = false
			}
			
			panel.begin { response in
				isLoading = false
				if response == .OK {
					action(panel.urls)
				}
			}
		}
	}
}

// MARK: - 标准布局模板

/// 所有 Feature View 的标准容器
/// 用法：
/// StandardFeatureContainer {
///     YourContent()
/// }
public struct StandardFeatureContainer<Content: View>: View {
	let content: Content
	
	public init(@ViewBuilder content: () -> Content) {
		self.content = content()
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
		.scrollIndicators(.visible)
		.background(Color(NSColor.controlBackgroundColor))
	}
}

/// 带标题的 Section 容器
public struct FeatureSection<Content: View>: View {
	let title: String
	let systemImage: String?
	let content: Content
	
	public init(
		_ title: String,
		systemImage: String? = nil,
		@ViewBuilder content: () -> Content
	) {
		self.title = title
		self.systemImage = systemImage
		self.content = content()
	}
	
	public var body: some View {
		GroupBox {
			content
		} label: {
			Label(title, systemImage: systemImage ?? "folder")
				.font(.headline)
		}
	}
}

// MARK: - 进度显示组件

public struct ProgressSection: View {
	let progress: Double
	let message: String
	let showPercentage: Bool
	
	public init(
		progress: Double,
		message: String = "",
		showPercentage: Bool = true
	) {
		self.progress = progress
		self.message = message
		self.showPercentage = showPercentage
	}
	
	public var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack {
				if !message.isEmpty {
					Text(message)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer()
				if showPercentage {
					Text("\(Int(progress * 100))%")
						.font(.caption.monospacedDigit())
						.foregroundStyle(.secondary)
				}
			}
			
			ProgressView(value: progress)
				.progressViewStyle(.linear)
		}
		.padding(.vertical, 2)
	}
}

// MARK: - 结果列表组件

/// 通用结果列表：支持展开、缩略图、操作按钮
public struct ResultList<Item: Identifiable, RowContent: View>: View {
	let items: [Item]
	let rowContent: (Item) -> RowContent
	let emptyMessage: String
	let onDelete: ((Item) -> Void)?
	let onShowInFinder: ((Item) -> Void)?
	
	public init(
		items: [Item],
		emptyMessage: String = "暂无结果",
		@ViewBuilder rowContent: @escaping (Item) -> RowContent,
		onDelete: ((Item) -> Void)? = nil,
		onShowInFinder: ((Item) -> Void)? = nil
	) {
		self.items = items
		self.emptyMessage = emptyMessage
		self.rowContent = rowContent
		self.onDelete = onDelete
		self.onShowInFinder = onShowInFinder
	}
	
	public var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			if items.isEmpty {
				Text(emptyMessage)
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .center)
					.padding(.vertical, 20)
			} else {
				LazyVStack(alignment: .leading, spacing: 10) {
					ForEach(items) { item in
						ResultRow(item: item, content: rowContent)
							.contextMenu {
								if let onShowInFinder {
									Button("在 Finder 中显示") { onShowInFinder(item) }
								}
								if let onDelete {
									Divider()
									Button("删除", role: .destructive) { onDelete(item) }
								}
							}
					}
				}
			}
		}
	}
}

/// 单行结果项
private struct ResultRow<Item, Content: View>: View {
	let item: Item
	let content: (Item) -> Content
	
	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			content(item)
		}
		.padding(10)
		.background(.quaternary.opacity(0.6))
		.clipShape(RoundedRectangle(cornerRadius: 8))
	}
}

// MARK: - 横向缩略图滚动条

public struct ThumbnailScrollView<Content: View>: View {
	let content: Content
	let height: CGFloat
	
	public init(height: CGFloat = 120, @ViewBuilder content: () -> Content) {
		self.height = height
		self.content = content()
	}
	
	public var body: some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 8) {
				content
			}
			.padding(.horizontal, 4)
			.padding(.vertical, 4)
		}
		.frame(height: height)
	}
}

/// 单张缩略图卡片
public struct ThumbnailCard: View {
	let image: NSImage?
	let size: CGFloat
	let title: String
	let subtitle: String?
	let onTap: (() -> Void)?
	
	public init(
		image: NSImage?,
		size: CGFloat = 100,
		title: String,
		subtitle: String? = nil,
		onTap: (() -> Void)? = nil
	) {
		self.image = image
		self.size = size
		self.title = title
		self.subtitle = subtitle
		self.onTap = onTap
	}
	
	public var body: some View {
		VStack(spacing: 4) {
			ZStack {
				if let image {
					Image(nsImage: image)
						.resizable()
						.aspectRatio(contentMode: .fill)
						.frame(width: size, height: size)
						.clipped()
				} else {
					RoundedRectangle(cornerRadius: 6)
						.fill(Color.secondary.opacity(0.1))
						.frame(width: size, height: size)
						.overlay(
							Image(systemName: "photo")
								.font(.system(size: size * 0.4))
								.foregroundStyle(.secondary)
						)
				}
			}
			.cornerRadius(6)
			.overlay(
				RoundedRectangle(cornerRadius: 6)
					.stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
			)
			.onTapGesture { onTap?() }
			
			Text(title)
				.font(.caption2)
				.lineLimit(1)
				.truncationMode(.middle)
				.frame(width: size)
			
			if let subtitle {
				Text(subtitle)
					.font(.caption2)
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.frame(width: size)
			}
		}
		.frame(width: size)
	}
}

// MARK: - 确认对话框

public struct ConfirmationButton<Label: View>: View {
	let role: ButtonRole?
	let action: () -> Void
	let label: Label
	
	@State private var showAlert = false
	let alertTitle: String
	let alertMessage: String
	let confirmText: String
	let cancelText: String
	
	public init(
		role: ButtonRole? = nil,
		alertTitle: String,
		alertMessage: String,
		confirmText: String = "确定",
		cancelText: String = "取消",
		action: @escaping () -> Void,
		@ViewBuilder label: () -> Label
	) {
		self.role = role
		self.alertTitle = alertTitle
		self.alertMessage = alertMessage
		self.confirmText = confirmText
		self.cancelText = cancelText
		self.action = action
		self.label = label()
	}
	
	public var body: some View {
		Button(role: role) { showAlert = true } label: { label }
			.alert(alertTitle, isPresented: $showAlert) {
				Button(cancelText, role: .cancel) { }
				Button(confirmText, role: role ?? .destructive) { action() }
			} message: {
				Text(alertMessage)
			}
	}
}

// MARK: - 状态标签

public struct StatusBadge: View {
	public enum Style {
		case success
		case warning
		case error
		case info
		case neutral
		
		var color: Color {
			switch self {
			case .success: return .green
			case .warning: return .orange
			case .error: return .red
			case .info: return .blue
			case .neutral: return .secondary
			}
		}
		
		var backgroundColor: Color {
			color.opacity(0.1)
		}
	}
	
	let text: String
	let style: Style
	
	public init(_ text: String, style: Style = .info) {
		self.text = text
		self.style = style
	}
	
	public var body: some View {
		Text(text)
			.font(.caption2.weight(.medium))
			.padding(.horizontal, 6)
			.padding(.vertical, 2)
			.background(style.backgroundColor)
			.foregroundStyle(style.color)
			.clipShape(Capsule())
	}
}

// MARK: - 空状态视图

public struct EmptyStateView: View {
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
		VStack(spacing: 12) {
			Image(systemName: systemImage)
				.font(.system(size: 48))
				.foregroundStyle(.secondary)
			
			VStack(spacing: 4) {
				Text(title)
					.font(.headline)
				Text(message)
					.font(.caption)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
			}
			
			if let actionTitle, let action {
				Button(actionTitle) { action() }
					.buttonStyle(.borderedProminent)
					.controlSize(.small)
			}
		}
		.padding()
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}

// MARK: - 操作日志视图

public struct OperationLogView: View {
	let logs: [String]
	let maxHeight: CGFloat
	
	public init(logs: [String], maxHeight: CGFloat = 150) {
		self.logs = logs
		self.maxHeight = maxHeight
	}
	
	public var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text("操作日志")
				.font(.headline)
			
			ScrollView {
				Text(logs.reversed().joined(separator: "\n"))
					.font(.system(.caption, design: .monospaced))
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .leading)
			}
			.frame(maxHeight: maxHeight)
			.background(Color(NSColor.controlBackgroundColor))
			.cornerRadius(6)
		}
	}
}

// MARK: - 扩展：快捷方式

public extension View {
	/// 包裹在标准容器中
	func inStandardContainer() -> some View {
		StandardFeatureContainer { self }
	}
	
	/// 作为 FeatureSection 包裹
	func inSection(_ title: String, systemImage: String? = nil) -> some View {
		FeatureSection(title, systemImage: systemImage) { self }
	}
}