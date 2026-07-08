import SwiftUI

// MARK: - CanvasResizeHandles

/// 8 个锚点的缩放手柄覆盖层，用于 CanvasElement 的等比缩放与非等比拉伸操作。
///
/// 使用方式：将此视图叠加在画布 ZStack 中，画布需定义 `.coordinateSpace(.named("canvas"))`。
///
/// - 角点手柄 → 等比缩放（修改 element.scale）
/// - 水平边手柄 → 横向非等比拉伸（修改 element.nonUniformScale.width）
/// - 垂直边手柄 → 纵向非等比拉伸（修改 element.nonUniformScale.height）
struct CanvasResizeHandles: View {
	@Binding var element: CanvasElement

	// MARK: - DragStartState

	/// 拖拽开始时元素状态的快照，用于计算拖拽增量
	struct DragStartState: Equatable {
		let size: CGSize				// element.effectiveSize 快照
		let position: CGPoint			// element.position 快照
		let nonUniformScale: CGSize?	// element.nonUniformScale 快照
	}

	@GestureState private var dragStart: DragStartState? = nil

	private let handleSize: CGFloat = 8
	private let minElementSize: CGFloat = 20

	// MARK: - Body

	var body: some View {
		let frame = element.canvasFrame

		ZStack {
			ForEach(HandlePosition.allCases, id: \.self) { handle in
				handleView
					.position(position(for: handle, in: frame))
					.simultaneousGesture(resizeGesture(for: handle))
			}
		}
	}

	// MARK: - Handle Position

	/// 计算各手柄在手柄父视图（画布 ZStack）中的坐标
	private func position(for handle: HandlePosition, in frame: CGRect) -> CGPoint {
		switch handle {
		case .topLeft:		return frame.origin
		case .top:			return CGPoint(x: frame.midX, y: frame.minY)
		case .topRight:		return CGPoint(x: frame.maxX, y: frame.minY)
		case .centerLeft:	return CGPoint(x: frame.minX, y: frame.midY)
		case .centerRight:	return CGPoint(x: frame.maxX, y: frame.midY)
		case .bottomLeft:	return CGPoint(x: frame.minX, y: frame.maxY)
		case .bottom:		return CGPoint(x: frame.midX, y: frame.maxY)
		case .bottomRight:	return CGPoint(x: frame.maxX, y: frame.maxY)
		}
	}

	// MARK: - Handle View

	/// 单个手柄的外观：8x8 白色圆角矩形 + 灰色边框 + 投影
	private var handleView: some View {
		RoundedRectangle(cornerRadius: 1.5)
			.fill(Color.white)
			.frame(width: handleSize, height: handleSize)
			.overlay(
				RoundedRectangle(cornerRadius: 1.5)
					.stroke(Color.gray.opacity(0.6), lineWidth: 1)
			)
			.shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 0.5)
	}

	// MARK: - Resize Gesture

	/// 为指定手柄创建拖拽手势
	/// - 使用 `.coordinateSpace(.named("canvas"))` 保证坐标一致性
	/// - 使用 `@GestureState` 快照拖拽起始状态，手势结束后自动清理
	private func resizeGesture(for handle: HandlePosition) -> some Gesture {
		DragGesture(coordinateSpace: .named("canvas"))
			.updating($dragStart) { value, state, _ in
				if state == nil {
					state = DragStartState(
						size: element.effectiveSize,
						position: element.position,
						nonUniformScale: element.nonUniformScale
					)
				}
			}
			.onChanged { value in
				guard let start = dragStart else { return }
				performResize(handle: handle, start: start, translation: value.translation)
			}
	}

	// MARK: - Resize Logic

	/// 根据手柄类型和拖拽增量执行缩放/拉伸
	/// - 角点（Corner）：等比缩放，统一修改 scale，同时调整 position 使对角锚点固定
	/// - 水平边（Horizontal Edge）：横向非等比拉伸，修改 nonUniformScale.width
	/// - 垂直边（Vertical Edge）：纵向非等比拉伸，修改 nonUniformScale.height
	private func performResize(
		handle: HandlePosition,
		start: DragStartState,
		translation: CGSize
	) {
		let ds = element.displaySize
		let minS = minElementSize

		// ---------------------------------------------------------------
		// 角点 — 等比缩放
		// ---------------------------------------------------------------
		if handle.isCorner {
			// 根据角点位置计算拖拽后的新宽度
			let newWidth: CGFloat = {
				switch handle {
				case .topLeft, .bottomLeft:
					return max(start.size.width - translation.width, minS)
				case .topRight, .bottomRight:
					return max(start.size.width + translation.width, minS)
				default:
					return start.size.width
				}
			}()

			// 等比缩放：新 scale = 新宽度 / displaySize.width
			let newScale = newWidth / ds.width

			// 用高度反向验证最小值
			if ds.height * newScale < minS {
				element.scale = minS / ds.height
			} else {
				element.scale = newScale
			}

			// 非等比拉伸模式下拖拽角点 → 清除非等比，转为纯等比
			element.nonUniformScale = nil

			// 根据角点类型调整 position，使对角锚点保持不动
			let newSize = element.effectiveSize
			switch handle {
			case .topLeft:
				element.position.x = start.position.x + (start.size.width - newSize.width)
				element.position.y = start.position.y + (start.size.height - newSize.height)
			case .topRight:
				element.position.y = start.position.y + (start.size.height - newSize.height)
			case .bottomLeft:
				element.position.x = start.position.x + (start.size.width - newSize.width)
			case .bottomRight:
				break	// 左上角为锚点，position 无需变化
			default:
				break
			}
			return
		}

		// ---------------------------------------------------------------
		// 水平边 — 横向非等比拉伸（修改 nonUniformScale.width）
		// ---------------------------------------------------------------
		if handle.isHorizontalEdge {
			let newWidth: CGFloat = {
				switch handle {
				case .centerLeft:
					return max(start.size.width - translation.width, minS)
				case .centerRight:
					return max(start.size.width + translation.width, minS)
				default:
					return start.size.width
				}
			}()

			// 如果 nonUniformScale 为 nil，先用当前 scale 初始化
			var nus = start.nonUniformScale ?? CGSize(width: element.scale, height: element.scale)
			nus.width = newWidth / ds.width
			element.nonUniformScale = nus

			// 左侧手柄拖拽时，右侧边缘为锚点 → 需左移 position.x
			if handle == .centerLeft {
				element.position.x = start.position.x + (start.size.width - newWidth)
			}
			return
		}

		// ---------------------------------------------------------------
		// 垂直边 — 纵向非等比拉伸（修改 nonUniformScale.height）
		// ---------------------------------------------------------------
		if handle.isVerticalEdge {
			let newHeight: CGFloat = {
				switch handle {
				case .top:
					return max(start.size.height - translation.height, minS)
				case .bottom:
					return max(start.size.height + translation.height, minS)
				default:
					return start.size.height
				}
			}()

			var nus = start.nonUniformScale ?? CGSize(width: element.scale, height: element.scale)
			nus.height = newHeight / ds.height
			element.nonUniformScale = nus

			// 上方手柄拖拽时，下边缘为锚点 → 需上移 position.y
			if handle == .top {
				element.position.y = start.position.y + (start.size.height - newHeight)
			}
			return
		}
	}
}
