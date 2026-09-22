import SwiftUI

/// 可拖拽/可拉伸的裁剪框（归一化 0~1 坐标，与容器实际尺寸无关）
struct CropOverlay: View {
	@Binding var normalizedRect: CGRect

	private let minSize: CGFloat = 0.08
	private let edgeThickness: CGFloat = 10
	private let cornerInset: CGFloat = 12

	@State private var wholeStartRect: CGRect?
	@State private var cornerStartRect: CGRect?
	@State private var activeCorner: CornerMode?

	var body: some View {
		GeometryReader { geo in
			let size = geo.size
			let rect = CGRect(
				x: normalizedRect.origin.x * size.width,
				y: normalizedRect.origin.y * size.height,
				width: normalizedRect.size.width * size.width,
				height: normalizedRect.size.height * size.height
			)

			ZStack(alignment: .topLeading) {
				// 暗色遮罩
				Path { path in
					path.addRect(CGRect(origin: .zero, size: size))
					path.addRect(rect)
				}
				.fill(.black.opacity(0.35), style: FillStyle(eoFill: true))

				// 边框
				Rectangle()
					.path(in: rect)
					.stroke(.yellow, lineWidth: 2)

				// 内部拖动区域（移动整个框）
				Rectangle()
					.fill(.clear)
					.contentShape(Rectangle())
					.frame(width: rect.width, height: rect.height)
					.position(x: rect.midX, y: rect.midY)
					.highPriorityGesture(dragWhole(in: size))

				// 四边命中条（拖动 = 移动整个框，两端内缩避开角点）
				edgeHandle(
					x: rect.midX, y: rect.minY + edgeThickness / 2,
					width: rect.width - 2 * cornerInset, height: edgeThickness,
					in: size
				)
				edgeHandle(
					x: rect.midX, y: rect.maxY - edgeThickness / 2,
					width: rect.width - 2 * cornerInset, height: edgeThickness,
					in: size
				)
				edgeHandle(
					x: rect.minX + edgeThickness / 2, y: rect.midY,
					width: edgeThickness, height: rect.height - 2 * cornerInset,
					in: size
				)
				edgeHandle(
					x: rect.maxX - edgeThickness / 2, y: rect.midY,
					width: edgeThickness, height: rect.height - 2 * cornerInset,
					in: size
				)

				// 四角圆点（最顶层，自由调整大小）
				cornerHandle(at: rect.origin, in: size, mode: .topLeft)
				cornerHandle(at: CGPoint(x: rect.maxX, y: rect.minY), in: size, mode: .topRight)
				cornerHandle(at: CGPoint(x: rect.minX, y: rect.maxY), in: size, mode: .bottomLeft)
				cornerHandle(at: CGPoint(x: rect.maxX, y: rect.maxY), in: size, mode: .bottomRight)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
	}

	private enum CornerMode { case topLeft, topRight, bottomLeft, bottomRight }

	private func cornerHandle(at point: CGPoint, in containerSize: CGSize, mode: CornerMode) -> some View {
		Circle()
			.fill(.yellow)
			.frame(width: 14, height: 14)
			.highPriorityGesture(dragCorner(in: containerSize, mode: mode))
			.position(point)
	}

	private func edgeHandle(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, in containerSize: CGSize) -> some View {
		Rectangle()
			.fill(.clear)
			.contentShape(Rectangle())
			.frame(width: max(width, 0), height: max(height, 0))
			.position(x: x, y: y)
			.highPriorityGesture(dragWhole(in: containerSize))
	}

	// MARK: 手势

	private func dragWhole(in containerSize: CGSize) -> some Gesture {
		DragGesture(coordinateSpace: .local)
			.onChanged { value in
				if wholeStartRect == nil { wholeStartRect = normalizedRect }
				guard let start = wholeStartRect else { return }

				var r = start
				let dx = value.translation.width / max(containerSize.width, 1)
				let dy = value.translation.height / max(containerSize.height, 1)
				r.origin.x += dx
				r.origin.y += dy
				// 移动模式：只钳制位置，尺寸保持不变
				normalizedRect = clampMove(r)
			}
			.onEnded { _ in
				wholeStartRect = nil
			}
	}

	private func dragCorner(in containerSize: CGSize, mode: CornerMode) -> some Gesture {
		DragGesture(coordinateSpace: .local)
			.onChanged { value in
				if activeCorner != mode || cornerStartRect == nil {
					activeCorner = mode
					cornerStartRect = normalizedRect
				}
				guard let start = cornerStartRect else { return }

				var r = start
				let dx = value.translation.width / max(containerSize.width, 1)
				let dy = value.translation.height / max(containerSize.height, 1)

				switch mode {
				case .topLeft:
					r.origin.x += dx
					r.origin.y += dy
					r.size.width -= dx
					r.size.height -= dy
				case .topRight:
					r.origin.y += dy
					r.size.width += dx
					r.size.height -= dy
				case .bottomLeft:
					r.origin.x += dx
					r.size.width -= dx
					r.size.height += dy
				case .bottomRight:
					r.size.width += dx
					r.size.height += dy
				}

				// 缩放模式：钳制尺寸与位置，最终尺寸在 [minSize, 1-origin] 内
				normalizedRect = clampResize(r)
			}
			.onEnded { _ in
				cornerStartRect = nil
				activeCorner = nil
			}
	}

	// MARK: 钳制

	/// 移动模式：裁剪框不能超出图片边界（归一化 0~1 空间）。
	/// 只调整 origin，绝不修改 size。触边后框保持不动（origin 被钳在合法范围内）。
	private func clampMove(_ rect: CGRect) -> CGRect {
		var r = rect
		r.origin.x = min(max(r.origin.x, 0), 1 - r.size.width)
		r.origin.y = min(max(r.origin.y, 0), 1 - r.size.height)
		return r
	}

	/// 缩放模式：处理 origin 越界与尺寸越界。
	/// 先吸收负 origin 到 size，再统一将 size 钳入 [minSize, 1-origin]。
	/// 对边保持不动，只调整被拖动的角点侧。
	private func clampResize(_ rect: CGRect) -> CGRect {
		var r = rect

		// 处理 origin.x < 0：把超出量从宽度中扣除，origin 归零
		if r.origin.x < 0 {
			r.size.width = max(r.size.width + r.origin.x, minSize)
			r.origin.x = 0
		}
		if r.origin.y < 0 {
			r.size.height = max(r.size.height + r.origin.y, minSize)
			r.origin.y = 0
		}

		// 尺寸上限：不超过 1 - origin（对边到右/下边界）
		r.size.width = min(max(r.size.width, minSize), 1 - r.origin.x)
		r.size.height = min(max(r.size.height, minSize), 1 - r.origin.y)

		return r
	}
}
