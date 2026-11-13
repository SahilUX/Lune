import Foundation
import AVFoundation
import Observation

@Observable
@MainActor
final class PlayerEngine {
    static let shared: PlayerEngine = {
        MainActor.assumeIsolated { PlayerEngine() }
    }()

    private let avPlayer = AVPlayer()
    /// Keeps the loader alive for the current item (AVFoundation holds its delegate weakly).
    private var assetLoader: PinnedAssetLoader?
    private(set) var queue: [Song] = []
    private(set) var currentIndex: Int = -1
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    var volume: Float = 1.0 {
        didSet { avPlayer.volume = volume }
    }
    var repeatMode: RepeatMode = .none
    var isShuffling = false
    private(set) var currentLyrics: LyricsData? = nil
    private var trackStartTime: Date?

    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    var nowPlayingBridge: NowPlayingBridge?

    private init() {
        setupTimeObserver()
        setupRateObserver()
        nowPlayingBridge = NowPlayingBridge(engine: self)
    }

    // MARK: - Playback Control

    var currentSong: Song? {
        guard currentIndex >= 0, currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }

    func play(songs: [Song], startingAt index: Int = 0) {
        guard !songs.isEmpty, index >= 0, index < songs.count else { return }
        queue = songs
        currentIndex = index
        loadAndPlay(song: songs[index])
    }

    func play(song: Song) {
        if let i = queue.firstIndex(where: { $0.id == song.id }) {
            currentIndex = i
            loadAndPlay(song: song)
        } else {
            queue.insert(song, at: currentIndex + 1)
            currentIndex += 1
            loadAndPlay(song: song)
        }
    }

    func enqueue(songs: [Song]) {
        queue.append(contentsOf: songs)
    }

    func togglePlayPause() {
        if isPlaying {
            avPlayer.pause()
            isPlaying = false
        } else {
            avPlayer.play()
            isPlaying = true
        }
        nowPlayingBridge?.updatePlaybackState()
    }

    func skipForward() {
        guard let next = nextIndex() else { return }
        currentIndex = next
        loadAndPlay(song: queue[next])
    }

    func skipBackward() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard let prev = prevIndex() else { return }
        currentIndex = prev
        loadAndPlay(song: queue[prev])
    }

    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        avPlayer.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func starCurrentTrack() {
        guard let song = currentSong else { return }
        Task {
            if song.isStarred { try? await SubsonicClient.shared.unstar(id: song.id) }
            else { try? await SubsonicClient.shared.star(id: song.id) }
        }
    }

    // MARK: - Queue Management

    func move(fromOffsets: IndexSet, toOffset: Int) {
        queue.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    func remove(at offsets: IndexSet) {
        queue.remove(atOffsets: offsets)
    }

    func clearQueue() {
        queue.removeAll()
        currentIndex = -1
        avPlayer.replaceCurrentItem(with: nil)
        isPlaying = false
        nowPlayingBridge?.updatePlaybackState()
    }

    func shuffle() {
        guard !queue.isEmpty, let current = currentSong else { return }
        queue.shuffle()
        if let i = queue.firstIndex(where: { $0.id == current.id }) {
            queue.move(fromOffsets: IndexSet(integer: i), toOffset: 0)
            currentIndex = 0
        }
    }

    // MARK: - Private

    private func loadAndPlay(song: Song) {
        Task {
            if let localURL = await TrackCache.shared.cachedURL(for: song) {
                setItem(url: localURL, song: song)
            } else if let streamURL = try? SubsonicClient.shared.streamURL(songId: song.id) {
                setItem(url: streamURL, song: song)
            }
        }
    }

    private func setItem(url: URL, song: Song) {
        assetLoader?.invalidate()
        let item: AVPlayerItem
        if let loader = PinnedAssetLoader.make(for: url) {
            assetLoader = loader
            item = AVPlayerItem(asset: loader.asset)
        } else {
            assetLoader = nil
            item = AVPlayerItem(url: url)
        }
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    self?.avPlayer.play()
                    self?.isPlaying = true
                    let secs = item.duration.seconds
                    self?.duration = secs.isFinite ? secs : Double(song.duration)
                    self?.nowPlayingBridge?.update(song: song)
                case .failed:
                    if let error = item.error {
                        print("Player error: \(error.localizedDescription)")
                    }
                    self?.isPlaying = false
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }
        currentLyrics = nil
        trackStartTime = Date()
        avPlayer.replaceCurrentItem(with: item)
        nowPlayingBridge?.update(song: song)
        Task {
            try? await SubsonicClient.shared.scrobble(id: song.id, submission: false)
            await LastFMClient.shared.updateNowPlaying(song: song)
            currentLyrics = await LyricsService.shared.lyrics(for: song)
        }
    }

    private func setupRateObserver() {
        // Keep isPlaying in sync if the system pauses AVPlayer externally
        rateObserver = avPlayer.observe(\.rate, options: [.new]) { [weak self] _, change in
            DispatchQueue.main.async {
                let playing = (change.newValue ?? 0) > 0
                if self?.isPlaying != playing {
                    self?.isPlaying = playing
                    self?.nowPlayingBridge?.updatePlaybackState()
                }
            }
        }
    }

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.currentTime = time.seconds
            }
        }
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleTrackEnd()
            }
        }
    }

    private func handleTrackEnd() {
        if let song = currentSong {
            Task {
                try? await SubsonicClient.shared.scrobble(id: song.id, submission: true)
                if let started = trackStartTime {
                    await LastFMClient.shared.scrobble(song: song, startedAt: started, duration: song.duration)
                }
            }
        }
        trackStartTime = nil
        switch repeatMode {
        case .one:
            seek(to: 0)
            avPlayer.play()
        case .all:
            skipForward()
        case .none:
            if let next = nextIndex() {
                currentIndex = next
                loadAndPlay(song: queue[next])
            } else {
                isPlaying = false
                nowPlayingBridge?.updatePlaybackState()
            }
        }
    }

    private func nextIndex() -> Int? {
        guard !queue.isEmpty else { return nil }
        let next = currentIndex + 1
        if next < queue.count { return next }
        if repeatMode == .all { return 0 }
        return nil
    }

    private func prevIndex() -> Int? {
        guard !queue.isEmpty else { return nil }
        let prev = currentIndex - 1
        if prev >= 0 { return prev }
        if repeatMode == .all { return queue.count - 1 }
        return nil
    }
}

enum RepeatMode {
    case none, one, all
}
