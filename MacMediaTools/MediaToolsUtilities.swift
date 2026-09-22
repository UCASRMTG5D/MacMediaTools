import AppKit

enum MediaFileExtensions {
    static let photo: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp", "gif", "webp"]
    static let video: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "wmv", "flv", "webm", "3gp"]
    static let all: Set<String> = photo.union(video)
}

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "00:00.000" }
    let clamped = max(0, seconds)
    let ms = Int((clamped.truncatingRemainder(dividingBy: 1)) * 1000)
    let s = Int(clamped) % 60
    let m = Int(clamped) / 60 % 60
    let h = Int(clamped) / 3600
    if h > 0 {
        return String(format: "%d:%02d:%02d.%03d", h, m, s, ms)
    }
    return String(format: "%02d:%02d.%03d", m, s, ms)
}

func formatTimeShort(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "00:00" }
    let clamped = max(0, seconds)
    let s = Int(clamped) % 60
    let m = Int(clamped) / 60 % 60
    let h = Int(clamped) / 3600
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    }
    return String(format: "%02d:%02d", m, s)
}

func parseTimeString(_ string: String) -> Double? {
    let components = string.components(separatedBy: CharacterSet(charactersIn: ":."))
    let numbers = components.compactMap { Double($0) }
    switch numbers.count {
    case 4:
        let h = min(Int(numbers[0]), 99)
        let m = min(Int(numbers[1]), 59)
        let s = min(Int(numbers[2]), 59)
        let ms = min(Int(numbers[3]), 999)
        return Double(h * 3600 + m * 60 + s) + Double(ms) / 1000
    case 3:
        let m = min(Int(numbers[0]), 99)
        let s = min(Int(numbers[1]), 59)
        let ms = min(Int(numbers[2]), 999)
        return Double(m * 60 + s) + Double(ms) / 1000
    case 2:
        let s = min(Int(numbers[0]), 99)
        let ms = min(Int(numbers[1]), 999)
        return Double(s) + Double(ms) / 1000
    default: return nil
    }
}

func formatFileNameTimestamp(_ seconds: Double) -> String {
    let h = Int(seconds) / 3600
    let m = Int(seconds) / 60 % 60
    let s = Int(seconds) % 60
    let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
    return String(format: "%02d-%02d-%02d-%03d", h, m, s, ms)
}

func currentTimestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return formatter.string(from: Date())
}

// MARK: - Confirm Trash

/// Shows a confirmation NSAlert and moves the file to Trash if confirmed.
/// - Returns: `true` if the file was trashed, `false` if cancelled.
@discardableResult
func confirmAndTrash(url: URL) -> Bool {
    let alert = NSAlert()
    alert.messageText = "确认移到废纸篓"
    alert.informativeText = "确定要将文件 \"\(url.lastPathComponent)\" 移到废纸篓吗？"
    alert.alertStyle = .warning
    alert.addButton(withTitle: "移到废纸篓")
    alert.addButton(withTitle: "取消")

    guard alert.runModal() == .alertFirstButtonReturn else { return false }
    do {
        try TrashManager.moveToTrash(url)
        return true
    } catch {
        return false
    }
}

// MARK: - 宽高比预设

/// 宽高比预设，供宽高调整功能的裁剪与尺寸调整复用
struct AspectRatioPreset: Identifiable {
    let id: String
    let label: String
    let ratioWidth: CGFloat
    let ratioHeight: CGFloat

    /// ratio 数值（宽 / 高）
    var ratio: CGFloat { ratioWidth / ratioHeight }

    static let all: [AspectRatioPreset] = [
        AspectRatioPreset(id: "1:1", label: "1:1", ratioWidth: 1, ratioHeight: 1),
        AspectRatioPreset(id: "4:3", label: "4:3", ratioWidth: 4, ratioHeight: 3),
        AspectRatioPreset(id: "3:2", label: "3:2", ratioWidth: 3, ratioHeight: 2),
        AspectRatioPreset(id: "16:9", label: "16:9", ratioWidth: 16, ratioHeight: 9),
        AspectRatioPreset(id: "3:4", label: "3:4", ratioWidth: 3, ratioHeight: 4),
        AspectRatioPreset(id: "2:3", label: "2:3", ratioWidth: 2, ratioHeight: 3),
        AspectRatioPreset(id: "9:16", label: "9:16", ratioWidth: 9, ratioHeight: 16),
    ]
}

// MARK: - UserDefaults Keys

extension UserDefaults {
    enum Keys {
        static let lastExtractionTask = "LastExtractionTask"
        static let videoScreenshotExtractorLogs = "VideoScreenshotExtractorLogs"
        static let operationLogs = "OperationLogs"
    }
}

/// Shows a confirmation NSAlert for deleting a source file.
/// - Returns: `true` if the file was deleted/recycled, `false` if cancelled.
@discardableResult
func confirmAndDeleteSource(url: URL) -> Bool {
    let alert = NSAlert()
    alert.messageText = "确认删除文件"
    alert.informativeText = "确定要删除文件 \"\(url.lastPathComponent)\" 吗？此操作无法撤销。"
    alert.alertStyle = .warning
    alert.addButton(withTitle: "删除")
    alert.addButton(withTitle: "取消")

    guard alert.runModal() == .alertFirstButtonReturn else { return false }
    do {
        try FileManager.default.removeItem(at: url)
        return true
    } catch {
        return false
    }
}
