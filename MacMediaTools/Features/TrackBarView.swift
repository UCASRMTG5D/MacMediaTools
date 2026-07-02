import SwiftUI

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
                .foregroundStyle(color)
                .padding(.leading, 4)
        }
    }
}
