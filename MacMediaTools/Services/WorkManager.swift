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
	func requestStart(_ feature: ToolFeature) async -> Bool {
		// If nothing is running or it's the same feature, proceed.
		if currentWork == nil || currentWork == feature {
			currentWork = feature
			pendingWork = nil
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
			return true
		case .alertSecondButtonReturn: // Queue
			pendingWork = feature
			return false
		default: // Cancel
			return false
		}
	}

	/// Call when work for `feature` has finished.
	func finishWork(_ feature: ToolFeature) {
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
