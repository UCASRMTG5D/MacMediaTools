import SwiftUI

struct RootView: View {
	@State private var selection: ToolFeature? = .videoCropResize

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
					DuplicateVideoView()
				case .duplicateMedia:
					DuplicateMediaView()
				case .fileCopy:
					FileCopyView()
				case .none:
					Text("请选择左侧功能")
				}
			}
			.padding()
		}
		.frame(minWidth: 980, minHeight: 640)
	}
}
