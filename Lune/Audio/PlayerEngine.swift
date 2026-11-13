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
    private(set) var queue: [Song] = [] { didSet { refreshCurrentSongID() } }
    private(set) var currentIndex: Int = -1 { didSet { refreshCurrentSongID() } }
    /// Id of the playing song. Rows watch this instead of `currentSong`, which also changes
    /// whenever the queue is edited, so only the rows whose state really changed redraw.
    private(set) var currentSongID: String?
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    var volume: Float = 1.0 {
        didSet { avPlayer.volume = volume }
    }
    var repeatMode: RepeatMode = .none
    var isShuffling = false
    private(set) var currentLyrics: LyricsData? = nil

    /// The track currently being listened to, for scrobbling. Cleared once it has been
    /// submitted (or skipped too early to count), so a track is never scrobbled twice.
    private var pendingScrobble: (song: Song, started: Date)?

    /// Bumped whenever the selected track changes or the queue is cleared. Async work
    /// started for an older selection compares against it before touching the player.
    private var loadGeneration = 0
    private var loadTask: Task<Void, Never>?
    private var lyricsTask: Task<Void, Never>?
    /// True once the user pauses, so an item that finishes loading afterwards stays paused.
    private var userPaused = false

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
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

    private func refreshCurrentSongID() {
        let id = currentSong?.id
        if id != currentSongID { currentSongID = id }
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
            userPaused = true
            avPlayer.pause()
            isPlaying = false
        } else {
            userPaused = false
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

    /// Current position read straight from AVPlayer. `currentTime` only updates every 0.5s,
    /// so views that draw a moving progress bar sample this each frame instead.
    func livePosition() -> Double {
        let t = avPlayer.currentTime().seconds
        return t.isFinite ? max(t, 0) : currentTime
    }

    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        avPlayer.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func starCurrentTrack() {
        guard let song = currentSong else { return }
        let starred = !song.isStarred
        Task { [weak self] in
            do {
                if starred { try await SubsonicClient.shared.star(id: song.id) }
                else { try await SubsonicClient.shared.unstar(id: song.id) }
            } catch {
                return
            }
            // Keep the queue's copy in step so the next tap reverses this one.
            guard let self, let i = self.queue.firstIndex(where: { $0.id == song.id }) else { return }
            self.queue[i].isStarred = starred
        }
    }

    // MARK: - Queue Management

    func move(fromOffsets: IndexSet, toOffset: Int) {
        // Carry each entry's old position along so the playing track can be found again.
        var tagged = queue.enumerated().map { (oldIndex: $0.offset, song: $0.element) }
        tagged.move(fromOffsets: fromOffsets, toOffset: toOffset)
        queue = tagged.map(\.song)
        if let i = tagged.firstIndex(where: { $0.oldIndex == currentIndex }) {
            currentIndex = i
        }
    }

    func remove(at offsets: IndexSet) {
        guard !offsets.isEmpty else { return }
        let removedCurrent = offsets.contains(currentIndex)
        let removedBefore = offsets.filter { $0 < currentIndex }.count
        queue.remove(atOffsets: offsets)

        if !removedCurrent {
            currentIndex -= removedBefore
        } else if queue.isEmpty {
            clearQueue()
        } else {
            // The playing track is gone: carry on with whatever now sits in its place.
            currentIndex = min(currentIndex - removedBefore, queue.count - 1)
            loadAndPlay(song: queue[currentIndex])
        }
    }

    func clearQueue() {
        submitScrobbleIfEligible(position: livePosition())
        cancelPendingLoads()
        queue.removeAll()
        currentIndex = -1
        currentLyrics = nil
        avPlayer.replaceCurrentItem(with: nil)
        isPlaying = false
        nowPlayingBridge?.clear()
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

    private func cancelPendingLoads() {
        loadGeneration &+= 1
        loadTask?.cancel()
        lyricsTask?.cancel()
        loadTask = nil
        lyricsTask = nil
    }

    private func loadAndPlay(song: Song) {
        // The track being left counts as listened if it got far enough.
        submitScrobbleIfEligible(position: livePosition())
        cancelPendingLoads()
        userPaused = false
        currentLyrics = nil
        let generation = loadGeneration

        loadTask = Task { [weak self] in
            let cached = await TrackCache.shared.cachedURL(for: song)
            // A newer selection (or a cleared queue) supersedes this one.
            guard !Task.isCancelled, let self, self.loadGeneration == generation else { return }
            if let cached {
                self.setItem(url: cached, song: song)
            } else if let streamURL = try? SubsonicClient.shared.streamURL(songId: song.id) {
                self.setItem(url: streamURL, song: song)
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
                // Ignore callbacks from an item that has since been replaced.
                guard let self = self, item === self.avPlayer.currentItem else { return }
                switch item.status {
                case .readyToPlay:
                    if !self.userPaused {
                        self.avPlayer.play()
                        self.isPlaying = true
                    }
                    let secs = item.duration.seconds
                    self.duration = secs.isFinite ? secs : Double(song.duration)
                    self.nowPlayingBridge?.update(song: song)
                case .failed:
                    if let error = item.error {
                        print("Player error: \(error.localizedDescription)")
                    }
                    self.isPlaying = false
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }
        pendingScrobble = (song, Date())
        avPlayer.replaceCurrentItem(with: item)
        nowPlayingBridge?.update(song: song)

        // Now-playing pings and lyrics are independent, so a slow scrobble request
        // can't hold lyrics back.
        Task {
            try? await SubsonicClient.shared.scrobble(id: song.id, submission: false)
            await LastFMClient.shared.updateNowPlaying(song: song)
        }
        lyricsTask = Task { [weak self] in
            let lyrics = await LyricsService.shared.lyrics(for: song)
            guard !Task.isCancelled, let self, self.currentSong?.id == song.id else { return }
            self.currentLyrics = lyrics
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
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] note in
            let finished = note.object as? AVPlayerItem
            MainActor.assumeIsolated {
                // Only this player's own item ends a track here.
                guard let self, let finished, finished === self.avPlayer.currentItem else { return }
                self.handleTrackEnd()
            }
        }
    }

    // MARK: - Scrobbling

    /// Submits the pending scrobble if the listener got far enough: half the track or
    /// four minutes, whichever comes first, and only for tracks over 30 seconds
    /// (Last.fm's rule, applied to the Subsonic server too).
    private func submitScrobbleIfEligible(position: Double) {
        guard let pending = pendingScrobble else { return }
        pendingScrobble = nil
        let length = Double(pending.song.duration)
        guard length > 30, position >= min(length / 2, 240) else { return }
        let song = pending.song
        let started = pending.started
        Task {
            try? await SubsonicClient.shared.scrobble(id: song.id, submission: true)
            await LastFMClient.shared.scrobble(song: song, startedAt: started, duration: song.duration)
        }
    }

    private func handleTrackEnd() {
        // The track played to the end, so it always counts.
        submitScrobbleIfEligible(position: .infinity)
        switch repeatMode {
        case .one:
            if let song = currentSong { pendingScrobble = (song, Date()) }
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
