import Foundation
import SwiftUI

// MARK: - ObservableService Base Class

/// 所有有状态、可观察 Service 的基类
/// 提供统一的：isWorking、progress、cancel、clear、错误处理
@MainActor
open class BaseObservableService: ObservableObject {
	
	// MARK: - Published State
	
	@Published public private(set) var isWorking = false
	@Published public private(set) var progress = ProgressInfo.zero
	@Published public var errorMessage: String?
	
	// MARK: - Internal State
	
	private var currentTask: Task<Void, Never>?
	
	// MARK: - Public API
	
	/// 取消当前工作
	public func cancel() {
		currentTask?.cancel()
		currentTask = nil
		isWorking = false
		progress = .zero
	}
	
	/// 清理状态（切换模式/重新开始时调用）
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
	protected func runAsync(
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
	protected func runSimple(
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
	protected func updateProgress(_ current: Int, _ total: Int, phase: String = "", message: String = "") {
		Task { @MainActor in
			self.progress = ProgressInfo(current: current, total: total, phase: phase, message: message)
		}
	}
}

// MARK: - 可暂停 Service 基类

/// 支持暂停/恢复的长任务基类
@MainActor
open class PausableService: BaseObservableService, PausableService {
	
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
	protected func checkPaused() async {
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

// MARK: - 标准错误类型

/// 服务层标准错误
public enum ServiceError: LocalizedError, Sendable {
	case cancelled
	case invalidInput(String)
	case resourceUnavailable(String)
	case operationFailed(String, underlying: Error?)
	case permissionDenied(String)
	case notFound(String)
	case validationFailed(String)
	case unsupportedFormat(String)
	case diskSpaceInsufficient(required: UInt64, available: UInt64)
	
	public var errorDescription: String? {
		switch self {
		case .cancelled:
			return "操作已取消"
		case .invalidInput(let msg):
			return "输入无效: \(msg)"
		case .resourceUnavailable(let msg):
			return "资源不可用: \(msg)"
		case .operationFailed(let msg, let err):
			if let err { return "\(msg): \(err.localizedDescription)" }
			return "操作失败: \(msg)"
		case .permissionDenied(let msg):
			return "权限不足: \(msg)"
		case .notFound(let msg):
			return "未找到: \(msg)"
		case .validationFailed(let msg):
			return "验证失败: \(msg)"
		case .unsupportedFormat(let msg):
			return "不支持的格式: \(msg)"
		case .diskSpaceInsufficient(let req, let avail):
			return "磁盘空间不足，需要 \(ByteCountFormatter.string(fromByteCount: Int64(req), countStyle: .file))，可用 \(ByteCountFormatter.string(fromByteCount: Int64(avail), countStyle: .file))"
		}
	}