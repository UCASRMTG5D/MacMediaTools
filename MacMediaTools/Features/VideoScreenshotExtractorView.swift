import SwiftUI
import AVFoundation
import AVKit
import UniformTypeIdentifiers

struct VideoScreenshotExtractorView: View {
    // 视频相关状态
    @State private var videoURL: URL?
    @State private var videoDuration: Double = 0
    @State private var metadata: VideoScreenshotExtractor.VideoMetadata?
    @State private var currentTime: Double = 0
    @State private var isPlaying = false
    @State private var previewPlayer: AVPlayer?
    
    // 时间范围选择
    @State private var startTime: Double = 0
    @State private var endTime: Double = 0
    @State private var startTimeString: String = "00:00.000"
    @State private var endTimeString: String = "00:00.000"
    
    // 提取设置
    @State private var interval: Double = 1.0
    @State private var outputFormat: VideoScreenshotExtractor.ExtractionSettings.OutputFormat = .png
    @State private var enableQualityCheck: Bool = true
    @State private var qualityThreshold: Double = 0.85
    
    // 输出路径
    @State private var outputDirectory: URL?
    
    // 提取状态
    @State private var isProcessing = false
    @State private var isPaused = false
    @State private var shouldCancel = false
    @State private var progress: Int = 0
    @State private var totalFrames: Int = 0
    @State private var statusMessage = ""
    @State private var estimatedRemainingTime: TimeInterval?
    
    // 结果展示
    @State private var extractedFrames: [VideoScreenshotExtractor.ExtractedFrame] = []
    @State private var selectedFrame: VideoScreenshotExtractor.ExtractedFrame?
    
    // 错误处理
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var showSuccess = false
    @State private var successMessage = ""
    
    // 快捷键支持
    @FocusState private var focusedField: String?
    
    // 操作日志
    @ObservedObject private var logManager = OperationLogManager.shared
    @State private var playbackEndObserver: NSObjectProtocol?
    
    var body: some View {
        HSplitView {
            sidebarPanel
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
            
            detailPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1000, minHeight: 700)
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("提取完成", isPresented: $showSuccess) {
            Button("打开目录") {
                if let outputDirectory = extractedFrames.first?.filePath?.deletingLastPathComponent() {
                    NSWorkspace.shared.open(outputDirectory)
                }
            }
            Button("确定", role: .cancel) { }
        } message: {
            Text(successMessage)
        }
        .onAppear {
            // 尝试恢复上次任务
            if let lastTask = OperationLogManager.shared.loadLastTaskState() {
                // 可以在这里添加恢复任务的逻辑
            }
        }
        .onDisappear {
            if let playbackEndObserver {
                NotificationCenter.default.removeObserver(playbackEndObserver)
                self.playbackEndObserver = nil
            }
            previewPlayer?.pause()
        }
        .modifier(KeyboardShortcutsModifier(
            isPlaying: $isPlaying,
            videoURL: videoURL,
            currentTime: $currentTime,
            videoDuration: videoDuration,
            togglePlay: togglePlay,
            seekToTime: seekToTime
        ))
    }

    private var sidebarPanel: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("视频导入")
                        .font(.headline)
                    
                    Button("选择视频文件") {
                        selectVideo()
                    }
                    .buttonStyle(.bordered)
                    
