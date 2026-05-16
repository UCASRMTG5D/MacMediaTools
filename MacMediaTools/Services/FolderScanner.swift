import Foundation

enum FolderScanner {
	static func scanFiles(
		in folder: URL,
		allowedExtensions: Set<String>
	) -> [URL] {
		let fm = FileManager.default
		let keys: [URLResourceKey] = [.isRegularFileKey, .nameKey]
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

