import Combine
import Foundation

// MARK: - 文件搜索模型

/// 持有文件搜索的全部状态与执行逻辑。
/// 由 RootView 以 @StateObject 持有，因此切换功能时视图被销毁也不会中断正在进行的搜索，
/// 切回时状态仍在，直接展示进行中/已完成的结果。
///
/// 架构说明：文件搜索为只读操作（writeDir = nil），不与任何任务冲突，
/// 因此不参与 WorkManager 排他调度，天然支持与其它任务并行运行。
@MainActor
final class FileSearchModel: BaseObservableService {

	@Published var folderURL: URL?
	@Published var keyword = ""
	@Published var searchResult: FinderSearchService.SearchResult?

	/// 是否正在搜索（与 BaseObservableService.isWorking 同步）
	var isSearching: Bool { isWorking }

	// MARK: - 选择文件夹

	func selectFolder(_ url: URL?) {
		folderURL = url
		searchResult = nil
		errorMessage = nil
	}

	// MARK: - 搜索

	/// 开始搜索。立即返回；进度通过 @Published 属性更新。
	/// 搜索在后台线程（Task.detached）执行，切走功能不中断，可与其它任务并行。
	func startSearch() {
		guard let folder = folderURL else { return }
		let keyword = keyword

		runSimple(
			priority: .userInitiated,
			operation: {
				let result = await Task.detached(priority: .userInitiated) {
					FinderSearchService.search(in: folder, keyword: keyword)
				}.value
				guard !Task.isCancelled else { return }
				self.searchResult = result
				self.errorMessage = nil
			},
			onError: { [weak self] error in
				self?.errorMessage = error.localizedDescription
			}
		)
	}
}