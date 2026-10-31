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
		summary: "图片 / 视频 / GIF 通用的宽高处理工具：可选裁剪 → 可选尺寸调整 → 导出。",
		details: [
			"两阶段可跳过：可只裁剪、只调整尺寸、或二者都做",
			"裁剪：拖拽裁剪框移动位置 / 调整大小，支持 1:1 / 4:3 / 3:2 / 16:9 等预设，数字输入与裁剪框双向同步，正确处理旋转元数据",
			"尺寸调整：输入目标宽高，支持宽高比预设与恢复原始尺寸，支持拉伸 / Aspect Fit（保持比例加黑边）",
			"实时拉伸预览：开启尺寸调整后，可预览缩放效果并对比新旧分辨率",
			"输出目录通过安全书签记忆；可选择删除源文件（二次确认）",
		]
	),
	HelpFeature(
		number: "2",
		name: "视频片段整合",
		icon: "rectangle.stack.fill.badge.plus",
		summary: "批量选择、拖拽排序，拼接为单一 MP4，支持不同分辨率自动居中 / 裁剪。",
		details: [
			"列表中显示每个视频的文件名和分辨率（宽×高）",
			"自动取所有视频宽高的最大值作为默认输出分辨率",
			"不同分辨率的视频自动适配：小于输出尺寸的填充黑边居中，大于的裁剪边缘保留中心",
			"支持手动指定输出宽高与文件名",
		]
	),
	HelpFeature(
		number: "3",
		name: "音视频处理",
		icon: "waveform",
		summary: "视频轨道 + 音频轨道导入 → 变速 / 偏移 / 对齐 → 合并导出。",
		details: [
			"视频、音频各自支持 0.5x–2.0x 变速（步长 0.1）",
			"支持起始对齐、结束对齐、同步对齐三种轨道对齐方式",
			"支持单独的视频分离 / 音频分离功能",
			"撤销 / 重做（最多 10 步）",
			"合并输出 .mov；分离音频为 .m4a、分离视频为 .mov",
		]
	),
	HelpFeature(
		number: "4",
		name: "批量截图",
		icon: "camera.viewfinder",
		summary: "按时间间隔截取视频帧，支持清晰度评分、±1 秒替代帧搜索与内容去重。",
		details: [
			"时间间隔 0.001–60 秒，滑块与数字输入双向同步",
			"质量检查：BT.601 Y 通道 + Sobel 3×3 计算清晰度；始终在 ±1 秒内按 0.1 秒搜索更清晰帧并替换",
			"质量筛选用百分位：界面百分比表示保留质量最高的比例，不是绝对阈值",
			"内容去重：16×16 灰度指纹 + 时序滑动窗口，相似帧只保留质量更高的一张，阈值越低越严格",
			"四种结果：全部 / 质量筛选 / 去重 / 筛选+去重，保存时只保存当前模式",
			"支持 PNG / JPEG 输出；预计超过 500 帧时先确认；可暂停 / 取消",
			"快捷键：空格播放 / 暂停，← / → 前后 1 秒",
		]
	),
	HelpFeature(
		number: "5",
		name: "停顿去除",
		icon: "speaker.slash.fill",
		summary: "按音频音量检测停顿，删除静音段（每段保留前 0.5 秒），导出紧凑版视频。",
		details: [
			"音量阈值 -55…-25 dBFS 可调；低于阈值且持续 ≥ 0.5 秒判定为停顿",
			"每个停顿段只保留前 0.5 秒，其余删除",
			"分析后显示原始时长、预计新时长、可节省比例与停顿段数量",
			"导出同名后缀 _去停顿.mp4，同名文件自动追加 _1、_2…",
			"无音频轨道的视频无法检测停顿，会给出提示",
		]
	),
	HelpFeature(
		number: "6",
		name: "画幅拼接",
		icon: "square.grid.3x3.fill",
		summary: "将多个图片、视频、GIF 拼接到同一画布，支持拖动定位、缩放、裁切、混音。",
		details: [
			"文件选择器可一次导入多个图片 / 视频 / GIF，导入后在画布中自由拖动定位",
			"编辑模式分移动 / 缩放 / 裁切；编辑时画布不套滚动视图，避免手势冲突",
			"8 个锚点缩放手柄：四角等比缩放 + 四边单轴拉伸",
			"每个元素可独立裁切显示区域；视频 / GIF 可单独调节音量",
			"画布尺寸可选 1920×1080 / 1280×720 等预设或自定义",
			"导出 MP4（H.264 + AAC，30fps），时长取最长元素 + 1 秒",
		]
	),
	HelpFeature(
		number: "7",
		name: "重复照片检测",
		icon: "photo.on.rectangle.angled",
		summary: "快速模式 SHA256 精确匹配；精细模式 dHash + pHash 相似聚类。",
		details: [
			"快速检测：全文件 SHA256 精确匹配，只报告内容完全一致的照片",
			"精细检测：64 位 dHash + 64 位 pHash，中心裁切 90% 降低水印干扰",
			"两个哈希距离都满足阈值才判定相似；严格度滑块映射为两套 Hamming 阈值",
			"支持采样比例 10%–100%、自定义缓存目录（默认 hash_cache/picture）",
			"结果可并排对比、在 Finder 显示、移到废纸篓（二次确认）或本次忽略",
		]
	),
	HelpFeature(
		number: "8",
		name: "重复视频检测",
		icon: "video.badge.checkmark",
		summary: "快速模式按时长 / 大小 / 分辨率分组；精细模式用分段 dHash 指纹聚类。",
		details: [
			"快速检测：时长（毫秒）+ 文件大小 + 分辨率三项一致才归为同组，GIF 也会扫描",
			"精细检测：每部视频均匀抽 10 个时间点，中心裁切 70% 后计算 64 位 dHash",
			"逐段 Hamming 距离 ≤ 10 视为匹配，匹配比例 ≥ 50% 判定相似，再做连通分量聚类",
			"支持采样比例 10%–100%、自定义缓存目录（默认 hash_cache/video）",
			"并排对比面板：同步播放 / 进度 / 音量，按平均相似度排序",
		]
	),
	HelpFeature(
		number: "9",
		name: "文件复制工具",
		icon: "doc.on.doc",
		summary: "智能媒体文件复制，目标同名时按内容判重，不同内容自动编号。",
		details: [
			"目标没有同名文件时直接复制",
			"图片：SHA256 相同则跳过并报告；不同则自动改名 原名_1.ext",
			"视频：时长 + 分辨率都相同则跳过；不同则自动改名",
			"界面显示选择列表、复制进度、当前文件与重复报告",
		]
	),
	HelpFeature(
		number: "10",
		name: "文件搜索",
		icon: "magnifyingglass",
		summary: "按文件名关键词搜索目标文件夹中的图片 / 视频，分组以缩略图网格展示。",
		details: [
			"递归扫描目标文件夹，文件名包含关键词即匹配（不区分大小写）；关键词为空时列出全部媒体",
			"结果按图片 / 视频两大类分组，组内按文件创建时间倒序排列",
			"缩略图网格展示，缩略图尺寸 60–200 可调",
			"点击缩略图可用系统默认应用打开，支持在 Finder 中显示",
		]
	),
	HelpFeature(
		number: "11",
		name: "媒体修复",
		icon: "wrench.and.screwdriver",
		summary: "检测并修复图片扩展名不符、视频不兼容 QuickTime 的问题，修复前逐项确认。",
		details: [
			"检测阶段只读文件、不修改任何内容，结果按图片 / 视频两大类分组列出",
			"图片扩展名不符：实际格式（如 WebP）与扩展名（如 .jpg）不一致导致 Preview 显示「已锁定」，修复为零画质损失重命名",
			"视频不兼容 QuickTime：扩展名为 avi / mkv / wmv / flv / webm / 3gp 等时，无损 remux 到 MP4（不转码，拷贝音视频流）",
			"支持选择「全部 / 仅图片 / 仅视频」检测范围",
			"勾选需要修复的项目后点击「开始修复」才会写盘，可全选 / 取消",
			"支持选择文件或递归扫描整个文件夹",
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
