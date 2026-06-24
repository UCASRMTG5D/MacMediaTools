import AppKit
import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct AudioVideoEditorView: View {
    @State private var videoURL: URL?
    @State private var audioURL: URL?
    @State private var videoTrack: TrackItem?
    @State private var audioTrack: TrackItem?
    
    @State private var videoOffset: Double = 0
    @State private var audioOffset: Double = 0
    @State private var videoSpeed: Double = 1.0
    @State private var audioSpeed: Double = 1.0
    
    @State private var timelineScale: Double = 1.0
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var previewPlayer: AVPlayer?
    
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var outputURL: URL?
    @State private var errorMessage: String?
    @State private var successMessage: String?
    
    @State private var undoStack: [EditAction] = []
    @State private var redoStack: [EditAction] = []
    
    private let maxUndoSteps = 10
    
    struct TrackItem: Identifiable {
        let id = UUID()
        let url: URL
        let name: String
        let duration: Double
        let type: TrackType
        
        enum TrackType {
            case video
            case audio
        }
    }
    
    enum EditAction {
        case setVideo(URL?)
        case setAudio(URL?)
        case setVideoOffset(Double)
        case setAudioOffset(Double)
        case setVideoSpeed(Double)
        case setAudioSpeed(Double)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Text("音视频处理")
                    .font(.title2)
                
                Spacer()
                
                Button("撤销") {
                    undo()
                }
                .disabled(undoStack.isEmpty)
                
                Button("重做") {
                    redo()
                }
                .disabled(redoStack.isEmpty)
            }
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("导入文件")
                        .font(.headline)
                    
                    HStack(spacing: 12) {
                        OpenPanelButton(
                            title: "选择视频…",
                            mode: .file(allowedTypes: [.movie], allowsMultipleSelection: false)
                        ) { urls in
                            if let url = urls.first {
                                addAction(.setVideo(videoURL))
                                loadVideo(url)
                            }
                        }
                        .disabled(isExporting)
                        
                        if let videoTrack {
                            Button("移除") {
                                addAction(.setVideo(videoTrack.url))
                                self.videoTrack = nil
                                videoURL = nil
                            }
                            .foregroundColor(.red)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        OpenPanelButton(
                            title: "选择音频…",
                            mode: .file(allowedTypes: [.audio], allowsMultipleSelection: false)
                        ) { urls in
                            if let url = urls.first {
                                addAction(.setAudio(audioURL))
                                loadAudio(url)
                            }
                        }
                        .disabled(isExporting)
                        
                        if let audioTrack {
                            Button("移除") {
                                addAction(.setAudio(audioTrack.url))
                                self.audioTrack = nil
                                audioURL = nil
                            }
                            .foregroundColor(.red)
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("速度控制")
                        .font(.headline)
                    
                    HStack(spacing: 12) {
                        Text("视频速度")
                        Slider(value: $videoSpeed, in: 0.5...2.0, step: 0.1)
                            .frame(width: 150)
                            .disabled(isExporting)
                        Text("\(videoSpeed, specifier: "%.1f")x")
                            .monospaced()
                    }
                    
                    HStack(spacing: 12) {
                        Text("音频速度")
                        Slider(value: $audioSpeed, in: 0.5...2.0, step: 0.1)
                            .frame(width: 150)
                            .disabled(isExporting)
                        Text("\(audioSpeed, specifier: "%.1f")x")
                            .monospaced()
                    }
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("轨道编辑区")
                    .font(.headline)
                
                VStack(spacing: 4) {
                    if let videoTrack {
                        TrackRow(
                            title: "视频轨道",
                            name: videoTrack.name,
                            duration: videoTrack.duration,
                            offset: $videoOffset,
                            color: .blue
                        )
                    }
                    
                    if let audioTrack {
                        TrackRow(
                            title: "音频轨道",
                            name: audioTrack.name,
                            duration: audioTrack.duration,
                            offset: $audioOffset,
                            color: .green
                        )
                    }
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("时间轴")
                        .font(.headline)
                    
                    Button("-") {
                        timelineScale = max(0.5, timelineScale - 0.25)
                    }
                    .frame(width: 30)
                    
                    Text("\(timelineScale, specifier: "%.2f")x")
                        .monospaced()
                        .frame(width: 60)
                    
                    Button("+") {
                        timelineScale = min(4.0, timelineScale + 0.25)
                    }
                    .frame(width: 30)
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Button("起始对齐") {
                            alignTracks(to: .start)
                        }
                        .disabled(!canAlign)
                        
                        Button("结束对齐") {
                            alignTracks(to: .end)
                        }
                        .disabled(!canAlign)
                        
                        Button("同步对齐") {
                            alignTracks(to: .sync)
                        }
                        .disabled(!canAlign)
                    }
                }
                
                TimelineView(
                    videoTrack: videoTrack,
                    audioTrack: audioTrack,
                    videoOffset: videoOffset,
                    audioOffset: audioOffset,
                    scale: timelineScale,
                    currentTime: $currentTime
                )
                .frame(height: 80)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("预览")
                    .font(.headline)
                
                if let previewPlayer {
                    VideoPlayer(player: previewPlayer)
                        .frame(height: 240)
                        .cornerRadius(8)
                        .onDisappear {
                            previewPlayer.pause()
                        }
                } else {
                    Text("（预览区域）")
                        .frame(maxWidth: .infinity, minHeight: 240)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                }
                
                HStack(spacing: 12) {
                    Button(isPlaying ? "暂停" : "播放") {
                        togglePlayback()
                    }
                    .disabled(videoTrack == nil)
                    
                    Slider(value: $currentTime, in: 0...maxDuration)
                        .disabled(videoTrack == nil)
                    
                    Text(formatTime(currentTime))
                        .monospaced()
                        .frame(width: 60)
                }
            }
            
            Divider()
            
            HStack(spacing: 12) {
                OpenPanelButton(title: "选择输出目录…", mode: .folder) { urls in
                    if let url = urls.first {
                        let fileName = videoTrack?.name.components(separatedBy: ".").first ?? "merged"
                        outputURL = url.appendingPathComponent("\(fileName)_merged.mov")
                    }
                }
                .disabled(isExporting)
                
                Text(outputURL?.path ?? "未选择输出路径")
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                if isExporting {
                    ProgressView(value: exportProgress)
                        .frame(width: 150)
                    Text("\(Int(exportProgress * 100))%")
                } else {
                    Button("开始合并") {
                        Task { await mergeFiles() }
                    }
                    .disabled(!canMerge)
                }
                
                if let videoTrack {
                    Button("分离音频") {
                        Task { await extractAudio() }
                    }
                    .disabled(isExporting)
                }
                
                if let videoTrack {
                    Button("分离视频") {
                        Task { await extractVideo() }
                    }
                    .disabled(isExporting)
                }
            }
            
            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            }
            if let successMessage {
                Text(successMessage)
                    .foregroundColor(.green)
            }
            
            Spacer()
        }
        .padding()
    }
    
    private var canMerge: Bool {
        videoTrack != nil && audioTrack != nil && outputURL != nil && !isExporting
    }
    
    private var canAlign: Bool {
        videoTrack != nil && audioTrack != nil
    }
    
    private var maxDuration: Double {
        guard let videoTrack, let audioTrack else { return 0 }
        return max(videoTrack.duration / videoSpeed, audioTrack.duration / audioSpeed)
    }
    
    private func loadVideo(_ url: URL) {
        Task {
            do {
                let info = try await AudioVideoToolkit.shared.getTrackInfo(url: url)
                await MainActor.run {
                    videoURL = url
                    videoTrack = TrackItem(
                        url: url,
                        name: url.lastPathComponent,
                        duration: info.duration,
                        type: .video
                    )
                    previewPlayer = AVPlayer(url: url)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "加载视频失败：\(error.localizedDescription)"
                }
            }
        }
    }
    
    private func loadAudio(_ url: URL) {
        Task {
            do {
                let info = try await AudioVideoToolkit.shared.getTrackInfo(url: url)
                await MainActor.run {
                    audioURL = url
                    audioTrack = TrackItem(
                        url: url,
                        name: url.lastPathComponent,
                        duration: info.duration,
                        type: .audio
                    )
                }
            } catch {
                await MainActor.run {
                    errorMessage = "加载音频失败：\(error.localizedDescription)"
                }
            }
        }
    }
    
    private func alignTracks(to alignment: AlignmentType) {
        addAction(.setVideoOffset(videoOffset))
        addAction(.setAudioOffset(audioOffset))
        
        guard let videoTrack, let audioTrack else { return }
        
        switch alignment {
        case .start:
            videoOffset = 0
            audioOffset = 0
        case .end:
            let videoEndTime = videoTrack.duration / videoSpeed
            let audioEndTime = audioTrack.duration / audioSpeed
            if videoEndTime > audioEndTime {
                audioOffset = max(0, audioTrack.duration - (videoTrack.duration * audioSpeed / videoSpeed))
            } else {
                videoOffset = max(0, videoTrack.duration - (audioTrack.duration * videoSpeed / audioSpeed))
            }
        case .sync:
            videoOffset = 0
            audioOffset = 0
        }
    }
    
    enum AlignmentType {
        case start
        case end
        case sync
    }
    
    private func mergeFiles() async {
        guard let videoURL, let audioURL, let outputURL else { return }
        
        isExporting = true
        exportProgress = 0
        
        let settings = AudioVideoToolkit.MergeSettings(
            videoStartOffset: videoOffset,
            audioStartOffset: audioOffset,
            videoSpeed: videoSpeed,
            audioSpeed: audioSpeed
        )
        
        do {
            try await AudioVideoToolkit.shared.mergeAudioVideo(
                videoURL: videoURL,
                audioURL: audioURL,
                outputURL: outputURL,
                settings: settings
            ) { progress in
                DispatchQueue.main.async {
                    self.exportProgress = progress
                }
            }
            
            await MainActor.run {
                successMessage = "合并成功！"
                errorMessage = nil
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            }
        } catch {
            await MainActor.run {
                errorMessage = "合并失败：\(error.localizedDescription)"
            }
        }
        
        await MainActor.run {
            isExporting = false
        }
    }
    
    private func extractAudio() async {
        guard let videoURL else { return }
        
        isExporting = true
        exportProgress = 0
        
        let baseName = videoURL.deletingPathExtension().lastPathComponent
        let output = videoURL.deletingLastPathComponent().appendingPathComponent("\(baseName).m4a")
        
        do {
            try await AudioVideoToolkit.shared.extractAudio(
                from: videoURL,
                outputURL: output
            ) { progress in
                DispatchQueue.main.async {
                    self.exportProgress = progress
                }
            }
            
            await MainActor.run {
                successMessage = "音频分离成功！"
                errorMessage = nil
                NSWorkspace.shared.activateFileViewerSelecting([output])
            }
        } catch {
            await MainActor.run {
                errorMessage = "分离失败：\(error.localizedDescription)"
            }
        }
        
        await MainActor.run {
            isExporting = false
        }
    }
    
    private func extractVideo() async {
        guard let videoURL else { return }
        
        isExporting = true
        exportProgress = 0
        
        let baseName = videoURL.deletingPathExtension().lastPathComponent
        let output = videoURL.deletingLastPathComponent().appendingPathComponent("\(baseName)_novideo.mov")
        
        do {
            try await AudioVideoToolkit.shared.extractVideo(
                from: videoURL,
                outputURL: output
            ) { progress in
                DispatchQueue.main.async {
                    self.exportProgress = progress
                }
            }
            
            await MainActor.run {
                successMessage = "视频分离成功！"
                errorMessage = nil
                NSWorkspace.shared.activateFileViewerSelecting([output])
            }
        } catch {
            await MainActor.run {
                errorMessage = "分离失败：\(error.localizedDescription)"
            }
        }
        
        await MainActor.run {
            isExporting = false
        }
    }
    
    private func togglePlayback() {
        guard let previewPlayer else { return }
        
        if isPlaying {
            previewPlayer.pause()
        } else {
            previewPlayer.play()
        }
        isPlaying.toggle()
    }
    
    private func addAction(_ action: EditAction) {
        undoStack.append(action)
        if undoStack.count > maxUndoSteps {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }
    
    private func undo() {
        guard let action = undoStack.popLast() else { return }
        
        redoStack.append(action)
        
        switch action {
        case .setVideo(let url):
            if let url {
                loadVideo(url)
            } else {
                videoTrack = nil
                videoURL = nil
            }
        case .setAudio(let url):
            if let url {
                loadAudio(url)
            } else {
                audioTrack = nil
                audioURL = nil
            }
        case .setVideoOffset(let offset):
            videoOffset = offset
        case .setAudioOffset(let offset):
            audioOffset = offset
        case .setVideoSpeed(let speed):
            videoSpeed = speed
        case .setAudioSpeed(let speed):
            audioSpeed = speed
        }
    }
    
    private func redo() {
        guard let action = redoStack.popLast() else { return }
        
        undoStack.append(action)
        
        switch action {
        case .setVideo(let url):
            if let url {
                loadVideo(url)
            } else {
                videoTrack = nil
                videoURL = nil
            }
        case .setAudio(let url):
            if let url {
                loadAudio(url)
            } else {
                audioTrack = nil
                audioURL = nil
            }
        case .setVideoOffset(let offset):
            videoOffset = offset
        case .setAudioOffset(let offset):
            audioOffset = offset
        case .setVideoSpeed(let speed):
            videoSpeed = speed
        case .setAudioSpeed(let speed):
            audioSpeed = speed
        }
    }
}

