import Foundation

enum ToolFeature: String, CaseIterable, Identifiable {
	case videoCropResize = "宽高调整"
	case videoConcat = "视频片段整合"
	case audioVideoEdit = "音视频处理"
	case keyFrameExtract = "批量截图"
	case duplicatePhotos = "重复照片检测"
	case duplicateVideos = "重复视频检测"
	case fileCopy = "文件复制工具"

	var id: String { rawValue }
}

