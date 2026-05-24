import Foundation

enum ToolFeature: String, CaseIterable, Identifiable {
	case videoResize = "视频尺寸修改"
	case videoCrop = "视频尺寸裁剪"
	case videoConcat = "多个视频拼接"
	case duplicatePhotos = "重复照片检测"
	case duplicateVideos = "重复视频检测"
	case videoDownload = "视频批量下载"
	case fileCopy = "文件复制工具"

	var id: String { rawValue }
}

