import AppKit
import SwiftUI
import AVFoundation
import CryptoKit

struct FileCopyView: View {
	@State private var destFolderURL: URL?
	@State private var availableFiles: [FileItem] = []
	@State private var selectedFiles: Set<FileItem> = []
	@State private var isCopying = false
	@State private var statusText: String = "请选择源文件和目标文件夹"
	@State private var logText: String = ""
	@State private var duplicateReport: [DuplicateFileInfo] = []
	@State private var copyProgress: Double = 0
	@State private var currentFileName: String = ""

	private let photoExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp", "gif", "webp"]
	private let videoExts: Set<String> = ["mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v", "3gp"]

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				Text("文件复制工具")
					.font(.title2)

				VStack(alignment: .leading, spacing: 8) {
					HStack {
						OpenPanelButton(title: "选择源文件…", mode: .mediaFiles) { urls in
							processSelectedFiles(urls)
						}
						.disabled(isCopying)
						Text(availableFiles.isEmpty ? "未选择" : "已选择 \(availableFiles.count) 个文件")
							.lineLimit(1)
							.truncationMode(.middle)
							.foregroundStyle(.secondary)
					}

					HStack {
						OpenPanelButton(title: "选择目标文件夹…", mode: .folder) { urls in
							destFolderURL = urls.first
						}
						.disabled(isCopying)
						Text(destFolderURL?.path ?? "未选择")
							.lineLimit(1)
							.truncationMode(.middle)
							.foregroundStyle(.secondary)
					}
				}

				if !availableFiles.isEmpty {
					VStack(alignment: .leading, spacing: 8) {
						HStack {
							Text("已选择文件 (\(availableFiles.count))")
								.font(.headline)
							Spacer()
							Button(selectedFiles.count == availableFiles.count ? "取消全选" : "全选") {
								if selectedFiles.count == availableFiles.count {
									selectedFiles.removeAll()
								} else {
									selectedFiles = Set(availableFiles)
								}
							}
							.disabled(isCopying)
						}

						List(availableFiles, selection: $selectedFiles) {
							Text("\($0.fileName) (\($0.fileType == .photo ? "图片" : "视频"))")
								.tag($0)
						}
						.frame(height: 200)
						.background(Color(nsColor: .controlBackgroundColor))
						.cornerRadius(8)
					}
				}

				HStack(spacing: 12) {
					Button(isCopying ? "复制中…" : "开始复制") {
						Task { await startCopy() }
					}
					.disabled(isCopying || selectedFiles.isEmpty || destFolderURL == nil)

					if isCopying {
						ProgressView(value: copyProgress)
							.frame(width: 150)
						Text("\(Int(copyProgress * 100))%")
							.monospacedDigit()
							.foregroundStyle(.secondary)
					}
				}

				if !currentFileName.isEmpty {
					Text("正在处理: \(currentFileName)")
						.foregroundStyle(.secondary)
				}

				Text(statusText)
					.foregroundStyle(.secondary)

				if !duplicateReport.isEmpty {
					VStack(alignment: .leading, spacing: 8) {
						Text("重复文件报告")
							.font(.headline)
						ForEach(duplicateReport) { item in
							VStack(alignment: .leading, spacing: 4) {
								Text("文件: \(item.fileName)")
									.font(.subheadline)
								Text("路径: \(item.filePath)")
									.font(.caption)
									.foregroundStyle(.secondary)
								Text("原因: \(item.reason)")
									.font(.caption)
									.foregroundStyle(.orange)
							}
							.padding(8)
							.background(Color.orange.opacity(0.1))
							.cornerRadius(6)
						}
					}
				}

