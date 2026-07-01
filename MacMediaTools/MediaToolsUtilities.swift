import Foundation

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
    case 4: return numbers[0] * 3600 + numbers[1] * 60 + numbers[2] + numbers[3] / 1000
    case 3: return numbers[0] * 60 + numbers[1] + numbers[2] / 1000
    case 2: return numbers[0] + numbers[1] / 1000
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