                    if let videoURL = videoURL {
                        Text("已选择: \(videoURL.lastPathComponent)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("视频信息")
                        .font(.headline)
                    
                    if let metadata = metadata {
                        Text("时长: \(formatTime(metadata.duration))")
                        Text("分辨率: \(metadata.width) × \(metadata.height)")
                        Text("帧率: \(metadata.frameRate) fps")
                        Text("编码: \(metadata.codec)")
                    } else {
                        Text("请先选择视频")
                            .foregroundColor(.secondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("提取设置")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("时间间隔")
                            .font(.system(size: 13))
                            .fontWeight(.medium)
                        
                        HStack(alignment: .center, spacing: 8) {
                            Slider(value: $interval, in: 0.1...60, step: 0.1)
                                .frame(maxWidth: .infinity)
                            Text("\(String(format: "%.1f", interval))s")
                                .font(.system(size: 12))
                                .frame(width: 50, alignment: .trailing)
                        }
                        
                        Text("输出格式")
                            .font(.system(size: 13))
                            .fontWeight(.medium)
                        
                        Picker("", selection: $outputFormat) {
                            ForEach(VideoScreenshotExtractor.ExtractionSettings.OutputFormat.allCases, id: \.self) { format in
                                Text(format.rawValue)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                        
                        Toggle("启用质量检查", isOn: $enableQualityCheck)
                        
                        if enableQualityCheck {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("质量阈值: \(String(format: "%.0f", qualityThreshold * 100))%")
                                    .font(.system(size: 12))
                                Slider(value: $qualityThreshold, in: 0...1, step: 0.05)
                            }
                            .padding(.leading, 12)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("输出路径")
                        .font(.headline)
                    
                    Button("选择导出目录") {
                        selectOutputDirectory()
                    }
                    .buttonStyle(.bordered)
                    
                    if let outputDirectory = outputDirectory {
                        Text(outputDirectory.path)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("操作")
                        .font(.headline)
                    
                    Button(isProcessing ? (isPaused ? "继续" : "暂停") : "开始提取") {
                        if isProcessing {
                            togglePause()
                        } else {
                            Task { await extractScreenshots() }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(videoURL == nil || outputDirectory == nil)
                    
                    if isProcessing {
                        Button("取消") {
                            shouldCancel = true
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.visible)
        .navigationTitle("截图提取")
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var detailPanel: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("视频预览")
                        .font(.headline)
                    
                    ZStack(alignment: .bottomLeading) {
                        if let videoURL = videoURL {
                            VideoPlayer(player: previewPlayer)
                                .frame(height: 300)
                                .frame(maxWidth: .infinity)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                            
                            HStack(spacing: 16) {
                                Button(action: togglePlay) {
                                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 24))
                                }
                                .buttonStyle(.borderless)
                                
                                Text(formatTime(currentTime))
                                    .font(.system(size: 14))
                            }
                            .padding(12)
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .allowsHitTesting(true)
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "film")
                                    .font(.system(size: 64))
                                    .foregroundColor(.secondary)
                                
                                Text("请选择视频文件")
                                    .foregroundColor(.secondary)
                            }
                            .frame(height: 300)
                            .frame(maxWidth: .infinity)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("时间范围选择")
                        .font(.headline)
                    
                    VideoProgressSlider(
                        startTime: $startTime,
                        endTime: $endTime,
                        currentTime: $currentTime,
                        duration: $videoDuration,
                        onTimeChange: seekToTime
                    )
                    .frame(height: 40)
                    .frame(maxWidth: .infinity)
                    
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("开始时间")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            TextField("00:00.000", text: $startTimeString)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                                .focused($focusedField, equals: "startTime")
                                .onChange(of: startTimeString) { parseStartTime($0) }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("结束时间")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            TextField("00:00.000", text: $endTimeString)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                                .focused($focusedField, equals: "endTime")
                                .onChange(of: endTimeString) { parseEndTime($0) }
                        }
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    HStack(spacing: 8) {
                        Button("前10秒") { setRange(0, min(10, videoDuration)) }
                        Button("前30秒") { setRange(0, min(30, videoDuration)) }
                        Button("前1分钟") { setRange(0, min(60, videoDuration)) }
                        Button("全视频") { setRange(0, videoDuration) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                if isProcessing {
                    VStack(spacing: 8) {
                        ProgressView(value: Double(progress), total: Double(totalFrames))
                            .progressViewStyle(.linear)
                        
                        HStack {
                            Text(statusMessage)
                                .font(.system(size: 14))
                            
                            if let remaining = estimatedRemainingTime {
                                Text("预计剩余: \(formatDuration(remaining))")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                ThumbnailPreviewPanel(
                    frames: extractedFrames,
                    selectedFrame: $selectedFrame,
                    onExportZip: exportAsZip
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 16)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.visible)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Video Selection
    
    private func selectVideo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .movie, .mpeg4Movie, .quickTimeMovie,
            UTType("public.avi"), UTType("public.flv"), UTType("com.microsoft.wmv")
        ].compactMap { $0 }
        
        if panel.runModal() == .OK, let url = panel.urls.first {
            Task { await loadVideo(url: url) }
        }
    }
    
    private func loadVideo(url: URL) async {
        do {
            let isValid = await VideoScreenshotExtractor.shared.validateVideoFormat(url: url)
            guard isValid else {
                errorMessage = "不支持的视频格式，请选择 MP4、MOV、AVI、FLV、WMV 等格式"
                showError = true
                return
            }
            
            let metadata = try await VideoScreenshotExtractor.shared.getVideoMetadata(url: url)
            
            await MainActor.run {
                if let playbackEndObserver {
                    NotificationCenter.default.removeObserver(playbackEndObserver)
                    self.playbackEndObserver = nil
                }
                previewPlayer?.pause()

                self.videoURL = url
                self.metadata = metadata
                self.videoDuration = metadata.duration
                self.startTime = 0
                self.endTime = metadata.duration
                self.startTimeString = formatTime(0)
                self.endTimeString = formatTime(metadata.duration)
                self.currentTime = 0
                
                // 初始化预览播放器
                previewPlayer = AVPlayer(url: url)
                previewPlayer?.actionAtItemEnd = .pause
                
                logManager.logVideoInfo(url: url, metadata: metadata)
            }
        } catch {
            await MainActor.run {
                errorMessage = "加载视频失败: \(error.localizedDescription)"
                showError = true
            }
        }
    }
    
    // MARK: - Playback Control
    
    private func togglePlay() {
        if isPlaying {
            previewPlayer?.pause()
        } else {
            if let playbackEndObserver {
                NotificationCenter.default.removeObserver(playbackEndObserver)
                self.playbackEndObserver = nil
            }

            // 只在选定范围内播放
            previewPlayer?.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
            previewPlayer?.play()
            
            // 设置播放结束处理
            playbackEndObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: previewPlayer?.currentItem,
                queue: .main
            ) { _ in
                if currentTime >= endTime {
                    previewPlayer?.pause()
                    previewPlayer?.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
                    isPlaying = false
                    if let playbackEndObserver {
                        NotificationCenter.default.removeObserver(playbackEndObserver)
                        self.playbackEndObserver = nil
                    }
                }
            }
        }
        isPlaying.toggle()
    }
    
    private func seekToTime(_ time: Double) {
        currentTime = time
        previewPlayer?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }
    
    // MARK: - Time Range Management
    
    private func parseStartTime(_ string: String) {
        if let time = parseTimeString(string) {
            startTime = max(0, min(time, endTime - 0.1))
        }
    }
    
    private func parseEndTime(_ string: String) {
        if let time = parseTimeString(string) {
            endTime = max(startTime + 0.1, min(time, videoDuration))
        }
    }
    
    private func setRange(_ start: Double, _ end: Double) {
        startTime = start
        endTime = end
        startTimeString = formatTime(start)
        endTimeString = formatTime(end)
    }
    
    // MARK: - Screenshot Extraction
    
    private func extractScreenshots() async {
        guard let videoURL = videoURL, let outputDirectory = outputDirectory else {
            return
        }
        
        isProcessing = true
        isPaused = false
        shouldCancel = false
        progress = 0
        extractedFrames.removeAll()
        
        let settings = VideoScreenshotExtractor.ExtractionSettings(
            startTime: startTime,
            endTime: endTime,
            interval: interval,
            outputFormat: outputFormat,
            enableQualityCheck: enableQualityCheck,
            qualityThreshold: qualityThreshold
        )
        
        logManager.logExtractionSettings(
            startTime: startTime,
            endTime: endTime,
            interval: interval
        )
        
        do {
            let result = try await VideoScreenshotExtractor.shared.extractScreenshots(
                videoURL: videoURL,
                outputDirectory: outputDirectory,
                settings: settings,
                progressHandler: { progressInfo in
                    Task { @MainActor in
                        self.progress = progressInfo.current
                        self.totalFrames = progressInfo.total
                        self.statusMessage = progressInfo.status
                        self.estimatedRemainingTime = progressInfo.estimatedRemainingTime
                        
                        logManager.logExtractionProgress(
                            current: progressInfo.current,
                            total: progressInfo.total
                        )
                    }
                },
                pauseHandler: { self.isPaused },
                cancelHandler: { self.shouldCancel }
            )
            
            await MainActor.run {
                self.extractedFrames = result.extractedFrames
                self.isProcessing = false
                self.successMessage = "成功提取 \(result.extractedFrames.count) 帧截图，已保存到 \(result.outputDirectory.path)"
                self.showSuccess = true
                
                logManager.logExtractionComplete(
                    frameCount: result.extractedFrames.count,
                    duration: 0 // 可以从日志中获取实际耗时
                )
                
                // 清除任务状态
                OperationLogManager.shared.clearLastTaskState()
            }
        } catch {
            await MainActor.run {
                self.isProcessing = false
                self.errorMessage = error.localizedDescription
                self.showError = true
                
                logManager.logError(error)
            }
        }
    }
    
    private func togglePause() {
        isPaused.toggle()
    }
    
    // MARK: - Output Management
    
    private func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.urls.first {
            outputDirectory = url
        }
    }
    
    private func exportAsZip() {
        guard !extractedFrames.isEmpty else {
            return
        }
        
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.title = "保存ZIP文件"
        panel.nameFieldStringValue = "screenshots.zip"
        
        if panel.runModal() == .OK, let url = panel.url {
            let files = extractedFrames.compactMap { $0.filePath }
            
            Task {
                do {
                    try await VideoScreenshotExtractor.shared.exportAsZip(files: files, outputURL: url)
                    NSWorkspace.shared.open(url.deletingLastPathComponent())
                } catch {
                    errorMessage = "打包失败: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
    
    // MARK: - Utility Methods
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else {
            return "计算中..."
        }
        let clampedSeconds = max(0, seconds)
        let s = Int(clampedSeconds) % 60
        let m = Int(clampedSeconds) / 60
        return String(format: "%d分%d秒", m, s)
    }
}

struct ThumbnailPreviewPanel: View {
    let frames: [VideoScreenshotExtractor.ExtractedFrame]
    @Binding var selectedFrame: VideoScreenshotExtractor.ExtractedFrame?
    var onExportZip: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("提取结果")
                    .font(.headline)
                
                Text("\(frames.count) 帧")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("导出为ZIP") {
                    onExportZip?()
                }
                .disabled(frames.isEmpty)
                .buttonStyle(.bordered)
            }
            
            if frames.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "image")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("暂无提取结果")
                        .foregroundColor(.secondary)
                }
                .frame(height: 300)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                        ForEach(frames.indices, id: \.self) { index in
                            FrameThumbnail(
                                frame: frames[index],
                                index: index,
                                isSelected: selectedFrame?.time == frames[index].time,
                                onSelect: { selectedFrame = frames[index] }
                            )
                        }
                    }
                }
                .frame(maxHeight: 400)
                .scrollIndicators(.visible)
            }
            
            if let selectedFrame = selectedFrame {
                Divider()
                
                HStack(alignment: .top, spacing: 16) {
                    Image(nsImage: NSImage(cgImage: selectedFrame.image, size: CGSize(width: selectedFrame.image.width, height: selectedFrame.image.height)))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .cornerRadius(8)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("帧 \(((frames.firstIndex { $0.time == selectedFrame.time } ?? 0) + 1))")
                            .font(.headline)
                        
                        HStack(spacing: 16) {
                            VStack(alignment: .leading) {
                                Text("时间")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Text(formatTime(selectedFrame.time))
                            }
                            
                            VStack(alignment: .leading) {
                                Text("质量")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.2f%%", selectedFrame.qualityScore * 100))
                                    .foregroundColor(selectedFrame.qualityScore >= 0.8 ? .green : selectedFrame.qualityScore >= 0.5 ? .orange : .red)
                            }
                            
                            VStack(alignment: .leading) {
                                Text("来源")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Text(selectedFrame.isReplaced ? "智能替换" : "原始帧")
                                    .foregroundColor(selectedFrame.isReplaced ? .orange : .gray)
                            }
                        }
                        
                        if let filePath = selectedFrame.filePath {
                            HStack {
                                Text("保存路径")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                
                                Text(filePath.lastPathComponent)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                            }
                            
                            Button("在访达中显示") {
                                NSWorkspace.shared.activateFileViewerSelecting([filePath])
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
}

struct FrameThumbnail: View {
    let frame: VideoScreenshotExtractor.ExtractedFrame
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        VStack(alignment: .leading) {
            Image(nsImage: NSImage(cgImage: frame.image, size: CGSize(width: frame.image.width, height: frame.image.height)))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 80)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                )
                .overlay(
                    frame.isReplaced ? Image(systemName: "arrow.refresh")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                        .padding(2)
                        .background(Color.white.opacity(0.8))
                        .cornerRadius(2)
                        .offset(x: 4, y: 4) : nil
                )
            
            Text(formatTime(frame.time))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            HStack {
                Text("\(index + 1)")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
                
                Spacer()
                
                if frame.qualityScore < 0.8 {
                    Image(systemName: "alert.triangle")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                }
            }
        }
        .onTapGesture {
            onSelect()
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let s = Int(seconds) % 60
        let m = Int(seconds) / 60 % 60
        return String(format: "%02d:%02d", m, s)
    }
}

struct KeyboardShortcutsModifier: ViewModifier {
    @Binding var isPlaying: Bool
    let videoURL: URL?
    @Binding var currentTime: Double
    let videoDuration: Double
    let togglePlay: () -> Void
    let seekToTime: (Double) -> Void
    
    @State private var eventMonitor: Any?
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    handleKeyEvent(event)
                    return event
                }
            }
            .onDisappear {
                if let monitor = eventMonitor {
                    NSEvent.removeMonitor(monitor)
                    eventMonitor = nil
                }
            }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        guard videoURL != nil else { return }
        
        switch event.keyCode {
        case 49: // Space
            if isPlaying || videoURL != nil {
                togglePlay()
            }
        case 123: // Left arrow
            seekToTime(max(0, currentTime - 1))
        case 124: // Right arrow
            seekToTime(min(videoDuration, currentTime + 1))
        default:
            break
        }
    }
}
