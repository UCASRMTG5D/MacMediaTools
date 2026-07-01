import AVKit
import SwiftUI

// MARK: - PlayerItem (Observable wrapper around AVPlayer)

final class PlayerItem: ObservableObject, Identifiable {
	let id = UUID()
	let url: URL
	let player: AVPlayer
	@Published var currentTime: Double = 0
	@Published var duration: Double = 0
	@Published var isPlaying = false
	@Published var volume: Float = 1.0 {
		didSet { player.volume = volume }
	}

	private var timeObserver: Any?
	private var statusObservation: NSKeyValueObservation?
	private var playedToEndObserver: NSObjectProtocol?

	init(url: URL) {
		self.url = url
		player = AVPlayer(url: url)
		player.volume = 1.0
		observe()
	}

	private func observe() {
		statusObservation = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
			guard let self, item.status == .readyToPlay else { return }
			Task { @MainActor in
				self.duration = item.duration.seconds
			}
		}

		timeObserver = player.addPeriodicTimeObserver(
			forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
			queue: .main
		) { [weak self] time in
			guard let self else { return }
			currentTime = time.seconds
		}

		playedToEndObserver = NotificationCenter.default.addObserver(
			forName: .AVPlayerItemDidPlayToEndTime,
			object: player.currentItem,
			queue: .main
		) { [weak self] _ in
			self?.isPlaying = false
		}
	}

	func seek(to fraction: Double) {
		guard duration > 0 else { return }
		let clamped = max(0, min(fraction, 1))
		let time = CMTime(seconds: clamped * duration, preferredTimescale: 600)
		player.seek(to: time)
	}

	func togglePlay() {
		if isPlaying {
			player.pause()
		} else {
			player.play()
		}
		isPlaying = !isPlaying
	}

	func play() {
		player.play()
		isPlaying = true
	}

	func pause() {
		player.pause()
		isPlaying = false
	}

	deinit {
		if let observer = timeObserver {
			player.removeTimeObserver(observer)
		}
		if let obs = playedToEndObserver {
			NotificationCenter.default.removeObserver(obs)
		}
	}
}

// MARK: - PlayerView (NSViewRepresentable)

struct PlayerView: NSViewRepresentable {
	let player: AVPlayer

	func makeNSView(context: Context) -> AVPlayerView {
		let view = AVPlayerView()
		view.player = player
		view.controlsStyle = .none
		return view
	}

	func updateNSView(_ nsView: AVPlayerView, context: Context) {
		nsView.player = player
	}
}

// MARK: - VideoComparisonPanel

struct VideoComparisonPanel: View {
	let items: [SimilarVideoClusterer.ClusterItem]

	@StateObject private var playerItems: PlayerItemsManager

	init(items: [SimilarVideoClusterer.ClusterItem]) {
		self.items = items
		_playerItems = StateObject(wrappedValue: PlayerItemsManager(items: items))
	}

	var body: some View {
		VStack(spacing: 8) {
			globalControls
			playerStrip
		}
		.onDisappear {
			playerItems.pauseAll()
		}
	}

	// MARK: - Global Controls

	private var globalControls: some View {
		HStack(spacing: 12) {
			Button(action: { playerItems.toggleAll() }) {
				Image(systemName: playerItems.allPlaying ? "pause.fill" : "play.fill")
			}
			.buttonStyle(.borderless)

			Text("全部")
				.font(.caption)
				.foregroundStyle(.secondary)

			Slider(
				value: $playerItems.globalProgress,
				in: 0...1,
				onEditingChanged: { editing in
					if editing {
						playerItems.pauseAll()
					} else {
						playerItems.seekAll(to: playerItems.globalProgress)
					}
				}
			)
			.frame(width: 180)

			HStack(spacing: 4) {
				Image(systemName: "speaker.wave.2.fill")
					.imageScale(.small)
					.foregroundStyle(.secondary)
				Slider(value: $playerItems.globalVolume, in: 0...1)
					.frame(width: 80)
					.onChange(of: playerItems.globalVolume) { newVal in
						playerItems.setAllVolume(newVal)
					}
			}
		}
		.padding(.horizontal, 8)
		.padding(.vertical, 4)
		.background(.quinary)
		.clipShape(RoundedRectangle(cornerRadius: 6))
	}

	// MARK: - Player Strip

	private var playerStrip: some View {
		ScrollView(.horizontal, showsIndicators: true) {
			HStack(spacing: 10) {
				ForEach(Array(playerItems.items.enumerated()), id: \.element.id) { (_, item) in
					playerColumn(item: item)
						.frame(width: 300)
				}
			}
			.padding(.horizontal, 4)
			.padding(.vertical, 4)
		}
		.frame(minHeight: 240)
	}

	private func playerColumn(item: PlayerItem) -> some View {
		VStack(spacing: 4) {
			// Video rendering
			PlayerView(player: item.player)
				.aspectRatio(16 / 9, contentMode: .fit)
				.clipShape(RoundedRectangle(cornerRadius: 4))
				.overlay(
					RoundedRectangle(cornerRadius: 4)
						.stroke(.separator, lineWidth: 0.5)
				)

			// File name
			Text(item.url.lastPathComponent)
				.font(.caption2)
				.lineLimit(1)
				.truncationMode(.middle)

			// Local controls row
			HStack(spacing: 6) {
				Button(action: { item.togglePlay() }) {
					Image(systemName: item.isPlaying ? "pause.fill" : "play.fill")
						.frame(width: 12)
				}
				.buttonStyle(.borderless)
				.help(item.isPlaying ? "暂停" : "播放")

				Slider(
					value: Binding(
						get: { item.duration > 0 ? item.currentTime / item.duration : 0 },
						set: { item.seek(to: $0) }
					),
					in: 0...1
				)
				.frame(width: 100)

				HStack(spacing: 2) {
					Image(systemName: "speaker.fill")
						.imageScale(.small)
						.foregroundStyle(.secondary)
					Slider(
						value: Binding(
							get: { item.volume },
							set: { item.volume = $0 }
						),
						in: 0...1
					)
					.frame(width: 50)
				}
			}
			.font(.caption)
		}
	}
}

// MARK: - PlayerItemsManager

private final class PlayerItemsManager: ObservableObject {
	@Published var items: [PlayerItem] = []
	@Published var globalProgress: Double = 0
	@Published var globalVolume: Float = 1.0 {
		didSet { setAllVolume(globalVolume) }
	}

	private var timeSyncObserver: Any?

	init(items: [SimilarVideoClusterer.ClusterItem]) {
		self.items = items.map { PlayerItem(url: $0.url) }
		observeTimeSync()
	}

	/// Observe the first player's time to update global progress.
	private func observeTimeSync() {
		guard let first = items.first else { return }
		timeSyncObserver = first.player.addPeriodicTimeObserver(
			forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
			queue: .main
		) { [weak self] time in
			guard let self, first.duration > 0 else { return }
			globalProgress = time.seconds / first.duration
		}
	}

	var allPlaying: Bool {
		items.allSatisfy(\.isPlaying)
	}

	func toggleAll() {
		if allPlaying {
			pauseAll()
		} else {
			for item in items { item.play() }
		}
	}

	func pauseAll() {
		for item in items { item.pause() }
	}

	func seekAll(to fraction: Double) {
		for item in items { item.seek(to: fraction) }
	}

	func setAllVolume(_ volume: Float) {
		for item in items { item.volume = volume }
	}

	deinit {
		if let observer = timeSyncObserver {
			items.first?.player.removeTimeObserver(observer)
		}
	}
}
