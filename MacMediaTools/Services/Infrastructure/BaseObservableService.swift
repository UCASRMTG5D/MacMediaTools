import Foundation
import SwiftUI

// MARK: - 标准 ObservableService 基类

/// 所有有状态 Service 的基类
/// 提供统一的：isWorking、progress、cancel、clear、错误处理
@MainActor
open class BaseObservableService: ObservableObject, ObservableService {
	
	// MARK: - Public Published State
	
	@Published public var isWorking = false
	@Published public var progress = ProgressInfo.zero
	@Published public var errorMessage: String?
	
	// MARK: - Internal State
	
	private var currentTask: Task<Void, Never>?
	private let workID = UUID()
	
	// MARK: - Protocol Requirements
	
	public var serviceID: String {
		String(describing: Self.self)
	}
	
	public func cancel() {
		currentTask?.cancel()
		currentTask = nil
		isWorking = false
		progress = .zero
	}
	
	open func clear() {
		cancel()
		errorMessage = nil
	}
	
	// MARK: - Protected Execution API
	
	/// 在后台执行耗时操作，自动管理 isWorking/progress/errorMessage
	/// - Parameters:
	///   - priority: 任务优先级
	///   - operation: 实际工作闭包，接收进度回调
	///   - onProgress: 进度更新回调（可选，默认更新 self.progress）
	///   - onError: 错误处理（可选，默认设置 errorMessage）
	///   - onFinish: 完成回调（无论成功失败都会调用）
	@discardableResult
	open func runAsync(
		priority: TaskPriority = .userInitiated,
		operation: @escaping (@escaping (ProgressInfo) -> Void) async throws -> Void,
		onProgress: (@MainActor (ProgressInfo) -> Void)? = nil,
		onError: (@MainActor (Error) -> Void)? = nil,
		onFinish: (@MainActor () -> Void)? = nil
	) -> Task<Void, Never> {
		// 取消前一个任务
		currentTask?.cancel()
		
		let task = Task(priority: priority) { [weak self] in
			guard let self else { return }
			
			await MainActor.run {
				self.isWorking = true
				self.errorMessage = nil
				self.progress = ProgressInfo(phase: "准备中…")
			}
			
			let progressCallback: @Sendable (ProgressInfo) -> Void = { info in
				Task { @MainActor [weak self] in
					self?.progress = info
					onProgress?(info)
				}
			}
			
			do {
				try await operation(progressCallback)
				await MainActor.run { self.isWorking = false }
			} catch is CancellationError {
				await MainActor.run { self.isWorking = false }
			} catch {
				await MainActor.run {
					self.isWorking = false
					self.handleError(error, customHandler: onError)
				}
			}
			
			await MainActor.run { onFinish?() }
		}
		
		currentTask = task
		return task
	}
	
	/// 简化版：无进度回调的异步执行
	@discardableResult
	open func runSimple(
		priority: TaskPriority = .userInitiated,
		operation: @escaping () async throws -> Void,
		onError: (@MainActor (Error) -> Void)? = nil,
		onFinish: (@MainActor () -> Void)? = nil
	) -> Task<Void, Never> {
		runAsync(
			priority: priority,
			operation: { _ in try await operation() },
			onError: onError,
			onFinish: onFinish
		)
	}
	
	/// 错误处理：可被子类重写
	open func handleError(_ error: Error, customHandler: (@MainActor (Error) -> Void)?) {
		if let customHandler {
			customHandler(error)
		} else if let serviceError = error as? ServiceError {
			errorMessage = serviceError.localizedDescription
		} else {
			errorMessage = "操作失败: \(error.localizedDescription)"
		}
	}
	
	/// 更新进度的便捷方法
	open func updateProgress(_ current: Int, _ total: Int, phase: String = "", message: String = "") {
		Task { @MainActor in
			self.progress = ProgressInfo(current: current, total: total, phase: phase, message: message)
		}
	}
}

// MARK: - 可暂停 Service 基类

/// 支持暂停/恢复的长任务基类
@MainActor
open class BasePausableService: BaseObservableService, PausableService {
	
	@Published public private(set) var isPaused = false
	
	private var pauseContinuation: CheckedContinuation<Void, Never>?
	
	public func pause() {
		guard isWorking && !isPaused else { return }
		isPaused = true
		progress = ProgressInfo(
			current: progress.current,
			total: progress.total,
			phase: "已暂停: \(progress.phase)",
			message: progress.message
		)
	}
	
	public func resume() {
		guard isWorking && isPaused else { return }
		isPaused = false
		progress = ProgressInfo(
			current: progress.current,
			total: progress.total,
			phase: progress.phase.replacingOccurrences(of: "已暂停: ", with: ""),
			message: progress.message
		)
		pauseContinuation?.resume()
		pauseContinuation = nil
	}
	
	/// 在工作循环中调用：如果暂停则挂起直到恢复
	open func checkPaused() async {
		guard isPaused else { return }
		
		await withCheckedContinuation { continuation in
			pauseContinuation = continuation
		}
	}
	
	override open func cancel() {
		// 恢复暂停以便任务正常退出
		if isPaused { resume() }
		super.cancel()
	}
	
	override open func clear() {
		if isPaused { resume() }
		super.clear()
	}
}

// MARK: - 带缓存 Service 基类

/// 内置缓存功能的 Service 基类
@MainActor
open class BaseCacheableService<CacheKey: Hashable, CacheValue>: BaseObservableService, CacheableService {
	
	@Published public var cacheDirectory: URL?
	
	private var memoryCache: [CacheKey: CacheValue] = [:]
	private let cacheQueue = DispatchQueue(label: "cache.queue", attributes: .concurrent)
	
	public func cachedValue(for key: CacheKey) -> CacheValue? {
		cacheQueue.sync { memoryCache[key] }
	}
	
	public func cacheValue(_ value: CacheValue, for key: CacheKey) {
		cacheQueue.async(flags: .barrier) { self.memoryCache[key] = value }
		if let dir = cacheDirectory {
			persistToDisk(key: key, value: value, directory: dir)
		}
	}
	
	public func cleanStaleCache(validKeys: Set<CacheKey>) {
		cacheQueue.async(flags: .barrier) {
			self.memoryCache = self.memoryCache.filter { validKeys.contains($0.key) }
		}
		if let dir = cacheDirectory {
			cleanDiskCache(validKeys: validKeys, directory: dir)
		}
	}
	
	/// 子类实现：磁盘持久化
	open func persistToDisk(key: CacheKey, value: CacheValue, directory: URL) {}
	
	/// 子类实现：磁盘清理
	open func cleanDiskCache(validKeys: Set<CacheKey>, directory: URL) {}
	
	override open func clear() {
		super.clear()
		cacheQueue.async(flags: .barrier) { self.memoryCache.removeAll() }
	}
}