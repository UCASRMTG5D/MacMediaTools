import Foundation

class OperationLogManager: ObservableObject {
    static let shared = OperationLogManager()
    
    @Published var logs: [LogEntry] = []
    private let logQueue = DispatchQueue(label: "com.example.VideoScreenshotExtractor.logQueue")
    
    struct LogEntry: Identifiable, Codable {
        let id = UUID()
        let timestamp: Date
        let level: LogLevel
        let message: String
        let details: String?
        
        enum CodingKeys: String, CodingKey {
            case timestamp, level, message, details
        }
        
        enum LogLevel: String, Codable {
            case info = "INFO"
            case warning = "WARNING"
            case error = "ERROR"
            case success = "SUCCESS"
            
            var color: String {
                switch self {
                case .info: return "#007AFF"
                case .warning: return "#FF9500"
                case .error: return "#FF3B30"
                case .success: return "#34C759"
                }
            }
        }
    }
    
    struct TaskState: Codable {
        let videoURL: String
        let startTime: Double
        let endTime: Double
        let interval: Double
        let outputDirectory: String
        let progress: Int
        let totalFrames: Int
        let timestamp: Date
    }
    
    private init() {
        loadLogs()
    }
    
    func addLog(_ message: String, level: LogEntry.LogLevel = .info, details: String? = nil) {
        logQueue.async { [weak self] in
            let entry = LogEntry(
                timestamp: Date(),
                level: level,
                message: message,
                details: details
            )
            
            DispatchQueue.main.async {
                self?.logs.insert(entry, at: 0)
                
                // 保留最近1000条日志
                if self?.logs.count ?? 0 > 1000 {
                    self?.logs.removeLast()
                }
            }
            
            self?.saveLogs()
        }
    }
    
    func logVideoInfo(url: URL, metadata: VideoScreenshotExtractor.VideoMetadata) {
        addLog("加载视频: \(url.lastPathComponent)", level: .info)
        addLog("时长: \(formatTime(metadata.duration)) | 分辨率: \(metadata.width)x\(metadata.height) | 帧率: \(metadata.frameRate)fps", level: .info)
    }
    
    func logExtractionSettings(startTime: Double, endTime: Double, interval: Double) {
        addLog("提取设置: 开始=\(formatTime(startTime)), 结束=\(formatTime(endTime)), 间隔=\(interval)s", level: .info)
    }
    
    func logExtractionProgress(current: Int, total: Int) {
        let progress = Double(current) / Double(total) * 100
        addLog("提取进度: \(current)/\(total) (\(String(format: "%.1f", progress))%)", level: .info)
    }
    
    func logExtractionComplete(frameCount: Int, duration: TimeInterval) {
        addLog("提取完成: \(frameCount) 帧，耗时 \(String(format: "%.2f", duration)) 秒", level: .success)
    }
    
    func logError(_ error: Error) {
        addLog("错误: \(error.localizedDescription)", level: .error, details: error.localizedDescription)
    }
    
    func logWarning(_ message: String) {
        addLog(message, level: .warning)
    }
    
    func saveTaskState(videoURL: URL, startTime: Double, endTime: Double, interval: Double, outputDirectory: URL, progress: Int, totalFrames: Int) {
        let state = TaskState(
            videoURL: videoURL.path,
            startTime: startTime,
            endTime: endTime,
            interval: interval,
            outputDirectory: outputDirectory.path,
            progress: progress,
            totalFrames: totalFrames,
            timestamp: Date()
        )
        
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: "LastExtractionTask")
        }
    }
    
    func loadLastTaskState() -> TaskState? {
        if let data = UserDefaults.standard.data(forKey: "LastExtractionTask") {
            return try? JSONDecoder().decode(TaskState.self, from: data)
        }
        return nil
    }
    
    func clearLastTaskState() {
        UserDefaults.standard.removeObject(forKey: "LastExtractionTask")
    }
    
    private func saveLogs() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        if let data = try? encoder.encode(logs) {
            UserDefaults.standard.set(data, forKey: "VideoScreenshotExtractorLogs")
        }
    }
    
    private func loadLogs() {
        if let data = UserDefaults.standard.data(forKey: "VideoScreenshotExtractorLogs") {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            if let savedLogs = try? decoder.decode([LogEntry].self, from: data) {
                logs = savedLogs
            }
        }
    }
    
    func clearLogs() {
        logQueue.async { [weak self] in
            DispatchQueue.main.async {
                self?.logs.removeAll()
            }
            self?.saveLogs()
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        let s = Int(seconds) % 60
        let m = Int(seconds) / 60 % 60
        let h = Int(seconds) / 3600
        
        if h > 0 {
            return String(format: "%d:%02d:%02d.%03d", h, m, s, ms)
        }
        return String(format: "%02d:%02d.%03d", m, s, ms)
    }
}