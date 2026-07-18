import AppKit
import Foundation

// MARK: - WorkManager

/// Tracks which feature is currently performing work and handles
/// conflict resolution (interrupt / queue / cancel) when the user
/// tries to start a second operation.
@MainActor
final class WorkManager: ObservableObject {

	static let shared = WorkManager()

	@Published private(set) var currentWork: ToolFeature?
	@Published private(set) var pendingWork: ToolFeature?

	private init() {}

	/// Ask the manager whether work for `feature` may begin.
	/// - Returns: `true` if it is safe to start immediately.
	///            `false` if the user cancelled or the request was queued.
	///
	/// 旧版接口（无写入目录信息）：保持原有"强制串行 + 打断/排队/取消"语义，
	/// 旧版接口（无写入目录信息）：保持原有"强制串行 + 打断/排队/取消"语义，
	/// 供不涉及同文件夹并行冲突检测的功能使用。
	/// 启动成功后同时登记到 activeClaims（writeDir: nil），使新冲突检测器可见本任务。
	func requestStart(_ feature: ToolFeature) async -> Bool {
		// If nothing is running or it's the same feature, proceed.
		if currentWork == nil || currentWork == feature {
			currentWork = feature
			pendingWork = nil
			registerStarted(feature, writeDir: nil)
			return true
		}

		// Something else is running → show conflict dialog.
		guard let running = currentWork else { return true }
		let alert = NSAlert()
		alert.messageText = "正在执行其他任务"
		alert.informativeText = """
			当前「\(running.rawValue)」正在运行。

			请选择要如何处理：
			"""
		alert.addButton(withTitle: "打断当前任务")
		alert.addButton(withTitle: "排队等候")
		alert.addButton(withTitle: "取消")

		let response = alert.runModal()
		switch response {
		case .alertFirstButtonReturn: // Interrupt
			cancelWork()
			currentWork = feature
			registerStarted(feature, writeDir: nil)
			return true
		case .alertSecondButtonReturn: // Queue
			pendingWork = feature
			return false
		default: // Cancel
			return false
		}
	}

	// MARK: - 冲突感知接口（照片/视频精细检测等需同文件夹并行仲裁的功能）

	/// 任务在 WorkManager 中的登记记录
	struct WorkClaim: Sendable {
		let feature: ToolFeature
		/// 实际写入目录；nil 表示只读 / 不落盘（如快速模式仅计算哈希不缓存）
		let writeDir: URL?
	}

	/// 冲突裁决结果
	enum WorkStartResult: Sendable, Identifiable, Hashable {
		/// 无运行中任务 → 直接开始
		case allowed
		/// 用户取消，不开始
		case denied
		/// 存在同文件夹双向改写冲突 → 需弹窗，且「并行」选项禁用
		case conflict(running: ToolFeature, reason: String)
		/// 存在其他运行中任务但无冲突 → 需弹窗，「并行」选项可用
		case choice(running: ToolFeature, parallelAllowed: Bool, conflictReason: String?)

		/// 供 SwiftUI .sheet(item:) 使用；弹窗生命周期内实例不变，hashValue 稳定
		var id: Int { hashValue }
	}

	private var activeClaims: [ToolFeature: WorkClaim] = [:]

	/// 请求开始任务，携带实际写入目录用于同文件夹冲突检测。
	/// 不直接弹窗——把裁决结果返回给调用方，由调用方 SwiftUI 弹窗驱动按钮状态（含灰色 hover）。
	func requestStart(_ feature: ToolFeature, writeDir: URL?) -> WorkStartResult {
		// 自身已在运行 → 直接放行（避免重复点击卡死）
		if activeClaims[feature] != nil {
			return .allowed
		}

		// 无任何运行中任务 → 直接放行
		guard !activeClaims.isEmpty else {
			activeClaims[feature] = WorkClaim(feature: feature, writeDir: writeDir)
			return .allowed
		}

		// 检测与任一运行中任务是否存在「同文件夹 + 双向改写」冲突
		var conflictReason: String?
		var runningFeature: ToolFeature?
		for (running, claim) in activeClaims {
			if let reason = Self.directoryConflictBetween(newWriteDir: writeDir, runningWriteDir: claim.writeDir) {
				conflictReason = reason
				runningFeature = running
				break
			}
		}

		// 有冲突：并行禁用，原因明确
		if let reason = conflictReason, let running = runningFeature {
			return .conflict(running: running, reason: reason)
		}

		// 无冲突但有他者在跑：允许并行，弹窗询问（替换/排队/并行）
		runningFeature = activeClaims.keys.first
		return .choice(running: runningFeature!, parallelAllowed: true, conflictReason: nil)
	}

	/// 判定两个写入目录是否冲突（同路径或包含关系，且双方都改写）
	private static func directoryConflictBetween(newWriteDir: URL?, runningWriteDir: URL?) -> String? {
		guard let new = newWriteDir?.path, let running = runningWriteDir?.path else {
			return nil // 任一方只读 → 不冲突
		}
		let a = (new as NSString).standardizingPath
		let b = (running as NSString).standardizingPath
		if a == b {
			return "两个任务都将写入同一目录「\(a)」"
		}
		if a.hasPrefix(b + "/") || b.hasPrefix(a + "/") {
			return "两个任务的写入目录存在包含关系（「\(a)」与「\(b)」），可能互相改写"
		}
		return nil
	}

	/// 调用方在用户确认开始（含并行）后登记任务
	func registerStarted(_ feature: ToolFeature, writeDir: URL?) {
		activeClaims[feature] = WorkClaim(feature: feature, writeDir: writeDir)
	}

	/// 调用方在用户选择「打断/替换」时，清除被替换的任务登记
	func replaceRunning(_ feature: ToolFeature) {
		activeClaims.removeValue(forKey: feature)
	}

	/// Call when work for `feature` has finished.
	func finishWork(_ feature: ToolFeature) {
		activeClaims.removeValue(forKey: feature)
		if currentWork == feature {
			currentWork = nil
		}
		if pendingWork == feature {
			pendingWork = nil
		}
	}

	/// Cancel the currently running work.
	func cancelWork() {
		currentWork = nil
		pendingWork = nil
	}
}
