import Foundation

public enum ToolFeature: String, CaseIterable, Identifiable, Sendable {
	// 视频编辑
	case videoCropResize = "宽高调整"
	case videoConcat = "视频片段整合"
	case audioVideoEdit = "音视频处理"
	case keyFrameExtract = "批量截图"
	// 合成
	case spatialCanvas = "画幅拼接"
	// 查重清理
	case duplicatePhotos = "重复照片检测"
	case duplicateVideos = "重复视频检测"
	// 文件操作
	case fileCopy = "文件复制工具"
	case fileSearch = "文件搜索"
	// 修复工具
	case mediaRepair = "媒体修复"
	
	public var id: String { rawValue }
}