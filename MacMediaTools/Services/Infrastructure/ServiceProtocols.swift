import Foundation
import SwiftUI

// MARK: - Service 协议体系

/// 无状态工具服务标记协议（静态方法集合）
/// 如 FileHasher, FolderScanner, VideoToolkit
public protocol StaticService {
	static var serviceName: String { get }
}

/// 有状态、可观察的服务
/// 所有 ScanModel、Manager 类应遵循此协议
@MainActor
public protocol ObservableService: ObservableObject {
	/// 服务唯一标识
	var serviceID: String { get }
	
	/// 当前工作状态
	var isWorking: Bool { get }
	
	/// 进度信息（用于统一进度条）
	var progress: ProgressInfo { get }
	
	/// 取消当前工作
	func cancel()
	
	/// 清理状态（切换模式/重新开始时调用）
	func clear()
}

/// 进度信息标准结构
public struct ProgressInfo: Sendable, Equatable {
	public let current: Int
	public let total: Int
	public let phase: String
	public let message: String
	
	public var fraction: Double {
		guard total > 0 else { return 0 }
		return Double(current) / Double(total)
	}
	
	public init(current: Int = 0, total: Int = 0, phase: String = "", message: String = "") {
		self.current = current
		self.total = total
		self.phase = phase
		self.message = message
	}
	
	public static let zero = ProgressInfo()
}

/// 可异步执行长耗时任务的服务
@MainActor
public protocol AsyncExecutableService: ObservableService {
	associatedtype Input
	associatedtype Output
	
	/// 开始执行任务
	/// - Parameter input: 输入参数
	/// - Returns: 结果或抛出错误
	func execute(_ input: Input) async throws -> Output
}

/// 可暂停/恢复的长任务服务（简化版，不要求 associatedtype）
@MainActor
public protocol PausableService: ObservableService {
	var isPaused: Bool { get }
	
	func pause()
	func resume()
}

/// 带缓存的服务
public protocol CacheableService {
	associatedtype CacheKey: Hashable
	associatedtype CacheValue
	
	/// 缓存目录
	var cacheDirectory: URL? { get set }
	
	/// 从缓存获取
	func cachedValue(for key: CacheKey) -> CacheValue?
	
	/// 写入缓存
	func cacheValue(_ value: CacheValue, for key: CacheKey)
	
	/// 清理过期缓存
	func cleanStaleCache(validKeys: Set<CacheKey>)
}

// MARK: - 进度报告器（用于解耦 Service 与 UI）

/// 统一进度回调类型
public typealias ProgressHandler = @Sendable (ProgressInfo) -> Void

/// 进度聚合器：合并多个子任务进度为统一进度
public final class ProgressAggregator: @unchecked Sendable {
	private let lock = NSLock()
	private var children: [String: ProgressInfo] = [:]
	private let weights: [String: Double]
	
	public init(weights: [String: Double] = [:]) {
		self.weights = weights
	}
	
	/// 更新子任务进度
	public func update(_ childID: String, _ progress: ProgressInfo) {
		lock.withLock {
			children[childID] = progress
		}
	}
	
	/// 移除子任务
	public func remove(_ childID: String) {
		lock.withLock {
			children.removeValue(forKey: childID)
		}
	}
	
	/// 计算加权总进度
	public var combined: ProgressInfo {
		lock.withLock {
			guard !children.isEmpty else { return .zero }
			
			let totalWeight = weights.values.reduce(0, +)
			guard totalWeight > 0 else {
				// 等权重平均
				let avgFraction = children.values.map(\.fraction).reduce(0, +) / Double(children.count)
				let totalCurrent = children.values.map(\.current).reduce(0, +)
				let totalTotal = children.values.map(\.total).reduce(0, +)
				return ProgressInfo(
					current: totalCurrent,
					total: totalTotal,
					phase: children.values.first?.phase ?? "",
					message: children.values.first?.message ?? ""
				)
			}
			
			var weightedCurrent = 0
			var weightedTotal = 0
			var latestPhase = ""
			var latestMessage = ""
			
			for (id, progress) in children {
				let weight = weights[id] ?? 1.0
				weightedCurrent += Int(Double(progress.current) * weight)
				weightedTotal += Int(Double(progress.total) * weight)
				if !progress.phase.isEmpty { latestPhase = progress.phase }
				if !progress.message.isEmpty { latestMessage = progress.message }
			}
			
			return ProgressInfo(
				current: weightedCurrent,
				total: weightedTotal,
				phase: latestPhase,
				message: latestMessage
			)
		}
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
}

// MARK: - 任务管理

/// 可取消的异步任务包装器
public final class CancellableTask<Output>: @unchecked Sendable {
	private let task: Task<Output, Error>
	private let lock = NSLock()
	private var _isCancelled = false
	
	public init(_ task: Task<Output, Error>) {
		self.task = task
	}
	
	public var value: Output {
		get async throws {
			try await task.value
		}
	}
	
	public func cancel() {
		lock.withLock {
			guard !_isCancelled else { return }
			_isCancelled = true
			task.cancel()
		}
	}
	
	public var isCancelled: Bool {
		lock.withLock { _isCancelled }
	}
}

/// 任务组管理器：统一管理一组可取消任务
@MainActor
public final class TaskGroupManager {
	private var tasks: [String: Task<Void, Never>] = [:]
	
	public func add(_ id: String, _ task: Task<Void, Never>) {
		tasks[id]?.cancel()
		tasks[id] = task
	}
	
	public func cancel(_ id: String) {
		tasks[id]?.cancel()
		tasks.removeValue(forKey: id)
	}
	
	public func cancelAll() {
		for (_, task) in tasks { task.cancel() }
		tasks.removeAll()
	}
	
	public var activeCount: Int { tasks.count }
}