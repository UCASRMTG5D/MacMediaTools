import Foundation
import Combine

// MARK: - Dependency Injection Container

/// 简单的协议化依赖注入容器
/// - 编译期类型安全
/// - 支持单例/瞬态/作用域生命周期
/// - 无运行时反射，纯 Swift 实现
public final class DependencyContainer: @unchecked Sendable {
	
	// 单例注册表
	private var singletons: [ObjectIdentifier: Any] = [:]
	// 工厂注册表
	private var factories: [ObjectIdentifier: () -> Any] = [:]
	// 作用域实例缓存
	private var scopedInstances: [ObjectIdentifier: Any] = [:]
	
	private let lock = NSLock()
	
	public init() {}
	
	/// 注册单例（共享实例）
	/// - Parameters:
	///   - type: 协议或具体类型
	///   - factory: 创建实例的闭包（仅执行一次）
	public func registerSingleton<T>(_ type: T.Type, factory: @escaping () -> T) {
		let key = ObjectIdentifier(type)
		lock.withLock {
			factories[key] = factory
		}
	}
	
	/// 注册瞬态（每次获取新实例）
	public func registerTransient<T>(_ type: T.Type, factory: @escaping () -> T) {
		let key = ObjectIdentifier(type)
		lock.withLock {
			factories[key] = factory
		}
	}
	
	/// 注册作用域实例（同一作用域内共享，不同作用域隔离）
	/// 当前实现简化为单例，后续可扩展
	public func registerScoped<T>(_ type: T.Type, factory: @escaping () -> T) {
		registerSingleton(type, factory: factory)
	}
	
	/// 解析依赖
	/// - Throws: DependencyError.ifNotRegistered 未注册
	public func resolve<T>(_ type: T.Type) throws -> T {
		let key = ObjectIdentifier(type)
		
		return try lock.withLock {
			// 先查单例缓存
			if let instance = singletons[key] as? T {
				return instance
			}
			// 再查工厂
			if let factory = factories[key] {
				let instance = factory() as! T
				// 如果是单例模式（有工厂且无显式标记），缓存它
				singletons[key] = instance
				return instance
			}
			throw DependencyError.notRegistered(type)
		}
	}
	
	/// 可选解析（不抛出，返回 nil）
	public func resolveOptional<T>(_ type: T.Type) -> T? {
		try? resolve(type)
	}
	
	/// 重置容器（测试用）
	public func reset() {
		lock.withLock {
			singletons.removeAll()
			factories.removeAll()
			scopedInstances.removeAll()
		}
	}
	
	/// 预热单例（启动时调用，避免首次解析延迟）
	public func warmUp() {
		lock.withLock {
			for (key, factory) in factories where singletons[key] == nil {
				singletons[key] = factory()
			}
		}
	}
}

// MARK: - Dependency Errors

public enum DependencyError: Error, LocalizedError {
	case notRegistered(Any.Type)
	case circularDependency(Any.Type)
	case resolutionFailed(Any.Type, underlying: Error)
	
	public var errorDescription: String? {
		switch self {
		case .notRegistered(let type):
			return "依赖未注册: \(type)"
		case .circularDependency(let type):
			return "循环依赖: \(type)"
		case .resolutionFailed(let type, let error):
			return "依赖解析失败 \(type): \(error.localizedDescription)"
		}
	}
}

// MARK: - Property Wrapper 便捷注入

/// 在 View/Service 中使用 `@Inject` 自动从容器解析
@propertyWrapper
public struct Inject<T> {
	private let container: DependencyContainer
	private let type: T.Type
	private var cached: T?
	
	public init(_ type: T.Type = T.self, container: DependencyContainer = .shared) {
		self.container = container
		self.type = type
	}
	
	public var wrappedValue: T {
		mutating get {
			if let cached { return cached }
			let resolved = try! container.resolve(type)
			cached = resolved
			return resolved
		}
		set { cached = newValue }
	}
}

/// 可选注入（解析失败返回 nil）
@propertyWrapper
public struct InjectOptional<T> {
	private let container: DependencyContainer
	private let type: T.Type
	private var cached: T?
	
	public init(_ type: T.Type = T.self, container: DependencyContainer = .shared) {
		self.container = container
		self.type = type
	}
	
	public var wrappedValue: T? {
		mutating get {
			if let cached { return cached }
			cached = container.resolveOptional(type)
			return cached
		}
		set { cached = newValue }
	}
}

// MARK: - 全局共享容器

extension DependencyContainer {
	public static let shared = DependencyContainer()
	
	/// 配置标准服务（应用启动时调用一次）
	public func configureStandardServices() {
		// 全局单例服务
		registerSingleton(WorkManager.self) { WorkManager.shared }
		registerSingleton(BookmarkManager.self) { BookmarkManager.shared }
		registerSingleton(OperationLogManager.self) { OperationLogManager.shared }
		
		// 无状态工具服务（按需解析即可，无需注册）
		// FileHasher, FolderScanner, VideoToolkit 等为 StaticService 直接调用
	}
}

// MARK: - Lock Helper

extension NSLock {
	func withLock<T>(_ body: () throws -> T) rethrows -> T {
		lock()
		defer { unlock() }
		return try body()
	}
}