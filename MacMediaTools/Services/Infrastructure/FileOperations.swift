import Foundation
import AppKit
import Combine

/// 原子写入：先写临时文件，成功后 replace，避免写入中断导致文件损坏
public enum AtomicWrite {
	public indirect enum Error: Swift.Error, LocalizedError {
		case tempFileCreationFailed
		case writeFailed(reason: String)
		case replaceFailed(reason: String)
		
		public var errorDescription: String? {
			switch self {
			case .tempFileCreationFailed: return "无法创建临时文件"
			case .writeFailed(let reason): return "写入失败: \(reason)"
			case .replaceFailed(let reason): return "文件替换失败: \(reason)"
			}
		}
	}
	
	/// 原子写入 Data
	/// - Parameters:
	///   - data: 要写入的数据
	///   - url: 目标文件 URL
	///   - options: 写入选项（默认 .atomicWrite 在某些系统上不可靠，我们手动实现）
	public static func write(
		_ data: Data,
		to url: URL,
		options: Data.WritingOptions = []
	) throws {
		let tempURL = url.deletingLastPathComponent()
			.appendingPathComponent(".tmp_\(url.lastPathComponent)_\(UUID().uuidString.prefix(8))")
		
		do {
			try data.write(to: tempURL, options: options)
			try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
		} catch {
			// 清理临时文件
			try? FileManager.default.removeItem(at: tempURL)
			throw Error.writeFailed(reason: error.localizedDescription)
		}
	}
	
	/// 原子写入字符串
	public static func write(
		_ string: String,
		to url: URL,
		encoding: String.Encoding = .utf8
	) throws {
		guard let data = string.data(using: encoding) else {
			throw Error.writeFailed(reason: CocoaError(.fileWriteInvalidFileName).localizedDescription)
		}
		try write(data, to: url)
	}
}

// MARK: - Bookmark Manager

/// 安全作用域书签管理，统一处理文件夹/文件的持久化访问权限
public actor BookmarkManager {
	public static let shared = BookmarkManager()
	
	private var bookmarks: [String: Data] = [:]
	private let userDefaults = UserDefaults.standard
	private let bookmarkPrefix = "security_bookmark_"
	
	private init() {
		loadAll()
	}
	
	/// 保存 URL 的书签
	public func saveBookmark(for url: URL, key: String) async throws {
		let bookmarkData = try url.bookmarkData(
			options: .withSecurityScope,
			includingResourceValuesForKeys: nil,
			relativeTo: nil
		)
		bookmarks[key] = bookmarkData
		userDefaults.set(bookmarkData, forKey: bookmarkPrefix + key)
	}
	
	/// 解析书签并返回可访问的 URL（需要在使用前调用 startAccessing）
	public func resolveBookmark(key: String) async -> URL? {
		guard let data = bookmarks[key] ?? userDefaults.data(forKey: bookmarkPrefix + key) else {
			return nil
		}
		
		var isStale = false
		guard let url = try? URL(
			resolvingBookmarkData: data,
			options: .withSecurityScope,
			relativeTo: nil,
			bookmarkDataIsStale: &isStale
		) else {
			return nil
		}
		
		if isStale {
			// 书签过期，尝试重新保存
			try? await saveBookmark(for: url, key: key)
		}
		return url
	}
	
	/// 开始访问安全作用域资源
	/// - Returns: 是否成功开始访问（需配对调用 stopAccessing）
	public func startAccessing(_ url: URL) -> Bool {
		url.startAccessingSecurityScopedResource()
	}
	
	/// 停止访问安全作用域资源
	public func stopAccessing(_ url: URL) {
		url.stopAccessingSecurityScopedResource()
	}
	
	/// 删除书签
	public func removeBookmark(key: String) {
		bookmarks.removeValue(forKey: key)
		userDefaults.removeObject(forKey: bookmarkPrefix + key)
	}
	
	/// 批量加载启动时已存的书签
	private func loadAll() {
		let keys = userDefaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(bookmarkPrefix) }
		for key in keys {
			if let data = userDefaults.data(forKey: key) {
				let shortKey = String(key.dropFirst(bookmarkPrefix.count))
				bookmarks[shortKey] = data
			}
		}
	}
	
	/// 安全执行带作用域访问的操作
	public func withSecurityScope<T: Sendable>(
		key: String,
		_ body: @escaping @Sendable (URL) async throws -> T
	) async throws -> T? {
		guard let url = await resolveBookmark(key: key) else { return nil }
		let started = startAccessing(url)
		defer { if started { stopAccessing(url) } }
		return try await body(url)
	}
}

