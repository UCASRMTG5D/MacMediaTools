import SwiftUI

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
