import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct OpenPanelButton: View {
	enum Mode {
		case file(allowedTypes: [UTType], allowsMultipleSelection: Bool)
		case folder
	}

	let title: String
	let mode: Mode
	let onPick: ([URL]) -> Void

	var body: some View {
		Button(title) {
			let panel = NSOpenPanel()
			panel.canChooseFiles = true
			panel.canChooseDirectories = false
			panel.allowsMultipleSelection = false

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
			}

			if panel.runModal() == .OK {
				onPick(panel.urls)
			}
		}
	}
}

