import SwiftUI

struct FrameThumbnail: View {
    let frame: VideoScreenshotExtractor.ExtractedFrame
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Image(nsImage: NSImage(cgImage: frame.image, size: CGSize(width: frame.image.width, height: frame.image.height)))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 80)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                )
                .overlay(
                    frame.isReplaced ? Image(systemName: "arrow.refresh")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .padding(2)
                        .background(Color.white.opacity(0.8))
                        .cornerRadius(2)
                        .offset(x: 4, y: 4) : nil
                )

            Text(formatTimeShort(frame.time))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack {
                Text("\(index + 1)")
                    .font(.system(size: 9))
                    .foregroundStyle(.gray)

                Spacer()

                if frame.qualityScore < 0.8 {
                    Image(systemName: "alert.triangle")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
            }
        }
        .onTapGesture {
            onSelect()
        }
    }

    
}
