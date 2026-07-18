import Foundation
import Combine

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

