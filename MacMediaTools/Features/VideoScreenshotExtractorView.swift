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
    @State private var intervalString: String = "1.000"
    @State private var outputFormat: VideoScreenshotExtractor.ExtractionSettings.OutputFormat = .png
    @State private var enableQualityCheck: Bool = true
    @State private var qualityThreshold: Double = 0.85
    @State private var enableDuplicateFilter: Bool = false
    @State private var duplicateThreshold: Double = 0.15

    // 输出路径
    @State private var outputDirectory: URL?

    // 线程安全的提取控制（供 actor 在后台线程安全读取）
    private final class ExtractionControl: @unchecked Sendable {
        var isPaused = false
        var shouldCancel = false
    }

    // 提取状态
    @State private var isProcessing = false
    @State private var isPaused = false
    @State private var shouldCancel = false
    @State private var progress: Int = 0
    @State private var totalFrames: Int = 0
    @State private var statusMessage = ""
    @State private var estimatedRemainingTime: TimeInterval?
    private let extractionControl = ExtractionControl()
    @State private var expectedFrameCount: Int = 0

    // 结果展示
    @State private var extractionResult: VideoScreenshotExtractor.ExtractionResult?
    @State private var filterMode: VideoScreenshotExtractor.FilterMode = .all
    @State private var selectedFrame: VideoScreenshotExtractor.ExtractedFrame?

    // 错误处理
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var showSaveSuccess = false
    @State private var saveSuccessPath = ""
    @State private var showFrameCountWarning = false

    // 快捷键支持
    @FocusState private var focusedField: String?

    private var displayedFrames: [VideoScreenshotExtractor.ExtractedFrame] {
        guard let result = extractionResult else { return [] }
        return filterMode.frames(from: result)
    }

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
        .alert("提取完成", isPresented: $showSaveSuccess) {
            Button("打开目录") {
                if let path = saveSuccessPath.isEmpty ? nil : saveSuccessPath {
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                }
            }
            Button("确定", role: .cancel) { }
        } message: {
            Text("截图已保存到 \(saveSuccessPath)")
        }
        .alert("截图数量过多", isPresented: $showFrameCountWarning) {
            Button("忽略，继续执行") {
                beginExtraction(skipWarning: true)
            }
            Button("返回，进行修改", role: .cancel) { }
        } message: {
            Text("截图数量为 \(expectedFrameCount)，是否需要增加间隔或缩短区段？")
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
        .onChange(of: startTime) { newValue in
            startTimeString = formatTime(newValue)
        }
        .onChange(of: endTime) { newValue in
            endTimeString = formatTime(newValue)
        }
        .onChange(of: focusedField) { newValue in
            guard newValue == nil else { return }
            // 焦点离开任意字段时，同步解析字符串到实际值
            // 间隔字段
            if let value = Double(intervalString.replacingOccurrences(of: "s", with: "").trimmingCharacters(in: .whitespaces)) {
                let clamped = max(0.001, min(60, value))
                if clamped != interval {
                    interval = clamped
                    intervalString = String(format: "%.3f", interval)
                }
            }
            // 开始/结束时间字段
            if let parsed = parseTimeString(startTimeString) {
                let clamped = max(0, min(parsed, videoDuration - 0.1))
                if clamped != startTime { startTime = clamped }
            }
            if let parsed = parseTimeString(endTimeString) {
                let clamped = max(startTime + 0.1, min(parsed, videoDuration))
                if clamped != endTime { endTime = clamped }
            }
        }
    }

    private var sidebarPanel: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("视频导入")
                        .font(.headline)

                    OpenPanelButton(
                        title: "选择视频文件",
                        mode: .file(allowedTypes: [
                            .movie, .mpeg4Movie, .quickTimeMovie,
                            UTType("public.avi"),
                            UTType("public.flv"),
                            UTType("com.microsoft.wmv")
                        ].compactMap { $0 }, allowsMultipleSelection: false)
                    ) { urls in
                        if let url = urls.first {
                            Task { await loadVideo(url: url) }
                        }
                    }
                    .buttonStyle(.bordered)

                    if let videoURL = videoURL {
                        Text("已选择: \(videoURL.lastPathComponent)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
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
                            Slider(value: $interval, in: 0.001...60, step: 0.001)
                                .frame(maxWidth: .infinity)
                                .onChange(of: interval) { newValue in
                                    intervalString = String(format: "%.3f", newValue)
                                }
                            TextField("秒", text: $intervalString)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .focused($focusedField, equals: "interval")
                                .onSubmit {
                                    if let value = Double(intervalString.replacingOccurrences(of: "s", with: "").trimmingCharacters(in: .whitespaces)) {
                                        let clamped = max(0.001, min(60, value))
                                        interval = clamped
                                        intervalString = String(format: "%.3f", interval)
                                    }
                                }
                            Text("秒")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
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
                                Text("阈值越高，保留的截图越多")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.leading, 12)
                        }

                        Toggle("内容去重", isOn: $enableDuplicateFilter)

                        if enableDuplicateFilter {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("相似度阈值: \(String(format: "%.0f", duplicateThreshold * 100))%")
                                    .font(.system(size: 12))
                                Slider(value: $duplicateThreshold, in: 0.01...1, step: 0.01)
                                Text("阈值越低，判定为相似的条件越严格")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.leading, 12)
                        }
                    }
                }

