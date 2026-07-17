import AppKit
import AVFoundation
import SwiftUI

// MARK: - 媒体修复模型

/// 持有媒体修复的全部状态与执行逻辑。
/// 由 RootView 以 @StateObject 持有，因此切换功能时视图被销毁也不会中断正在运行的检测/修复。
@MainActor
final class MediaRepairModel: ObservableObject {

	@Published var selectedFiles: [URL] = []
	@Published var scope: MediaRepairScope = .all
	@Published var isDetecting = false
	@Published var isScanningFolder = false
	@Published var isRepairing = false
	@Published var result: MediaRepairResult?
	@Published var checkedIDs: Set<MediaRepairItem.ID> = []
	@Published var statusText: String = "请选择文件或文件夹（图片与视频）"
	@Published var logText: String = ""
	@Published var repairProgress: Double = 0
	@Published var currentFileName: String = ""

	private var detectTask: Task<Void, Never>?
	private var repairTask: Task<Void, Never>?

	// MARK: - 选择文件

	func selectFiles(_ urls: [URL]) {
		selectedFiles = urls
		resetDetection()
		log("已选择 \(urls.count) 个文件")
	}

	func selectFolder(_ folder: URL) {
		// 文件夹扫描放到后台，避免大目录阻塞主线程（导入阶段卡顿修复）
		isScanningFolder = true
		Task {
			let scanned = await Task.detached(priority: .userInitiated) {
				FolderScanner.scanFiles(in: folder, allowedExtensions: MediaFileExtensions.all)
			}.value
			await MainActor.run {
				selectedFiles = scanned
				resetDetection()
				isScanningFolder = false
				log("已扫描文件夹，找到 \(scanned.count) 个媒体文件")
			}
		}
	}

	// MARK: - 检测

	func startDetection() {
		guard !selectedFiles.isEmpty else { return }
		detectTask?.cancel()
		isDetecting = true
		statusText = "正在检测文件格式与编码…"

		let urls = selectedFiles
		let scope = scope

		detectTask = Task { @MainActor in
			guard await WorkManager.shared.requestStart(.mediaRepair) else {
				self.isDetecting = false
				return
			}
			defer {
				self.isDetecting = false
				WorkManager.shared.finishWork(.mediaRepair)
			}

			let detected = await MediaRepair.detect(urls: urls, scope: scope)
			guard !Task.isCancelled else { return }

			self.result = detected
			self.checkedIDs = Set(detected.imageItems.map { $0.id } + detected.videoItems.map { $0.id })
			let total = detected.imageItems.count + detected.videoItems.count
			self.statusText = total == 0
				? "未发现问题，所有文件的格式与扩展名均匹配。"
				: "发现 \(total) 处可修复问题，请勾选需要修复的项目。"
		}
	}

	// MARK: - 修复（后台并行执行，切走功能不中断）

	func startRepair() {
		guard let detected = result else { return }
		let allItems = detected.imageItems + detected.videoItems
		let toRepair = allItems.filter { checkedIDs.contains($0.id) }
		guard !toRepair.isEmpty else { return }

		repairTask?.cancel()
		isRepairing = true
		let total = toRepair.count
		repairProgress = 0
		currentFileName = ""
		statusText = "正在修复 \(total) 个项目…"
		log("开始修复 \(total) 个项目")

		repairTask = Task { @MainActor in
			guard await WorkManager.shared.requestStart(.mediaRepair) else {
				self.isRepairing = false
				return
			}
			defer {
				self.isRepairing = false
				WorkManager.shared.finishWork(.mediaRepair)
			}

			// 并发执行：每个文件的修复（改名/无损封装）互不依赖，放到后台并行，
			// 受限于设备核心数，避免在主线程串行执行导致卡顿。
			let results = await withTaskGroup(of: (URL, Bool, String?).self) { group in
				for item in toRepair {
					group.addTask(priority: .userInitiated) {
						do {
							try await MediaRepair.repair(item)
							return (item.url, true, nil)
						} catch {
							return (item.url, false, error.localizedDescription)
						}
					}
				}
				var collected: [(URL, Bool, String?)] = []
				for await r in group {
					collected.append(r)
					let done = collected.count
					await MainActor.run {
						self.repairProgress = Double(done) / Double(total)
						self.currentFileName = r.0.lastPathComponent
					}
				}
				return collected
			}

			guard !Task.isCancelled else { return }

			var success = 0
			var failed = 0
			for (url, ok, err) in results {
				if ok {
					success += 1
					self.log("修复成功: \(url.lastPathComponent)")
				} else {
					failed += 1
					self.log("修复失败: \(url.lastPathComponent) - \(err ?? "未知错误")")
				}
			}

			self.repairProgress = 1.0
			self.currentFileName = ""
			self.statusText = "修复完成！成功: \(success), 失败: \(failed)"
			self.log("修复完成。成功: \(success), 失败: \(failed)")
			// 清空检测结果，避免重复修复
			self.result = nil
			self.checkedIDs = []
		}
	}

	// MARK: - 勾选切换

	func toggleItem(_ item: MediaRepairItem) {
		if checkedIDs.contains(item.id) {
			checkedIDs.remove(item.id)
		} else {
			checkedIDs.insert(item.id)
		}
	}

	func toggleSection(_ items: [MediaRepairItem]) {
		let allChecked = !items.isEmpty && items.allSatisfy { checkedIDs.contains($0.id) }
		if allChecked {
			for item in items { checkedIDs.remove(item.id) }
		} else {
			for item in items { checkedIDs.insert(item.id) }
		}
	}

	func sectionAllChecked(_ items: [MediaRepairItem]) -> Bool {
		!items.isEmpty && items.allSatisfy { checkedIDs.contains($0.id) }
	}

	// MARK: - 内部

	private func resetDetection() {
		result = nil
		checkedIDs = []
		statusText = "已选择 \(selectedFiles.count) 个文件，点击「开始检测」"
		repairProgress = 0
		currentFileName = ""
	}

	private func log(_ message: String) {
		let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
		let logMessage = "[\(timestamp)] \(message)"
		logText = logText.isEmpty ? logMessage : logText + "\n" + logMessage
	}
}
