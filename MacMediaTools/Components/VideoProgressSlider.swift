import SwiftUI
import AVFoundation

struct VideoProgressSlider: View {
    @Binding var startTime: Double
    @Binding var endTime: Double
    @Binding var currentTime: Double
    @Binding var duration: Double
    
    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false
    @State private var isDraggingPlayhead = false
    
    var onTimeChange: ((Double) -> Void)?
    
    var body: some View {
        VStack(spacing: 8) {
            // 进度条
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("progressTrack"))
                                .onChanged { value in
                                    guard !isDraggingStart, !isDraggingEnd, !isDraggingPlayhead else { return }
                                    updateCurrentTime(from: value, in: geometry)
                                }
                        )
                    
                    // 背景
                    Rectangle()
                        .fill(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                        .allowsHitTesting(false)
                    
                    // 可选区域背景
                    Rectangle()
                        .fill(Color(NSColor.systemBlue).opacity(0.2))
                        .cornerRadius(4)
                        .frame(width: calculateSelectionWidth(geometry: geometry), height: 12)
                        .offset(x: calculateStartOffset(geometry: geometry))
                        .allowsHitTesting(false)
                    
                    // 播放进度
                    Rectangle()
                        .fill(Color(NSColor.systemBlue).opacity(0.5))
                        .cornerRadius(4)
                        .frame(width: calculatePlayheadWidth(geometry: geometry), height: 12)
                        .allowsHitTesting(false)
                    
                    // 起始点控制
                    Circle()
                        .fill(Color(NSColor.systemBlue))
                        .frame(width: 16, height: 16)
                        .shadow(radius: 2)
                        .offset(x: calculateStartOffset(geometry: geometry) - 8)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("progressTrack"))
                                .onChanged { value in
                                    isDraggingStart = true
                                    updateStartTime(from: value, in: geometry)
                                }
                                .onEnded { _ in
                                    isDraggingStart = false
                                }
                        )
                    
                    // 结束点控制
                    Circle()
                        .fill(Color(NSColor.systemOrange))
                        .frame(width: 16, height: 16)
                        .shadow(radius: 2)
                        .offset(x: calculateEndOffset(geometry: geometry) - 8)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("progressTrack"))
                                .onChanged { value in
                                    isDraggingEnd = true
                                    updateEndTime(from: value, in: geometry)
                                }
                                .onEnded { _ in
                                    isDraggingEnd = false
                                }
                        )
                    
                    // 播放头
                    Rectangle()
                        .fill(Color(NSColor.systemRed))
                        .frame(width: 2, height: 20)
                        .offset(x: calculatePlayheadOffset(geometry: geometry) - 1, y: -4)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("progressTrack"))
                                .onChanged { value in
                                    isDraggingPlayhead = true
                                    updateCurrentTime(from: value, in: geometry)
                                }
                                .onEnded { _ in
                                    isDraggingPlayhead = false
                                }
                        )
                }
                .frame(height: 12)
                .coordinateSpace(name: "progressTrack")
            }
            
            // 时间标签
            HStack {
                Text(formatTime(currentTime))
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .bold()
                
                Spacer()
                
                Text(formatTime(startTime))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(formatTime(endTime))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(formatTime(duration))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func calculateStartOffset(geometry: GeometryProxy) -> CGFloat {
        guard duration > 0 else { return 0 }
        return (startTime / duration) * geometry.size.width
    }
    
    private func calculateEndOffset(geometry: GeometryProxy) -> CGFloat {
        guard duration > 0 else { return geometry.size.width }
        return (endTime / duration) * geometry.size.width
    }
    
    private func calculatePlayheadOffset(geometry: GeometryProxy) -> CGFloat {
        guard duration > 0 else { return 0 }
        return (currentTime / duration) * geometry.size.width
    }
    
    private func calculateSelectionWidth(geometry: GeometryProxy) -> CGFloat {
        guard duration > 0 else { return 0 }
        return max(0, (endTime - startTime) / duration * geometry.size.width)
    }
    
    private func calculatePlayheadWidth(geometry: GeometryProxy) -> CGFloat {
        guard duration > 0 else { return 0 }
        return (currentTime / duration) * geometry.size.width
    }
    
    private func updateStartTime(from value: DragGesture.Value, in geometry: GeometryProxy) {
        let x = max(0, min(value.location.x, geometry.size.width))
        guard duration > 0 else { return }
        let newTime = (x / geometry.size.width) * duration
        startTime = max(0, min(newTime, endTime - 0.1))
    }
    
    private func updateEndTime(from value: DragGesture.Value, in geometry: GeometryProxy) {
        let x = max(0, min(value.location.x, geometry.size.width))
        guard duration > 0 else { return }
        let newTime = (x / geometry.size.width) * duration
        endTime = max(startTime + 0.1, min(newTime, duration))
    }
    
    private func updateCurrentTime(from value: DragGesture.Value, in geometry: GeometryProxy) {
        let x = max(0, min(value.location.x, geometry.size.width))
        guard duration > 0 else { return }
        let newTime = (x / geometry.size.width) * duration
        currentTime = max(0, min(newTime, duration))
        onTimeChange?(currentTime)
    }
    

}
