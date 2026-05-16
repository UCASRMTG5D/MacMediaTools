import CryptoKit
import Foundation

enum FileHasher {
	/// 对文件做 SHA256（分块读取，避免一次性读入内存）
	static func sha256(url: URL) throws -> String {
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