// MARK: - Trash Manager

/// 统一的废纸篓操作，替代分散的 NSWorkspace.shared.recycle / FileManager.trashItem
public enum TrashManager {
	public indirect enum Error: Swift.Error, LocalizedError {
		case moveFailed(underlying: Swift.Error)
		case notSupported
		
		public var errorDescription: String? {
			switch self {
			case .moveFailed(let e): return "移至废纸篓失败: \(e.localizedDescription)"
			case .notSupported: return "当前系统不支持废纸篓操作"
			}
		}
	}
	
	/// 将文件移至废纸篓（macOS 10.14+ 使用 FileManager.trashItem，更早版本回退）
	/// - Returns: true 表示成功
	@discardableResult
	public static func moveToTrash(_ url: URL) throws -> Bool {
		if #available(macOS 10.14, *) {
			var resultingURL: NSURL?
			try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
			return true
		} else {
			// 回退：NSWorkspace.recycle（已弃用但仍可用）
			NSWorkspace.shared.recycle([url])
			return true
		}
	}
	
	/// 批量移至废纸篓，返回失败的文件
	public static func moveToTrash(_ urls: [URL]) -> [URL: Error] {
		var failed: [URL: Error] = [:]
		for url in urls {
			do {
				try moveToTrash(url)
			} catch let e as Error {
				failed[url] = e
			} catch {
				failed[url] = Error.moveFailed(underlying: error)
			}
		}
		return failed
	}
}

// MARK: - Unique File URL

/// 生成不覆盖已有文件的目标 URL。
/// 同名时追加 `_repaired` 编号（或调用方指定的后缀），遵循「同名文件保护」规则，
/// 不静默覆盖，避免磁盘文件数少于预期（见 BUG_KNOWLEDGE.md 的 Data.write 静默覆盖条目）。
public enum UniqueFileURL {
	/// 为 `url` 生成带 `targetExtension` 的新 URL，若已存在同名文件则追加自增编号。
	/// - Parameters:
	///   - url: 源文件 URL（用于提取父目录与基础名）
	///   - targetExtension: 目标扩展名（不含点）
	///   - suffix: 冲突时的编号后缀，默认 "_repaired"
	public static func make(
		for url: URL,
		targetExtension: String,
		suffix: String = "_repaired"
	) -> URL {
		let parent = url.deletingLastPathComponent()
		let base = url.deletingPathExtension().lastPathComponent
		var candidate = parent.appendingPathComponent("\(base).\(targetExtension)")
		guard FileManager.default.fileExists(atPath: candidate.path) else {
			return candidate
		}
		var counter = 1
		repeat {
			candidate = parent.appendingPathComponent("\(base)\(suffix)\(counter).\(targetExtension)")
			counter += 1
		} while FileManager.default.fileExists(atPath: candidate.path)
		return candidate
	}
}

// MARK: - File Comparison

/// 文件比较策略协议
public protocol FileComparator: Sendable {
	associatedtype Result: Sendable
	
	/// 比较两个文件
	/// - Returns: 比较结果
	static func compare(_ lhs: URL, _ rhs: URL) async throws -> Result
}

/// 图片 SHA256 完全相等比较
public enum ImageSHA256Comparator: FileComparator {
	public typealias Result = Bool // true = 相同
	
	public static func compare(_ lhs: URL, _ rhs: URL) async throws -> Bool {
		let hash1 = try FileHasher.sha256(url: lhs)
		let hash2 = try FileHasher.sha256(url: rhs)
		return hash1 == hash2
	}
}

/// 视频时长+分辨率比较
public enum VideoPropertyComparator: FileComparator {
	public typealias Result = Bool
	
	public static func compare(_ lhs: URL, _ rhs: URL) async throws -> Bool {
		let info1 = try await VideoToolkit.readDisplayInfo(url: lhs)
		let info2 = try await VideoToolkit.readDisplayInfo(url: rhs)
		
		return abs(info1.durationSeconds - info2.durationSeconds) < 0.5 &&
			   info1.displaySize == info2.displaySize
	}
}