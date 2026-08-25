import Foundation
import MobileVLCKit

@MainActor
final class VLCPlayerController: NSObject, ObservableObject {
    enum PlayState {
        case idle, buffering, playing, paused, stopped, ended, errored
    }

    @Published var state: PlayState = .idle
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var rate: Float = 1.0

    let mediaPlayer = VLCMediaPlayer()

    override private init() {
        super.init()
        mediaPlayer.delegate = self
    }

    static let shared = VLCPlayerController()

    var isPlaying: Bool { state == .playing }

    func attach(drawable view: UIView) {
        mediaPlayer.drawable = view
    }

    func load(url: URL, startAt seconds: TimeInterval) {
        let media = VLCMedia(url: url)
        media.addOption(":network-caching=2000")
        mediaPlayer.media = media
        currentTime = 0
        duration = 0
        state = .buffering
        mediaPlayer.play()
        if seconds > 5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self, self.duration > 0 else { return }
                self.seek(to: min(seconds, self.duration - 15))
            }
        }
    }

    func togglePlayPause() {
        switch state {
        case .playing: pause()
        case .paused: play()
        default: break
        }
    }

    func play() {
        mediaPlayer.play()
    }

    func pause() {
        mediaPlayer.pause()
    }

    func stop() {
        mediaPlayer.stop()
    }

    func seek(to seconds: TimeInterval) {
        guard duration > 0 else { return }
        let clamped = max(0, min(seconds, duration - 1))
        mediaPlayer.time = VLCTime(int: Int32(clamped * 1000))
        currentTime = clamped
    }

    func seek(by delta: TimeInterval) {
        seek(to: currentTime + delta)
    }

    func setRate(_ newRate: Float) {
        rate = newRate
        mediaPlayer.rate = newRate
    }

    private func refreshFromPlayer() {
        let mediaLength = mediaPlayer.media?.length.intValue ?? 0
        duration = TimeInterval(mediaLength) / 1000
        currentTime = TimeInterval(mediaPlayer.time.intValue) / 1000

        let newState: PlayState
        switch mediaPlayer.state {
        case .playing: newState = .playing
        case .paused: newState = .paused
        case .buffering: newState = .buffering
        case .ended: newState = .ended
        case .error: newState = .errored
        case .stopped: newState = .stopped
        default: newState = state == .buffering ? .buffering : .paused
        }
        if newState != state {
            state = newState
            if newState == .playing && abs(mediaPlayer.rate - rate) > 0.01 {
                mediaPlayer.rate = rate
            }
        }
    }
}

extension VLCPlayerController: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification!) {
        Task { @MainActor [weak self] in
            self?.refreshFromPlayer()
        }
    }

    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification!) {
        Task { @MainActor [weak self] in
            self?.refreshFromPlayer()
        }
    }
}
