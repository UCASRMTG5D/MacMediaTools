import SwiftUI

/// 一个简单的可拖拽/可拉伸的裁剪框（坐标使用 0~1 的归一化值）
struct CropOverlay: View {
	@Binding var normalizedRect: CGRect

	private let minSize: CGFloat = 0.08
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

				// 拖动整个框
				Rectangle()
					.fill(.clear)
					.contentShape(Rectangle())
					.frame(width: rect.width, height: rect.height)
					.position(x: rect.midX, y: rect.midY)
					.gesture(dragWhole(in: size))

				// 角点
				cornerHandle(at: rect.origin, in: size, mode: .topLeft)
				cornerHandle(at: CGPoint(x: rect.maxX, y: rect.minY), in: size, mode: .topRight)
				cornerHandle(at: CGPoint(x: rect.minX, y: rect.maxY), in: size, mode: .bottomLeft)
				cornerHandle(at: CGPoint(x: rect.maxX, y: rect.maxY), in: size, mode: .bottomRight)
			}
		}
	}

	private enum CornerMode { case topLeft, topRight, bottomLeft, bottomRight }

	private func cornerHandle(at point: CGPoint, in containerSize: CGSize, mode: CornerMode) -> some View {
		Circle()
			.fill(.yellow)
			.frame(width: 10, height: 10)
			.position(point)
			.gesture(dragCorner(in: containerSize, mode: mode))
	}

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
				normalizedRect = clamp(r)
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

				normalizedRect = clamp(r)
			}
			.onEnded { _ in
				cornerStartRect = nil
				activeCorner = nil
			}
	}

	private func clamp(_ rect: CGRect) -> CGRect {
		var r = rect
		r.size.width = max(r.size.width, minSize)
		r.size.height = max(r.size.height, minSize)

		// 防止 origin 超出导致 width/height 变负
		if r.origin.x < 0 { r.size.width += r.origin.x; r.origin.x = 0 }
		if r.origin.y < 0 { r.size.height += r.origin.y; r.origin.y = 0 }

		r.size.width = min(r.size.width, 1 - r.origin.x)
		r.size.height = min(r.size.height, 1 - r.origin.y)
		return r
	}
}
