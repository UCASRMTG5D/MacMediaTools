import SwiftUI

struct RootView: View {
	@State private var selection: ToolFeature? = .videoResize

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
				case .videoResize:
					VideoResizeView()
				case .videoCrop:
					VideoCropView()
				case .videoConcat:
					VideoConcatView()
				case .duplicatePhotos:
					DuplicatePhotoView()
				case .duplicateVideos:
					DuplicateVideoView()
				case .none:
					Text("请选择左侧功能")
				}
			}
			.padding()
		}
		.frame(minWidth: 980, minHeight: 640)
	}
}
