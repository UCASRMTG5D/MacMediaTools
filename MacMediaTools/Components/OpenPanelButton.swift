import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct OpenPanelButton: View {
	enum Mode {
		case file(allowedTypes: [UTType], allowsMultipleSelection: Bool)
		case folder
		case mediaFiles // 支持图片和视频的多选，带缩略图预览
	}

	let title: String
	let mode: Mode
	let onPick: ([URL]) -> Void

	var body: some View {
		Button(title) {
			let panel = NSOpenPanel()

			switch mode {
			case .file(let allowedTypes, let allowsMultipleSelection):
				panel.canChooseFiles = true
				panel.canChooseDirectories = false
				panel.allowsMultipleSelection = allowsMultipleSelection
				panel.allowedContentTypes = allowedTypes
			case .folder:
				panel.canChooseFiles = false
				panel.canChooseDirectories = true
				panel.allowsMultipleSelection = false
			case .mediaFiles:
				panel.canChooseFiles = true
				panel.canChooseDirectories = false
				panel.allowsMultipleSelection = true
				panel.allowedContentTypes = [
					UTType.image,
					UTType.movie,
					UTType.jpeg,
					UTType.png,
					UTType.heic,
					UTType("public.mpeg-4"),
					UTType("com.apple.quicktime-movie")
				].compactMap { $0 }
				panel.prompt = "选择媒体文件"
			}

			if panel.runModal() == .OK {
				onPick(panel.urls)
			}
		}
	}
}

