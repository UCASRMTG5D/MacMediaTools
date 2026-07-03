import SwiftUI

// MARK: - Help Feature Model

private struct HelpFeature: Identifiable {
	let id = UUID()
	let number: String
	let name: String
	let icon: String
	let summary: String
	let details: [String]
}

private let helpFeatures: [HelpFeature] = [
	HelpFeature(
		number: "1",
		name: "宽高调整",
		icon: "crop",
		summary: "图片 / 视频通用的宽高处理工具：可选裁剪 → 可选尺寸调整 → 导出。",
		details: [
			"两阶段可跳过：可只裁剪、只调整尺寸、或二者都做",
			"裁剪：拖拽黄色裁剪框 + 数字输入宽高（双向同步），归一化坐标，正确处理旋转元数据",
			"尺寸调整：输入目标宽高，支持拉伸 / Aspect Fit（保持比例加黑边）",
			"实时拉伸预览：开启尺寸调整后，可预览缩放后的画面效果，对比新旧分辨率",
			"支持图片：PNG / JPEG / TIFF 等常见格式，与视频共用同一界面",
		]
	),
	HelpFeature(
		number: "2",
		name: "视频片段整合",
		icon: "rectangle.stack.fill.badge.plus",
		summary: "批量选择、拖拽排序，拼接为单一视频，支持不同分辨率自动居中 / 裁剪。",
		details: [
			"列表中显示每个视频的文件名和分辨率（宽×高）",
			"自动取所有视频宽高的最大值作为默认输出分辨率",
			"不同分辨率的视频自动适配：小于输出尺寸的填充黑边居中，大于的裁剪边缘保留中心",
			"支持手动指定输出宽高",
		]
	),
	HelpFeature(
		number: "3",
		name: "音视频处理",
		icon: "waveform",
		summary: "视频轨道 + 音频轨道导入 → 速度调整 → 时间偏移 → 合并导出。",
		details: [
			"支持起始对齐、结束对齐、同步对齐三种轨道对齐方式",
			"单独的视频分离 / 音频分离功能",
			"撤销 / 重做（最多 10 步）",
			"基于 AVMutableComposition + AVAssetExportSession",
		]
	),
	HelpFeature(
		number: "4",
		name: "批量截图",
		icon: "camera.viewfinder",
		summary: "按时间间隔截取视频帧，支持智能质量筛选与替代帧搜索、内容去重。",
		details: [
			"智能质量检查：逐帧计算清晰度评分（基于梯度分析），自动在 ±1s 范围内搜索最佳替代帧",
			"内容去重：基于 16×16 灰度感知哈希比对截图内容，相似截图只保留质量最高的一张，阈值可调（默认 15%）",
			"时间间隔支持滑块拖拽与直接输入数字两种方式，实时同步",
			"支持 PNG / JPEG 输出格式",
			"实时进度与预计剩余时间",
			"键盘快捷键（空格播放 / 暂停，左右箭头逐帧）",
			"支持导出为 ZIP 打包",
			"持久化任务状态，支持恢复",
		]
	),
	HelpFeature(
		number: "5",
		name: "重复照片检测",
		icon: "photo.on.rectangle.angled",
		summary: "递归扫描文件夹，SHA256 内容哈希精确匹配，分组输出重复照片。",
		details: [
			"分块读取（1MB/块），避免大文件加载到内存",
			"支持常见图片格式（jpg、png、heic、webp 等 10 种）",
		]
	),
	HelpFeature(
		number: "6",
		name: "重复视频检测",
		icon: "video.badge.checkmark",
		summary: "按时长 / 文件大小 / 分辨率分组匹配重复视频。",
		details: [
			"使用 AVFoundation 读取视频元数据",
			"精度：时长毫秒级、大小字节级",
		]
	),
	HelpFeature(
		number: "7",
		name: "重复媒体综合检测",
		icon: "rectangle.3.group.bubble.left",
		summary: "统一检测照片（SHA256）和视频（特征匹配）的重复媒体。",
		details: [
			"按类型筛选（全部 / 仅照片 / 仅视频）",
			"缩略图预览（系统图标）",
			"匹配原因描述",
			"分组管理，支持删除操作",
		]
	),
	HelpFeature(
		number: "8",
		name: "文件复制工具",
		icon: "doc.on.doc",
		summary: "智能媒体文件复制，自动检测目标路径重复并生成带编号的文件名。",
		details: [
			"图片通过 SHA256 比对判定重复",
			"视频通过时长 + 分辨率比对判定重复",
			"重复文件自动生成带编号的文件名",
		]
	),
]

