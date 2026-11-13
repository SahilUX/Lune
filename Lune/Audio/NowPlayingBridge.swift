import MediaPlayer

@MainActor
final class NowPlayingBridge {
    private weak var engine: PlayerEngine?

    init(engine: PlayerEngine) {
        self.engine = engine
        setupRemoteCommands()
    }

    func update(song: Song) {
        let isPlaying = engine?.isPlaying ?? false
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyAlbumTitle: song.album,
            MPMediaItemPropertyPlaybackDuration: song.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: engine?.currentTime ?? 0,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]
        // Note: MPMediaItemArtwork crashes on macOS Sequoia due to internal
        // dispatch_barrier_async queue assertion. Artwork is disabled for stability.
        // Already on the main actor. Deferring this let an older track's update land after a newer one.
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func updatePlaybackState() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        let isPlaying = engine?.isPlaying ?? false
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = engine?.currentTime ?? 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Removes the track from the system's Now Playing controls (queue cleared).
    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            guard self?.engine != nil else { return .commandFailed }
            DispatchQueue.main.async {
                guard let engine = self?.engine else { return }
                if !engine.isPlaying { engine.togglePlayPause() }
            }
            return .success
        }
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            guard self?.engine != nil else { return .commandFailed }
            DispatchQueue.main.async {
                guard let engine = self?.engine else { return }
                if engine.isPlaying { engine.togglePlayPause() }
            }
            return .success
        }
        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.engine?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.engine?.skipForward() }
            return .success
        }
        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.engine?.skipBackward() }
            return .success
        }
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let e = event as? MPChangePlaybackPositionCommandEvent {
                DispatchQueue.main.async { self?.engine?.seek(to: e.positionTime) }
            }
            return .success
        }
    }
}
