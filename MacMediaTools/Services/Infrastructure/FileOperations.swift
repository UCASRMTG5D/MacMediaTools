import Foundation
import AppKit
import Combine

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