struct TrackRow: View {
    let title: String
    let name: String
    let duration: Double
    @Binding var offset: Double
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundColor(color)
                .font(.subheadline)
            
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)
            
            Text(formatDuration(duration))
                .monospaced()
                .foregroundStyle(.secondary)
            
            Text("偏移")
            
            Slider(value: $offset, in: 0...duration, step: 0.1)
                .frame(width: 150)
            
            Text("\(offset, specifier: "%.1f")s")
                .monospaced()
                .frame(width: 50)
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds / 60)
        let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
        return String(format: "%02d:%02d", mins, secs)
    }
}

struct TimelineView: View {
    let videoTrack: AudioVideoEditorView.TrackItem?
    let audioTrack: AudioVideoEditorView.TrackItem?
    let videoOffset: Double
    let audioOffset: Double
    let scale: Double
    @Binding var currentTime: Double
    
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                VStack(spacing: 4) {
                    if let videoTrack {
                        TrackBar(
                            duration: videoTrack.duration,
                            offset: videoOffset,
                            color: .blue,
                            label: "视频",
                            scale: scale
                        )
                    }
                    
                    if let audioTrack {
                        TrackBar(
                            duration: audioTrack.duration,
                            offset: audioOffset,
                            color: .green,
                            label: "音频",
                            scale: scale
                        )
                    }
                }
                
                Divider()
                    .frame(height: 60)
                
                TimeRuler(maxDuration: maxDuration, scale: scale)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var maxDuration: Double {
        let videoDur = videoTrack?.duration ?? 0
        let audioDur = audioTrack?.duration ?? 0
        return max(videoDur, audioDur)
    }
}

struct TrackBar: View {
    let duration: Double
    let offset: Double
    let color: Color
    let label: String
    let scale: Double
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: offset * 100 * scale, height: 24)
            
            Rectangle()
                .fill(color)
                .frame(width: duration * 100 * scale, height: 24)
            
            Text(label)
                .font(.caption)
                .foregroundColor(color)
                .padding(.leading, 4)
        }
    }
}

struct TimeRuler: View {
    let maxDuration: Double
    let scale: Double
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0...Int(maxDuration), id: \.self) { i in
                VStack(alignment: .leading) {
                    Text("\(i)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Rectangle()
                        .fill(.secondary)
                        .frame(width: 1, height: 40)
                }
                .frame(width: 100 * scale)
            }
        }
    }
}
