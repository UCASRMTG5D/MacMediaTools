import SwiftUI

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
