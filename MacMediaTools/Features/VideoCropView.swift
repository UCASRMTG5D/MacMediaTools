import AppKit
import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct VideoCropView: View {
	@State private var inputURL: URL?
	@State private var player: AVPlayer?
	@State private var displaySize: CGSize?

	@State private var infoText: String = "请选择一个视频文件"
	@State private var normalizedRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)

	@State private var outputFolder: URL?
	@State private var outputFileName: String = ""

	@State private var isWorking = false
	@State private var lastOutputURL: URL?
	@State private var errorMessage: String?

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			Text("视频尺寸裁剪")
				.font(.title2)

			HStack(spacing: 12) {
				OpenPanelButton(
					title: "选择视频…",
					mode: .file(allowedTypes: [.movie], allowsMultipleSelection: false)
				) { urls in
					guard let url = urls.first else { return }
					selectInput(url)
				}
				Text(inputURL?.path ?? "未选择")
					.lineLimit(1)
					.truncationMode(.middle)

				if let inputURL {
					Button("在 Finder 中显示") {
						NSWorkspace.shared.activateFileViewerSelecting([inputURL])
					}
					.buttonStyle(.borderless)
				}
			}

			Text(infoText)
				.foregroundStyle(.secondary)

			if let player {
				GeometryReader { geo in
					let container = geo.size
					let video = displaySize ?? container
					let scale = min(
						container.width / max(video.width, 1),
						container.height / max(video.height, 1)
					)
					let fitted = CGSize(width: video.width * scale, height: video.height * scale)
					let origin = CGPoint(
						x: (container.width - fitted.width) / 2,
						y: (container.height - fitted.height) / 2
					)

					ZStack(alignment: .topLeading) {
						VideoPlayer(player: player)
							.onDisappear { player.pause() }

						CropOverlay(normalizedRect: $normalizedRect)
							.frame(width: fitted.width, height: fitted.height)
							.position(
								x: origin.x + fitted.width / 2,
								y: origin.y + fitted.height / 2
							)
							.allowsHitTesting(true)
					}
				}
				.frame(height: 360)
				.clipped()
				.cornerRadius(8)
			} else {
				Text("（预览区域）")
					.frame(maxWidth: .infinity, minHeight: 360)
					.overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
			}

			Divider()

			Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
				GridRow {
					Text("输出目录")
					HStack {
						OpenPanelButton(title: "选择目录…", mode: .folder) { urls in
							outputFolder = urls.first
						}
						Text(outputFolder?.path ?? "(默认：原视频同目录)")
							.lineLimit(1)
							.truncationMode(.middle)
					}
					.gridCellColumns(3)
				}

				GridRow {
					Text("输出文件名")
					TextField("例如 xxx_1_crop.mp4", text: $outputFileName)
						.frame(maxWidth: 520)
						.gridCellColumns(3)
				}
			}

			HStack(spacing: 12) {
				Button(isWorking ? "处理中…" : "开始裁剪") {
					Task { await run() }
				}
				.disabled(isWorking || inputURL == nil || displaySize == nil)

				if let lastOutputURL {
					Button("在 Finder 中显示结果") {
						NSWorkspace.shared.activateFileViewerSelecting([lastOutputURL])
					}
				}
			}

			if let errorMessage {
				Text(errorMessage)
					.foregroundStyle(.red)
			}

			Spacer()
		}
	}

	private func selectInput(_ url: URL) {
		inputURL = url
		errorMessage = nil
		lastOutputURL = nil
		normalizedRect = CGRect(x: 0, y: 0, width: 1, height: 1)
		player = AVPlayer(url: url)
		player?.play()

		Task {
			do {
				let info = try await VideoToolkit.readDisplayInfo(url: url)
				displaySize = info.displaySize
				infoText = "原始宽高：\(Int(info.displaySize.width)) × \(Int(info.displaySize.height))（拖动黄色裁剪框）"

				if outputFolder == nil { outputFolder = url.deletingLastPathComponent() }
				if outputFileName.isEmpty { outputFileName = defaultOutputName(for: url) }
			} catch {
				infoText = "读取视频信息失败：\(error.localizedDescription)"
				displaySize = nil
			}
		}
	}

	private func defaultOutputName(for input: URL) -> String {
		let base = input.deletingPathExtension().lastPathComponent
		return "\(base)_1_crop.mp4"
	}

	private func buildOutputURL() -> URL? {
		guard let inputURL else { return nil }
		let folder = outputFolder ?? inputURL.deletingLastPathComponent()
		let name = outputFileName.isEmpty ? defaultOutputName(for: inputURL) : outputFileName
		return folder.appendingPathComponent(name)
	}

	@MainActor
	private func run() async {
		guard let inputURL, let displaySize, let outURL = buildOutputURL() else { return }
		isWorking = true
		errorMessage = nil
		lastOutputURL = nil
		defer { isWorking = false }

		let crop = CGRect(
			x: normalizedRect.origin.x * displaySize.width,
			y: normalizedRect.origin.y * displaySize.height,
			width: normalizedRect.size.width * displaySize.width,
			height: normalizedRect.size.height * displaySize.height
		).integral

		do {
			try await VideoToolkit.exportCropped(
				inputURL: inputURL,
				outputURL: outURL,
				cropRect: crop
			)
			lastOutputURL = outURL
		} catch {
			errorMessage = error.localizedDescription
		}
	}
}
