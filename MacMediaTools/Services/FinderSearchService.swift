import Foundation

enum FinderSearchService {

	// MARK: - Types

	struct SearchItem: Identifiable, Sendable {
		let id = UUID()
		let url: URL
		let name: String
		let creationDate: Date?
	}

	enum MediaGroup: String, CaseIterable, Sendable {
		case images = "图片"
		case videos = "视频"
	}

	struct SearchResult: Sendable {
		var images: [SearchItem] = []
		var videos: [SearchItem] = []
	}

	// MARK: - Constants

	static let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "heif", "tiff", "bmp", "webp"]
	static let videoExts: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "flv", "webm", "wmv", "mpeg", "mpg"]

	// MARK: - Public API

	static func search(in folder: URL, keyword: String) -> SearchResult {
		let fm = FileManager.default
		let keys: [URLResourceKey] = [.isRegularFileKey, .creationDateKey, .contentModificationDateKey, .nameKey]
		let didStart = folder.startAccessingSecurityScopedResource()
		defer { if didStart { folder.stopAccessingSecurityScopedResource() } }

		guard let enumerator = fm.enumerator(
			at: folder,
			includingPropertiesForKeys: keys,
			options: [.skipsHiddenFiles],
			errorHandler: nil
		) else {
			return SearchResult()
		}

		let lowerKeyword = keyword.lowercased()
		var images: [SearchItem] = []
		var videos: [SearchItem] = []

		for case let url as URL in enumerator {
			guard let values = try? url.resourceValues(forKeys: Set(keys)),
				  values.isRegularFile == true else { continue }
			let ext = url.pathExtension.lowercased()
			let label = values.name ?? url.lastPathComponent
			if !lowerKeyword.isEmpty && !label.lowercased().contains(lowerKeyword) {
				continue
			}
			let creationDate: Date? = values.creationDate ?? values.contentModificationDate
			let item = SearchItem(url: url, name: label, creationDate: creationDate)
			if imageExts.contains(ext) {
				images.append(item)
			} else if videoExts.contains(ext) {
				videos.append(item)
			}
		}

		return SearchResult(images: groupAndSort(images, group: .images),
		                    videos: groupAndSort(videos, group: .videos))
	}

	static func groupAndSort(_ items: [SearchItem], group: MediaGroup) -> [SearchItem] {
		items.sorted { lhs, rhs in
			let ld = lhs.creationDate ?? Date(timeIntervalSince1970: 0)
			let rd = rhs.creationDate ?? Date(timeIntervalSince1970: 0)
			return ld > rd
		}
	}
}
