import SwiftUI

struct WelcomeDefaultView: View {
	private let buildDateTime: String

	init() {
		let df = DateFormatter()
		df.dateFormat = "yyyy-MM-dd HH:mm:ss"
		df.locale = Locale(identifier: "zh_CN")

		if let url = Bundle.main.executableURL,
		   let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
		   let d = attrs[.modificationDate] as? Date {
			buildDateTime = df.string(from: d)
		} else {
			buildDateTime = df.string(from: Date())
		}
	}

	var body: some View {
		VStack(spacing: 16) {
			Image(systemName: "wrench.and.screwdriver.fill")
				.font(.system(size: 48))
				.foregroundStyle(.tertiary)

			Text("MacMediaTools")
				.font(.largeTitle)
				.fontWeight(.medium)

			Text("Provided by UCASRMTG5D")
				.font(.body)
				.foregroundColor(.secondary)

			Text("编译于 \(buildDateTime)")
				.font(.caption)
				.foregroundColor(.secondary)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}
