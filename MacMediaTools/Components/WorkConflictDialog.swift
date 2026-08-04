import SwiftUI

// MARK: - 任务冲突询问弹窗

/// 当 WorkManager 检测到有任务正在运行、需用户裁决时弹出的对话框。
/// - 无冲突（.choice, parallelAllowed=true）：「替换当前 / 并行运行 / 返回」均可点
/// - 有冲突（.conflict）：「并行运行」灰色禁用，hover 显示冲突原因
/// 「返回」即放弃本次启动、保留运行中任务，与「取消」语义重复，故不单独设取消按钮。
struct WorkConflictDialog: View {
	let result: WorkManager.WorkStartResult
	let runningName: String
	let onReplace: () -> Void
	let onQueue: () -> Void
	let onParallel: () -> Void

	private var conflictReason: String? {
		if case .conflict(_, let reason) = result { return reason }
		if case .choice(_, _, let reason) = result { return reason }
		return nil
	}

	private var parallelAllowed: Bool {
		if case .choice(_, let allowed, _) = result { return allowed }
		if case .conflict = result { return false }
		return false
	}

	var body: some View {
		VStack(spacing: 16) {
			Text("正在执行其他任务")
				.font(.headline)
			Text("当前「\(runningName)」正在运行。\n请选择要如何处理：")
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)

			if let reason = conflictReason {
				Text(reason)
					.font(.caption)
					.foregroundStyle(.orange)
					.multilineTextAlignment(.center)
					.frame(maxWidth: 320)
			}

			VStack(spacing: 10) {
				Button("替换当前任务") { onReplace() }
					.keyboardShortcut(.defaultAction)
				// 并行运行：冲突时灰色禁用 + hover 显示原因
				Button("并行运行") { onParallel() }
					.disabled(!parallelAllowed)
					.help(parallelAllowed ? "与当前任务同时运行" : (conflictReason ?? "当前任务与本项目标文件夹存在改写冲突，无法并行"))
				Button("返回") { onQueue() }
			}
			.frame(width: 220)
		}
		.padding(24)
		.frame(minWidth: 360)
	}
}
