import SwiftUI

struct RootView: View {
	@State private var selection: ToolFeature? = nil
	@Environment(\.openWindow) private var openWindow

	/// Lives here so DuplicateVideoView's scan continues running
	/// when the user switches to another feature and back.
	@StateObject private var duplicateVideoScan = DuplicateVideoScanModel()

	/// Lives here so MediaRepairView's detect/repair continues running
	/// when the user switches to another feature and back.
	@StateObject private var mediaRepair = MediaRepairModel()

	var body: some View {
		NavigationSplitView {
			List(ToolFeature.allCases, id: \.self, selection: $selection) { item in
				Text(item.rawValue)
					.tag(Optional(item))
			}
			.navigationTitle("功能")
		} detail: {
			Group {
				switch selection {
				case .videoCropResize:
					VideoCropResizeView()
				case .videoConcat:
					VideoConcatView()
				case .audioVideoEdit:
					AudioVideoEditorView()
				case .keyFrameExtract:
					VideoScreenshotExtractorView()
				case .duplicatePhotos:
					DuplicatePhotoView()
				case .duplicateVideos:
					DuplicateVideoView(scanModel: duplicateVideoScan)
				case .fileCopy:
					FileCopyView()
				case .spatialCanvas:
					SpatialCanvasView()
			case .mediaRepair:
				MediaRepairView(mediaRepair: mediaRepair)
				case nil:
					WelcomeDefaultView()
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.navigationTitle(selection?.rawValue ?? "")
		}
		.frame(minWidth: 1000, minHeight: 700)
		.onReceive(NotificationCenter.default.publisher(for: .openHelpWindow)) { _ in
			openWindow(id: "help")
		}
	}
}
