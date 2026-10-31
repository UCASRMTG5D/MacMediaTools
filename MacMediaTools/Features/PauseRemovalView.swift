import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PauseRemovalView: View {
    @State private var videoURL: URL?
    @State private var thresholdDB: Double = -40
    @State private var analysisResult: PauseAnalysisResult?
    @State private var isAnalyzing = false
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var outputFolder: URL?
    @State private var outputFileName: String = ""
    @State private var errorMessage: String?
    @State private var successMessage: String?
    
    private func uniqueOutputURL(folder: URL, fileName: String) -> URL {
        var url = folder.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        for i in 1...999 {
            let candidate = folder.appendingPathComponent("\(base)_\(i).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }
    
    private func friendlyMessage(for error: Error) -> String {
        if let e = error as? PauseRemoverError {
            switch e {
            case .noAudioTrack: return "该视频没有音频轨道，无法基于声音检测停顿。"
            case .outputAlreadyExists: return "输出文件已存在，请修改文件名。"
            default: return e.localizedDescription
            }
        }
        return error.localizedDescription
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox("视频选择") {
                    HStack {
                        OpenPanelButton(title: "选择视频…", mode: .file(allowedTypes: [.movie, .mpeg4Movie, .quickTimeMovie], allowsMultipleSelection: false)) { urls in
                            guard let url = urls.first else { return }
                            videoURL = url
                            analysisResult = nil
                            errorMessage = nil
                            successMessage = nil
                            outputFolder = url.deletingLastPathComponent()
                            outputFileName = url.deletingPathExtension().lastPathComponent + "_去停顿.mp4"
                        }
                        Text(videoURL?.lastPathComponent ?? "未选择视频")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.vertical, 4)
                }
                
                GroupBox("停顿判定参数") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Slider(value: $thresholdDB, in: (-55.0)...(-25.0), step: 1)
                            Text("\(Int(thresholdDB)) dBFS")
                                .monospacedDigit()
                                .frame(width: 60, alignment: .trailing)
                        }
                        Text("音频低于该音量、且持续 ≥ 0.5 秒，判定为停顿（仅保留停顿前 0.5 秒）。环境噪音大时调高，环境安静时调低。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: thresholdDB) { _ in
                    analysisResult = nil
                }
                
                GroupBox("分析") {
                    VStack(alignment: .leading, spacing: 8) {
                        Button(isAnalyzing ? "分析中…" : "分析停顿") {
                            guard let url = videoURL else { return }
                            Task {
                                isAnalyzing = true
                                errorMessage = nil
                                successMessage = nil
                                defer { isAnalyzing = false }
                                do {
                                    let r = try await PauseRemover.shared.analyze(url: url, thresholdDB: Float(thresholdDB))
                                    analysisResult = r
                                } catch {
                                    errorMessage = friendlyMessage(for: error)
                                }
                            }
                        }
                        .disabled(videoURL == nil || isAnalyzing || isExporting)
                        if isAnalyzing {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("正在分析音频…")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                if let r = analysisResult {
                    GroupBox("分析结果") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("原始时长：\(formatTimeShort(r.originalDuration))")
                            Text("预计新时长：\(formatTimeShort(r.keptDuration))")
                            Text("可节省：\(formatTimeShort(r.removedDuration))（\(String(format: "%.1f", r.removedRatio * 100))%）")
                            if r.keepSegments.isEmpty {
                                Text("未检测到可导出的片段")
                                    .foregroundColor(.secondary)
                            } else if r.silenceRanges.isEmpty {
                                Text("未检测到可去除的停顿，无需导出")
                                    .foregroundColor(.secondary)
                            } else {
                                Text("检测到停顿 \(r.silenceRanges.count) 个（每个仅保留前 0.5 秒）")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    GroupBox("导出") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                OpenPanelButton(title: "输出目录…", mode: .folder) { urls in
                                    outputFolder = urls.first
                                }
                                Text(outputFolder?.path ?? "(默认与源文件同目录)")
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            TextField("文件名", text: $outputFileName)
                            Button("导出紧凑版") {
                                guard let url = videoURL, let r = analysisResult else { return }
                                let folder = outputFolder ?? url.deletingLastPathComponent()
                                let outURL = uniqueOutputURL(folder: folder, fileName: outputFileName)
                                let started = SecurityBookmarkStore.shared.startAccessing(folder)
                                Task {
                                    isExporting = true
                                    exportProgress = 0
                                    errorMessage = nil
                                    successMessage = nil
                                    defer {
                                        if started { SecurityBookmarkStore.shared.stopAccessing(folder) }
                                        isExporting = false
                                    }
                                    do {
                                        try await PauseRemover.shared.export(inputURL: url, keepSegments: r.keepSegments, outputURL: outURL, progressHandler: { p in
                                            Task { @MainActor in self.exportProgress = p }
                                        })
                                        await MainActor.run {
                                            successMessage = "导出成功"
                                            NSWorkspace.shared.activateFileViewerSelecting([outURL])
                                        }
                                    } catch {
                                        await MainActor.run {
                                            errorMessage = friendlyMessage(for: error)
                                        }
                                    }
                                }
                            }
                            .disabled(analysisResult == nil || (analysisResult?.keepSegments.isEmpty ?? true) || isAnalyzing || isExporting || outputFileName.trimmingCharacters(in: .whitespaces).isEmpty)
                            if isExporting {
                                ProgressView(value: exportProgress)
                                Text(String(format: "%.0f%%", exportProgress * 100))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                if let em = errorMessage {
                    Text(em)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                if let sm = successMessage {
                    Text(sm)
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollIndicators(.visible)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
