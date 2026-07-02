import SwiftUI

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
                    .foregroundStyle(.secondary)

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
                        .foregroundStyle(.secondary)

                    Text("暂无提取结果")
                        .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
                                Text(formatTime(selectedFrame.time))
                            }

                            VStack(alignment: .leading) {
                                Text("质量")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.2f%%", selectedFrame.qualityScore * 100))
                                    .foregroundStyle(selectedFrame.qualityScore >= 0.8 ? .green : selectedFrame.qualityScore >= 0.5 ? .orange : .red)
                            }

                            VStack(alignment: .leading) {
                                Text("来源")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Text(selectedFrame.isReplaced ? "智能替换" : "原始帧")
                                    .foregroundStyle(selectedFrame.isReplaced ? .orange : .gray)
                            }
                        }

                        if let filePath = selectedFrame.filePath {
                            HStack {
                                Text("保存路径")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)

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
