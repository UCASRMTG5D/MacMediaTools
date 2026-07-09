import SwiftUI
import AppKit
import AVFoundation
import AVKit
import UniformTypeIdentifiers

// MARK: - CanvasElementView

/// 渲染单个画布元素（图片/视频/GIF），应用位置、缩放、裁剪等变换
/// 配合 SpatialCanvasView 的画布 ZStack 使用
struct CanvasElementView: View {
	let element: CanvasElement
	let isSelected: Bool
	let canvasScale: CGFloat

	var body: some View {
		let scaledSize = CGSize(
			width: element.effectiveSize.width * canvasScale,
			height: element.effectiveSize.height * canvasScale
		)
		return ZStack {
			// 媒体内容层
			Group {
				switch element.mediaType {
				case .image:
					imageContent
				case .video:
					videoContent
				case .gif:
					gifContent
				}
			}
			.clipped()

			// 选中边框（蓝色 2px）
			if isSelected {
				Rectangle()
					.stroke(Color.blue, lineWidth: 2)
					.allowsHitTesting(false)
			}

			// 裁剪遮罩层（半透明黑色，even-odd fill 挖空裁剪区域）
			if let cropRect = element.cropRect {
				cropOverlay(cropRect: cropRect)
					.allowsHitTesting(false)
			}
		}
		.frame(width: scaledSize.width, height: scaledSize.height)
		.position(
			x: element.position.x * canvasScale + scaledSize.width / 2,
			y: element.position.y * canvasScale + scaledSize.height / 2
		)
		.allowsHitTesting(true)
	}

	// MARK: - 图片渲染

	/// 加载 NSImage 并用 SwiftUI Image 显示，resizable + aspectFill 填满容器
	@ViewBuilder
	private var imageContent: some View {
		if let nsImage = NSImage(contentsOf: element.sourceURL) {
			Image(nsImage: nsImage)
				.resizable()
				.aspectRatio(contentMode: .fill)
				// BUG_KNOWLEDGE.md: Image.aspectRatio 在 ZStack 中需显式填满容器
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
	}

	// MARK: - 视频渲染

	/// 使用 AVQueuePlayer + AVPlayerLooper 实现无缝循环播放
	private var videoContent: some View {
		LoopingVideoPlayerView(url: element.sourceURL, volume: element.volume)
	}

	// MARK: - GIF 渲染

	/// 使用 NSImageView 渲染动画 GIF（AppKit 原生支持多帧 GIF 动画）
	private var gifContent: some View {
		GIFPlayerView(url: element.sourceURL)
	}

	// MARK: - 裁剪遮罩

	/// 基于归一化 cropRect 生成半透明遮罩
	/// 使用 Path even-odd fill：先画整体区域，再画裁剪区域，实现挖空效果
	private func cropOverlay(cropRect: CGRect) -> some View {
		GeometryReader { geo in
			let bounds = CGRect(origin: .zero, size: geo.size)
			let rect = CGRect(
				x: cropRect.origin.x * geo.size.width,
				y: cropRect.origin.y * geo.size.height,
				width: cropRect.size.width * geo.size.width,
				height: cropRect.size.height * geo.size.height
			)
			Path { path in
				path.addRect(bounds)
				path.addRect(rect)
			}
			.fill(Color.black.opacity(0.4), style: FillStyle(eoFill: true))
		}
	}
}

// MARK: - LoopingVideoPlayerView

/// AVQueuePlayer + AVPlayerLooper 封装，用于 NSViewRepresentable 桥接
private struct LoopingVideoPlayerView: NSViewRepresentable {
	let url: URL
	let volume: Double

	func makeCoordinator() -> Coordinator {
		Coordinator()
	}

	func makeNSView(context: Context) -> AVPlayerView {
		let playerItem = AVPlayerItem(url: url)
		let player = AVQueuePlayer(playerItem: playerItem)
		player.volume = Float(volume)
		player.isMuted = volume <= 0

		// 创建循环播放器，coordinator 持有引用防止释放
		let looper = AVPlayerLooper(player: player, templateItem: playerItem)
		context.coordinator.looper = looper

		player.play()

		let playerView = AVPlayerView()
		playerView.player = player
		playerView.controlsStyle = .none
		return playerView
	}

	func updateNSView(_ nsView: AVPlayerView, context: Context) {
		nsView.player?.volume = Float(volume)
		nsView.player?.isMuted = volume <= 0
	}

	static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
		nsView.player?.pause()
	}

	final class Coordinator {
		var looper: AVPlayerLooper?
	}
}

// MARK: - GIFPlayerView

/// NSImageView 封装，用于显示动画 GIF
private struct GIFPlayerView: NSViewRepresentable {
	let url: URL

	func makeNSView(context: Context) -> NSImageView {
		let imageView = NSImageView()
		imageView.image = NSImage(contentsOf: url)
		imageView.animates = true
		imageView.imageScaling = .scaleProportionallyUpOrDown
		return imageView
	}

	func updateNSView(_ nsView: NSImageView, context: Context) {
		// NSImage 已绑定到 NSImageView，更新时无需额外操作
	}
}