// MARK: - Environment / Build Info

private struct AppInfo {
	let version: String
	let build: String
	let osVersion: String
	let isNative: Bool

	static let current = AppInfo(
		version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—",
		build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—",
		osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
		isNative: {
			if let arch = ProcessInfo.processInfo.environment["NATIVE_ARCH"] {
				return arch == "arm64"
			}
			var sysinfo = utsname()
			uname(&sysinfo)
			let machine = withUnsafePointer(to: &sysinfo.machine) {
				String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
			}
			return machine == "arm64"
		}()
	)
}

// MARK: - Help Panel View

struct HelpPanelView: View {
	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 0) {
				headerSection
					.padding(.bottom, 28)

				overviewSection
					.padding(.bottom, 32)

				Divider()
					.padding(.bottom, 28)

				featuresSection
					.padding(.bottom, 28)

				Divider()
					.padding(.bottom, 24)

				requirementSection
					.padding(.bottom, 24)

				Divider()
					.padding(.bottom, 24)

				techStackSection
					.padding(.bottom, 24)

				Divider()
					.padding(.bottom, 24)

				privacySection
					.padding(.bottom, 24)

				footerSection
			}
			.padding(32)
		}
		.frame(minWidth: 560, idealWidth: 640, maxWidth: .infinity,
			   minHeight: 400, idealHeight: 640, maxHeight: .infinity)
		.background(Color(NSColor.windowBackgroundColor))
	}

	// MARK: - Sections

	private var headerSection: some View {
		HStack(spacing: 16) {
			Image(systemName: "wrench.and.screwdriver.fill")
				.font(.system(size: 44))
				.foregroundStyle(.blue)
				.symbolRenderingMode(.hierarchical)

			VStack(alignment: .leading, spacing: 4) {
				Text("MacMediaTools")
					.font(.largeTitle)
					.bold()
				Text("纯本地 macOS SwiftUI 多媒体工具箱")
					.font(.subheadline)
					.foregroundStyle(.secondary)
				Text("视频处理 · 重复媒体检测 · 文件管理")
					.font(.caption)
					.foregroundStyle(.tertiary)
			}
		}
	}

	private var overviewSection: some View {
		VStack(alignment: .leading, spacing: 12) {
			sectionTitle("概述")

			Text("MacMediaTools 是一个面向日常视频、音频和图片整理工作的 macOS 桌面工具集。")
				.font(.body)
				.lineSpacing(4)

			Text("所有处理完全在本地完成，无需联网，不上传任何文件。基于系统框架 AVFoundation / AVKit / CryptoKit，无外部依赖。")
				.font(.body)
				.lineSpacing(4)

			VStack(alignment: .leading, spacing: 6) {
				Label("macOS 13.0+", systemImage: "macbook")
				Label("Apple Silicon 优先，Intel Mac 亦可编译运行", systemImage: "cpu")
				Label("纯 SwiftUI + NavigationSplitView 布局", systemImage: "swift")
			}
			.font(.subheadline)
			.foregroundStyle(.secondary)
			.padding(.top, 4)
		}
	}

	private var featuresSection: some View {
		VStack(alignment: .leading, spacing: 20) {
			sectionTitle("功能介绍")

			Text("从左侧导航栏选择一个功能即可进入对应的工具界面。")
				.font(.subheadline)
				.foregroundStyle(.secondary)

			ForEach(helpFeatures) { feature in
				featureCard(feature)
			}
		}
	}

	private func featureCard(_ feature: HelpFeature) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 10) {
				Text(feature.number)
					.font(.caption)
					.fontWeight(.semibold)
					.foregroundStyle(.white)
					.frame(width: 22, height: 22)
					.background(Circle().fill(.blue))

				Image(systemName: feature.icon)
					.font(.body)
					.foregroundStyle(.blue)
					.frame(width: 20)

				Text(feature.name)
					.font(.headline)
			}

			Text(feature.summary)
				.font(.subheadline)
				.foregroundStyle(.secondary)

			VStack(alignment: .leading, spacing: 5) {
				ForEach(feature.details, id: \.self) { detail in
					Label(detail, systemImage: "circle.fill")
						.font(.caption)
						.foregroundStyle(.secondary)
						.labelStyle(.titleAndIcon)
				}
			}
			.padding(.leading, 52)
		}
		.padding(14)
		.background(
			RoundedRectangle(cornerRadius: 10)
				.fill(Color(NSColor.controlBackgroundColor))
		)
	}

	private var requirementSection: some View {
		VStack(alignment: .leading, spacing: 10) {
			sectionTitle("环境要求")

			Group {
				LabeledContent("操作系统", value: "macOS 13.0+")
				LabeledContent("开发工具", value: "Xcode 15.0+（推荐最新版本）")
				LabeledContent("外部依赖", value: "无 — 基于系统框架 AVFoundation / AVKit / CryptoKit")
			}
			.font(.subheadline)
		}
	}

	private var techStackSection: some View {
		VStack(alignment: .leading, spacing: 10) {
			sectionTitle("技术栈")

			Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
				GridRow {
					techBadge("SwiftUI + NavigationSplitView", "swift")
					techBadge("AVFoundation / AVKit", "video.fill")
				}
				GridRow {
					techBadge("CryptoKit (SHA256)", "lock.fill")
					techBadge("Swift Async/Await, Actor", "rays")
				}
			}
		}
	}

	private func techBadge(_ label: String, _ icon: String) -> some View {
		HStack(spacing: 6) {
			Image(systemName: icon)
				.font(.caption)
				.foregroundStyle(.blue)
			Text(label)
				.font(.caption)
		}
		.padding(.horizontal, 10)
		.padding(.vertical, 5)
		.background(
			Capsule()
				.fill(Color(NSColor.controlBackgroundColor))
		)
	}

	private var privacySection: some View {
		VStack(alignment: .leading, spacing: 10) {
			sectionTitle("隐私声明")

			VStack(alignment: .leading, spacing: 6) {
				Label("所有处理完全在本地完成", systemImage: "checkmark.shield.fill")
					.foregroundStyle(.green)
				Label("不上传文件、不联网", systemImage: "wifi.slash")
				Label("不收集用户数据", systemImage: "hand.raised.fill")
			}
			.font(.subheadline)
		}
	}

	private var footerSection: some View {
		VStack(spacing: 4) {
			Divider()
				.padding(.bottom, 12)

			HStack {
				Spacer()
				Text("MacMediaTools")
					.font(.caption2)
					.foregroundStyle(.tertiary)
				Text("·")
					.font(.caption2)
					.foregroundStyle(.tertiary)
				Text("纯本地 · 无联网 · 保护隐私")
					.font(.caption2)
					.foregroundStyle(.tertiary)
				Spacer()
			}
		}
	}

	// MARK: - Helpers

	private func sectionTitle(_ text: String) -> some View {
		Text(text)
			.font(.title2)
			.bold()
			.foregroundStyle(.primary)
	}
}

// MARK: - Preview

#Preview {
	HelpPanelView()
}
