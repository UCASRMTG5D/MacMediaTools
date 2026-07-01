import SwiftUI

@main
struct MacMediaToolsApp: App {
	var body: some Scene {
		WindowGroup {
			RootView()
		}
		// .windowStyle(.titleBar) — removed to resolve toolbar collapse with NavigationSplitView
	}
}

