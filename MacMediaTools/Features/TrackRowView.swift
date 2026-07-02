import SwiftUI

struct TrackRow: View {
    let title: String
    let name: String
    let duration: Double
    @Binding var offset: Double
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(color)
                .font(.subheadline)

            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(formatTimeShort(duration))
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
}