VStack(alignment: .leading, spacing: 8) {
            Text("输出路径")
                .font(.headline)

            OpenPanelButton(title: "选择导出目录", mode: .folder) { urls in
                outputDirectory = urls.first
                // Save bookmark for the selected directory
                if let dir = urls.first {
                    Task {
                        await SecurityBookmarkStore.shared.saveBookmark(for: dir, key: "VideoScreenshotExtractorOutputDirectory")
                    }
                }
            }
            .buttonStyle(.bordered)

            if let outputDirectory = outputDirectory {
                Text(outputDirectory.path)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            } else {
                Text("请先选择导出目录")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }

                VStack(alignment: .leading, spacing: 8) {
                    Text("操作")
                        .font(.headline)

                    Button(isProcessing ? (isPaused ? "继续" : "暂停") : "开始提取") {
                        if isProcessing {
                            togglePause()
                        } else {
                            beginExtraction()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(videoURL == nil || outputDirectory == nil)

                    if isProcessing {
                        Button("取消") {
                            shouldCancel = true
                            extractionControl.shouldCancel = true
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.red)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.visible)
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
                            .foregroundStyle(.white)
                            .cornerRadius(8)
                            .allowsHitTesting(true)
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "film")
                                    .font(.system(size: 64))
                                    .foregroundStyle(.secondary)

                                Text("请选择视频文件")
                                    .foregroundStyle(.secondary)
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
                                .foregroundStyle(.secondary)
                            TextField("00:00.000", text: $startTimeString)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                                .focused($focusedField, equals: "startTime")
                                .onSubmit { parseStartTime(startTimeString) }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("结束时间")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            TextField("00:00.000", text: $endTimeString)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                                .focused($focusedField, equals: "endTime")
                                .onSubmit { parseEndTime(endTimeString) }
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
                                Text("预计剩余: \(formatDurationChinese(remaining))")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 提取结果：4种筛选模式
                if let result = extractionResult {
                    VStack(spacing: 12) {
                        HStack {
                            Text("筛选结果")
                                .font(.headline)
                            Spacer()
                            Button("保存") {
                                saveCurrentFrames(result: result)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(displayedFrames.isEmpty)
                        }

                        // 4种模式卡片
                        HStack(spacing: 8) {
                            ForEach(VideoScreenshotExtractor.FilterMode.allCases) { mode in
                                let count = mode.frames(from: result).count
                                Button {
                                    filterMode = mode
                                } label: {
                                    VStack(spacing: 2) {
                                        Text(mode.rawValue)
                                            .font(.system(size: 12, weight: filterMode == mode ? .semibold : .regular))
                                        Text("\(count) 帧")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(filterMode == mode ? Color.blue : .primary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(filterMode == mode ? Color.blue.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(filterMode == mode ? Color.blue : Color.gray.opacity(0.3), lineWidth: filterMode == mode ? 2 : 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.bottom, 4)

                    ThumbnailPreviewPanel(
                        frames: displayedFrames,
                        selectedFrame: $selectedFrame
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 16)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.visible)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Video Selection

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

    private func beginExtraction(skipWarning: Bool = false) {
        // 从文本字段同步参数（用户可能未按 Enter 确认）
        if let parsedStart = parseTimeString(startTimeString) {
            startTime = max(0, min(parsedStart, videoDuration - 0.1))
        }
        if let parsedEnd = parseTimeString(endTimeString) {
            endTime = max(startTime + 0.1, min(parsedEnd, videoDuration))
        }
        if let parsedInterval = Double(intervalString.replacingOccurrences(of: "s", with: "").trimmingCharacters(in: .whitespaces)) {
            interval = max(0.001, min(60, parsedInterval))
            intervalString = String(format: "%.3f", interval)
        }

        let timeRange = endTime - startTime
        expectedFrameCount = max(1, Int(timeRange / interval) + 1)

        // 截图数量过多时弹窗警告
        if expectedFrameCount > 500 && !skipWarning {
            showFrameCountWarning = true
            return
        }

        Task {
            guard await WorkManager.shared.requestStart(.keyFrameExtract) else { return }
            isProcessing = true
            defer {
                isProcessing = false
                WorkManager.shared.finishWork(.keyFrameExtract)
            }
            await extractScreenshots()
        }
    }

    private func extractScreenshots() async {
        guard let videoURL = videoURL, let outputDirectory = outputDirectory else {
            return
        }

        // 从文本字段同步参数（用户可能未按 Enter 确认）
        if let parsedStart = parseTimeString(startTimeString) {
            startTime = max(0, min(parsedStart, videoDuration - 0.1))
        }
        if let parsedEnd = parseTimeString(endTimeString) {
            endTime = max(startTime + 0.1, min(parsedEnd, videoDuration))
        }
        if let parsedInterval = Double(intervalString.replacingOccurrences(of: "s", with: "").trimmingCharacters(in: .whitespaces)) {
            interval = max(0.001, min(60, parsedInterval))
            intervalString = String(format: "%.3f", interval)
        }

        isProcessing = true
        isPaused = false
        shouldCancel = false
        extractionControl.isPaused = false
        extractionControl.shouldCancel = false
        progress = 0
        extractionResult = nil
        
        let timeRange = endTime - startTime
        expectedFrameCount = max(1, Int(timeRange / interval) + 1)

        let settings = VideoScreenshotExtractor.ExtractionSettings(
            startTime: startTime,
            endTime: endTime,
            interval: interval,
            outputFormat: outputFormat,
            enableQualityCheck: enableQualityCheck,
            qualityThreshold: qualityThreshold,
            enableDuplicateFilter: enableDuplicateFilter,
            duplicateThreshold: duplicateThreshold
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
                pauseHandler: { self.extractionControl.isPaused },
                cancelHandler: { self.extractionControl.shouldCancel }
            )

            await MainActor.run {
                self.extractionResult = result
                self.filterMode = .all
                self.isProcessing = false

                logManager.logExtractionComplete(
                    frameCount: result.allFrames.count,
                    duration: 0
                )

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
        extractionControl.isPaused = isPaused
    }

    // MARK: - Output Management

    private func saveCurrentFrames(result: VideoScreenshotExtractor.ExtractionResult) {
        let saveDir = result.outputDirectory

        Task {
            do {
                if !FileManager.default.fileExists(atPath: saveDir.path) {
                    try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
                }
                
                // Start accessing the security-scoped resource
                let started = SecurityBookmarkStore.shared.startAccessing(saveDir)
                defer {
                    if started {
                        SecurityBookmarkStore.shared.stopAccessing(saveDir)
                    }
                }
                
                let savedURLs = try await VideoScreenshotExtractor.shared.saveFrames(
                    displayedFrames, to: saveDir, format: outputFormat
                )
                await MainActor.run {
                    // Use the resolved directory path for showing in Finder
                    saveSuccessPath = saveDir.path
                    showSaveSuccess = true
                    logManager.logExtractionComplete(frameCount: savedURLs.count, duration: 0)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "保存失败: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }

    // MARK: - Utility Methods

    private func formatDurationChinese(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else {
            return "计算中..."
        }
        let clampedSeconds = max(0, seconds)
        let s = Int(clampedSeconds) % 60
        let m = Int(clampedSeconds) / 60
        return String(format: "%d分%d秒", m, s)
    }
}

