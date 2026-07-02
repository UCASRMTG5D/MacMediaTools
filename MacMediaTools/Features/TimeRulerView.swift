import SwiftUI

struct TimeRuler: View {
    let maxDuration: Double
    let scale: Double

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0...Int(maxDuration), id: \.self) { i in
                VStack(alignment: .leading) {
                    Text("\(i)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Rectangle()
                        .fill(.secondary)
                        .frame(width: 1, height: 40)
                }
                .frame(width: 100 * scale)
            }
        }
    }
}
