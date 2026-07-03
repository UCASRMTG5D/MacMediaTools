import SwiftUI

// MARK: - Notification

extension Notification.Name {
	static let openHelpWindow = Notification.Name("openHelpWindow")
}

// MARK: - App

@main
struct MacMediaToolsApp: App {
	var body: some Scene {
		WindowGroup {
			RootView()
		}
		.commands {
			HelpMenuCommands()
		}

		// 帮助窗口
		Window("MacMediaTools 帮助", id: "help") {
			HelpPanelView()
		}
		.windowResizability(.contentSize)
	}
}

// MARK: - Help Menu

struct HelpMenuCommands: Commands {
	var body: some Commands {
		CommandGroup(replacing: .help) {
			Button("MacMediaTools 帮助") {
				NotificationCenter.default.post(name: .openHelpWindow, object: nil)
			}
			.keyboardShortcut("/", modifiers: [.command, .shift])
			Divider()
			Button("隐私声明") {
				NotificationCenter.default.post(name: .openHelpWindow, object: nil)
			}
		}
	}
}
