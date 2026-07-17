import Foundation
import Combine

// MARK: - Progress Reporting

/// 统一的进度报告协议，所有长耗时操作的 Service 必须遵循
public protocol ProgressReporter: Sendable {
	/// 报告进度
	/// - Parameters:
	///   - current: 已完成数量
	///   - total: 总数量
	///   - phase: 当前阶段描述
	func report(current: Int, total: Int, phase: String) async
}

/// 默认空实现（无进度报告）
public struct NoProgressReporter: ProgressReporter {
	public init() {}
	public func report(current: Int, total: Int, phase: String) async {}
}

/// 闭包实现的进度报告器，便于 View 直接传入
public struct ClosureProgressReporter: ProgressReporter {
	private let handler: @Sendable (Int, Int, String) async -> Void
	public init(_ handler: @escaping @Sendable (Int, Int, String) async -> Void) {
		self.handler = handler
	}
	public func report(current: Int, total: Int, phase: String) async {
		await handler(current, total, phase)
	}
}

// MARK: - Service 基础协议

/// 无状态的纯函数式 Service 协议（如 VideoToolkit、FileHasher、FolderScanner）
public protocol StaticService {
	associatedtype Input: Sendable
	associatedtype Output: Sendable
	associatedtype Error: Swift.Error
	
	/// 同步或异步执行核心逻辑
	static func execute(_ input: Input, progress: (any ProgressReporter)?) async throws -> Output
}

/// 有状态的 Observable Service 协议（如各类 ScanModel）
@MainActor
public protocol ObservableService: ObservableObject {
	associatedtype State: Sendable
	
	/// 当前状态快照（用于持久化/调试）
	var stateSnapshot: State { get }
	
	/// 取消正在进行的工作
	func cancel()
	
	/// 重置到初始状态
	func reset()
}

/// 可被 WorkManager 管理的后台任务 Service
@MainActor
public protocol BackgroundWorkService: ObservableService {
	/// 启动工作，返回是否成功获取执行权
	func start() async -> Bool
	
	/// 工作完成后的清理
	func finish()
}

// MARK: - Async 执行上下文

/// 统一的后台任务执行器，封装 Task.detached 的常用模式
public enum AsyncExecutor {
	/// 在用户发起优先级队列执行，不阻塞主线程
	/// - Returns: 任务结果
	public static func userInitiated<T: Sendable>(
		_ body: @escaping @Sendable () async -> T
	) async -> T {
		await Task.detached(priority: .userInitiated) {
			await body()
		}.value
	}
	
	/// 在后台队列执行，适合 CPU 密集型计算
	public static func background<T: Sendable>(
		_ body: @escaping @Sendable () async -> T
	) async -> T {
		await Task.detached(priority: .background) {
			await body()
		}.value
	}
	
	/// 在主线程执行（用于 UI 更新前的最后处理）
	@MainActor
	public static func main<T: Sendable>(
		_ body: @escaping @Sendable () async -> T
	) async -> T {
		await body()
	}
}

// MARK: - 结果封装

/// 统一的操作结果，避免到处 throws
public enum ServiceResult<Value: Sendable>: Sendable {
	case success(Value)
	case failure(Error)
	case cancelled
	
	public var value: Value? {
		if case .success(let v) = self { return v }
		return nil
	}
	
	public var error: Error? {
		if case .failure(let e) = self { return e }
		return nil
	}
	
	public var isSuccess: Bool {
		if case .success = self { return true }
		return false
	}
}

// MARK: - 取消令牌

/// 轻量级取消检查，避免在每个循环写 Task.isCancelled
@MainActor
public final class CancellationToken: @unchecked Sendable {
	private var _isCancelled = false
	
	public var isCancelled: Bool {
		_isCancelled || Task.isCancelled
	}
	
	public func cancel() { _isCancelled = true }
	public func reset() { _isCancelled = false }
	
	/// 在循环中调用，若已取消则抛出 CancellationError
	public func check() throws {
		if isCancelled { throw CancellationError() }
	}
}

public struct CancellationError: Error, Sendable {}