				if !logText.isEmpty {
					VStack(alignment: .leading, spacing: 4) {
						Text("操作日志")
							.font(.headline)
						ScrollView {
							Text(logText)
								.font(.system(.caption, design: .monospaced))
								.foregroundStyle(.secondary)
						}
						.frame(maxHeight: 150)
						.background(Color(nsColor: .controlBackgroundColor))
						.cornerRadius(6)
					}
				}
			}
			.padding()
		}
	}

	private func processSelectedFiles(_ urls: [URL]) {
		logText = ""
		statusText = "正在处理选中的文件…"
		
		var files: [FileItem] = []
		for url in urls {
			let ext = url.pathExtension.lowercased()
			if photoExts.contains(ext) || videoExts.contains(ext) {
				let fileType: FileItem.FileType = photoExts.contains(ext) ? .photo : .video
				files.append(FileItem(url: url, fileType: fileType))
			}
		}
		
		availableFiles = files
		selectedFiles = Set(files)
		
		if files.isEmpty {
			statusText = "未选择有效的图片或视频文件"
		} else {
			statusText = "已选择 \(files.count) 个媒体文件，点击开始复制"
			log("已选择 \(files.count) 个文件")
			for file in files {
				log("  - \(file.fileName) (\(file.fileType == .photo ? "图片" : "视频"))")
			}
		}
	}

	private func startCopy() async {
		guard let destURL = destFolderURL else {
			statusText = "请先选择目标文件夹"
			return
		}

		isCopying = true
		duplicateReport = []
		copyProgress = 0
		currentFileName = ""

		let selectedItems = Array(selectedFiles)
		let total = selectedItems.count
		var successCount = 0
		var duplicateCount = 0

		log("开始复制 \(total) 个文件到: \(destURL.path)")

		for (index, item) in selectedItems.enumerated() {
			await MainActor.run {
				currentFileName = item.fileName
				copyProgress = Double(index) / Double(total)
			}

			let result = await processFile(item, to: destURL)

			switch result {
			case .success:
				successCount += 1
				log("复制成功: \(item.fileName)")
			case .duplicate(let reason):
				duplicateCount += 1
				duplicateReport.append(DuplicateFileInfo(
					fileName: item.fileName,
					filePath: item.url.path,
					reason: reason
				))
				log("跳过重复: \(item.fileName) - \(reason)")
			case .failed(let error):
				log("复制失败: \(item.fileName) - \(error)")
			}

			await MainActor.run {
				copyProgress = Double(index + 1) / Double(total)
			}
		}

		await MainActor.run {
			isCopying = false
			currentFileName = ""
			copyProgress = 1.0
			statusText = "复制完成！成功: \(successCount), 重复跳过: \(duplicateCount)"
			log("复制完成。成功: \(successCount), 重复: \(duplicateCount)")
		}
	}

	private func processFile(_ item: FileItem, to destFolder: URL) async -> CopyResult {
		let destFileURL = destFolder.appendingPathComponent(item.fileName)

		if FileManager.default.fileExists(atPath: destFileURL.path) {
			if item.fileType == .photo {
				let result = await compareImageHashes(source: item.url, destination: destFileURL)
				switch result {
				case .same:
					return .duplicate(reason: "图片内容完全相同")
				case .different:
					let newURL = generateUniqueFileName(for: destFileURL, fileType: .photo)
					return await copyFile(from: item.url, to: newURL)
				case .error(let err):
					return .failed(error: err)
				}
			} else {
				let result = await compareVideoProperties(source: item.url, destination: destFileURL)
				switch result {
				case .same:
					return .duplicate(reason: "视频分辨率和时长完全相同")
				case .different:
					let newURL = generateUniqueFileName(for: destFileURL, fileType: .video)
					return await copyFile(from: item.url, to: newURL)
				case .error(let err):
					return .failed(error: err)
				}
			}
		} else {
			return await copyFile(from: item.url, to: destFileURL)
		}
	}

	private func copyFile(from source: URL, to destination: URL) async -> CopyResult {
		do {
			try FileManager.default.copyItem(at: source, to: destination)
			return .success
		} catch {
			return .failed(error: error.localizedDescription)
		}
	}

	private func compareImageHashes(source: URL, destination: URL) async -> CompareResult {
		return await Task.detached(priority: .userInitiated) {
			do {
				let sourceData = try Data(contentsOf: source)
				let destData = try Data(contentsOf: destination)

				let sourceHash = SHA256.hash(data: sourceData)
				let destHash = SHA256.hash(data: destData)

				if sourceHash == destHash {
					return .same
				} else {
					return .different
				}
			} catch {
				return .error(error.localizedDescription)
			}
		}.value
	}

	private func compareVideoProperties(source: URL, destination: URL) async -> CompareResult {
		return await Task.detached(priority: .userInitiated) {
			do {
				let sourceAsset = AVAsset(url: source)
				let destAsset = AVAsset(url: destination)

				let sourceDuration = try await sourceAsset.load(.duration)
				let destDuration = try await destAsset.load(.duration)

				if abs(sourceDuration.seconds - destDuration.seconds) > 0 {
					return .different
				}

				let sourceTracks = try await sourceAsset.loadTracks(withMediaType: .video)
				let destTracks = try await destAsset.loadTracks(withMediaType: .video)

				if sourceTracks.isEmpty || destTracks.isEmpty {
					return .different
				}

				let sourceSize = try await sourceTracks[0].load(.naturalSize)
				let destSize = try await destTracks[0].load(.naturalSize)

				if sourceSize != destSize {
					return .different
				}

				return .same
			} catch {
				return .error(error.localizedDescription)
			}
		}.value
	}

	private func generateUniqueFileName(for originalURL: URL, fileType: FileItem.FileType) -> URL {
		let parentDir = originalURL.deletingLastPathComponent()
		let baseName = originalURL.deletingPathExtension().lastPathComponent
		let ext = originalURL.pathExtension

		var counter = 1
		var newURL: URL

		repeat {
			let newName = "\(baseName)_\(counter).\(ext)"
			newURL = parentDir.appendingPathComponent(newName)
			counter += 1
		} while FileManager.default.fileExists(atPath: newURL.path)

		return newURL
	}

	private func log(_ message: String) {
		let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
		let logMessage = "[\(timestamp)] \(message)"
		Task { @MainActor in
			logText = logText.isEmpty ? logMessage : logText + "\n" + logMessage
		}
	}
}

struct FileItem: Identifiable, Hashable {
	let id = UUID()
	let url: URL
	let fileType: FileType

	var fileName: String {
		url.lastPathComponent
	}

	enum FileType {
		case photo
		case video
	}
}

struct DuplicateFileInfo: Identifiable {
	let id = UUID()
	let fileName: String
	let filePath: String
	let reason: String
}

enum CopyResult {
	case success
	case duplicate(reason: String)
	case failed(error: String)
}

enum CompareResult {
	case same
	case different
	case error(String)
}