import Foundation
import CryptoKit

// MARK: - FileHasher (静态工具，无状态)

/// 文件哈希计算服务 - 纯函数式静态工具
public enum FileHasher: StaticService {
	public typealias Input = URL
	public typealias Output = String
	public typealias Error = Swift.Error
	
	/// 计算文件 SHA256（分块读取，避免大文件内存溢出）
	public static func execute(_ url: URL, progress: (any ProgressReporter)?) async throws -> String {
		let handle = try FileHandle(forReadingFrom: url)
		defer { try? handle.close() }
		
		let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
		var processed: Int64 = 0
		let chunkSize = 1024 * 1024  // 1MB
		
		var hasher = SHA256()
		
		while true {
			let data = try handle.read(upToCount: chunkSize) ?? Data()
			if data.isEmpty { break }
			hasher.update(data: data)
			processed += Int64(data.count)
			
			if let progress {
				await progress.report(current: Int(processed), total: Int(fileSize), phase: "计算哈希中…")
			}
			
			// 协作式取消检查
			if Task.isCancelled { throw CancellationError() }
		}
		
		let digest = hasher.finalize()
		return digest.map { String(format: "%02x", $0) }.joined()
	}
	
	/// 同步版本（兼容旧代码）
	public static func sha256(url: URL) throws -> String {
		let handle = try FileHandle(forReadingFrom: url)
		defer { try? handle.close() }
		
		var hasher = SHA256()
		while true {
			let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
			if data.isEmpty { break }
			hasher.update(data: data)
		}
		let digest = hasher.finalize()
		return digest.map { String(format: "%02x", $0) }.joined()
	}
}

// MARK: - FolderScanner (静态工具)

/// 文件夹扫描服务 - 纯函数式静态工具
public enum FolderScanner: StaticService {
	public typealias Input = ScanRequest
	public typealias Output = [URL]
	public typealias Error = Swift.Error
	
	public struct ScanRequest: Sendable {
		let folder: URL
		let allowedExtensions: Set<String>
		let skipHidden: Bool
		
		public init(folder: URL, allowedExtensions: Set<String>, skipHidden: Bool = true) {
			self.folder = folder
			self.allowedExtensions = allowedExtensions
			self.skipHidden = skipHidden
		}
	}
	
	public static func execute(_ request: ScanRequest, progress: (any ProgressReporter)?) async throws -> [URL] {
		let fm = FileManager.default
		let keys: [URLResourceKey] = [.isRegularFileKey, .nameKey]
		let didStart = request.folder.startAccessingSecurityScopedResource()
		defer { if didStart { request.folder.stopAccessingSecurityScopedResource() } }
		
		guard let enumerator = fm.enumerator(
			at: request.folder,
			includingPropertiesForKeys: keys,
			options: request.skipHidden ? [.skipsHiddenFiles] : [],
			errorHandler: nil
		) else {
			return []
		}
		
		var results: [URL] = []
		var scanned = 0
		
		for case let url as URL in enumerator {
			guard let values = try? url.resourceValues(forKeys: Set(keys)),
				  values.isRegularFile == true else { continue }
			let ext = url.pathExtension.lowercased()
			if request.allowedExtensions.contains(ext) {
				results.append(url)
			}
			scanned += 1
			
			if scanned % 50 == 0, let progress {
				await progress.report(current: scanned, total: 0, phase: "扫描中…")
			}
			
			if Task.isCancelled { throw CancellationError() }
		}
		
		if let progress {
			await progress.report(current: scanned, total: scanned, phase: "扫描完成")
		}
		
		return results
	}
	
	/// 同步版本（兼容旧代码）
	public static func scanFiles(
		in folder: URL,
		allowedExtensions: Set<String>
	) -> [URL] {
		let fm = FileManager.default
		let keys: [URLResourceKey] = [.isRegularFileKey, .nameKey]
		let didStart = folder.startAccessingSecurityScopedResource()
		defer { if didStart { folder.stopAccessingSecurityScopedResource() } }
		
		guard let enumerator = fm.enumerator(
			at: folder,
			includingPropertiesForKeys: keys,
			options: [.skipsHiddenFiles],
			errorHandler: nil
		) else {
			return []
		}
		
		var results: [URL] = []
		for case let url as URL in enumerator {
			guard let values = try? url.resourceValues(forKeys: Set(keys)),
				  values.isRegularFile == true else { continue }
			let ext = url.pathExtension.lowercased()
			if allowedExtensions.contains(ext) {
				results.append(url)
			}
		}
		return results
	}
}

// MARK: - MediaFileExtensions (常量迁移)

public enum MediaFileExtensions {
	public static let photo: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp", "gif", "webp"]
	public static let video: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "wmv", "flv", "webm", "3gp"]
	public static let gif: Set<String> = ["gif"]
	public static let all: Set<String> = photo.union(video)
}