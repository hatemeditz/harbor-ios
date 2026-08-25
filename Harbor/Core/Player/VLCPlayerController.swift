import Foundation
import MobileVLCKit

struct PlayerMediaTrack: Identifiable, Equatable, Hashable {
    let id: Int32
    let name: String
}

@MainActor
final class VLCPlayerController: NSObject, ObservableObject {
    enum PlayState: Equatable {
        case idle, buffering, playing, paused, stopped, ended, errored
    }

    private enum StartSeekBehavior: Equatable {
        case resume
        case preserveTimestamp
    }

    private struct PendingStart {
        let time: TimeInterval
        let behavior: StartSeekBehavior
    }

    @Published var state: PlayState = .idle
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var rate: Float = 1.0
    @Published private(set) var audioTracks: [PlayerMediaTrack] = []
    @Published private(set) var subtitleTracks: [PlayerMediaTrack] = []
    @Published private(set) var selectedAudioTrackId: Int32 = -1
    @Published private(set) var selectedSubtitleTrackId: Int32 = -1
    @Published private(set) var selectedExternalSubtitleLabel: String?
    @Published private(set) var subtitleDelay: TimeInterval = 0
    @Published private(set) var subtitleScale: Double = 100
    @Published private(set) var subtitleVerticalPosition: Double = 0
    @Published private(set) var subtitleError: String?

    let mediaPlayer = VLCMediaPlayer()
    private var pendingStart: PendingStart?
    private var currentMediaURL: URL?
    private var mediaGeneration = UUID()
    private var externalSubtitleURL: URL?
    private var externalSubtitleAppliedGeneration: UUID?
    private var desiredAudioTrackName: String?
    private var desiredEmbeddedSubtitleName: String?
    private var subtitlesDisabled = false
    private var pauseAfterReload = false
    private var lastProgressAt: Date?

    override private init() {
        super.init()
        mediaPlayer.delegate = self
    }

    static let shared = VLCPlayerController()

    var isPlaying: Bool { state == .playing || mediaPlayer.isPlaying }

    var isBuffering: Bool {
        state == .buffering && !mediaPlayer.isPlaying
    }

    func attach(drawable view: UIView) {
        mediaPlayer.drawable = view
    }

    func load(url: URL, startAt seconds: TimeInterval) {
        externalSubtitleURL = nil
        externalSubtitleAppliedGeneration = nil
        selectedExternalSubtitleLabel = nil
        desiredAudioTrackName = nil
        desiredEmbeddedSubtitleName = nil
        subtitlesDisabled = false
        subtitleError = nil
        subtitleDelay = 0
        pauseAfterReload = false
        startPlayback(url: url, startAt: seconds)
    }

    private func startPlayback(
        url: URL,
        startAt seconds: TimeInterval,
        seekBehavior: StartSeekBehavior = .resume
    ) {
        let media = VLCMedia(url: url)
        media.addOption(":network-caching=2000")
        // MobileVLCKit 3.x uses VLC 3's inverse relative-font-size scale
        // (16 is approximately 100%; smaller values render larger text).
        let relativeFontSize = Int((1600 / subtitleScale).rounded())
        media.addOption(":freetype-rel-fontsize=\(relativeFontSize)")
        media.addOption(":sub-margin=\(Int(subtitleVerticalPosition.rounded()))")
        currentMediaURL = url
        mediaGeneration = UUID()
        externalSubtitleAppliedGeneration = nil
        mediaPlayer.media = media
        mediaPlayer.currentVideoSubTitleDelay = Int(subtitleDelay * 1_000_000)
        let shouldSeek = seekBehavior == .preserveTimestamp ? seconds > 0 : seconds > 0.25
        pendingStart = shouldSeek ? PendingStart(time: seconds, behavior: seekBehavior) : nil
        lastProgressAt = nil
        currentTime = 0
        duration = 0
        audioTracks = []
        subtitleTracks = []
        selectedAudioTrackId = -1
        selectedSubtitleTrackId = -1
        state = .buffering
        mediaPlayer.play()
    }

    func togglePlayPause() {
        switch state {
        case .playing: pause()
        case .paused: play()
        case .buffering:
            mediaPlayer.isPlaying ? pause() : play()
        case .idle, .stopped: play()
        case .ended, .errored: break
        }
    }

    func play() {
        mediaPlayer.play()
        state = .playing
    }

    func pause() {
        mediaPlayer.pause()
        state = .paused
    }

    func stop() {
        pendingStart = nil
        lastProgressAt = nil
        currentMediaURL = nil
        externalSubtitleURL = nil
        externalSubtitleAppliedGeneration = nil
        mediaPlayer.stop()
        state = .stopped
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
        let clamped = max(0.25, min(newRate, 4.0))
        rate = clamped
        mediaPlayer.rate = clamped
    }

    func poll() {
        refreshFromPlayer()
    }

    func selectAudioTrack(_ track: PlayerMediaTrack) {
        desiredAudioTrackName = track.name
        mediaPlayer.currentAudioTrackIndex = track.id
        selectedAudioTrackId = track.id
    }

    func selectEmbeddedSubtitle(_ track: PlayerMediaTrack) {
        externalSubtitleURL = nil
        externalSubtitleAppliedGeneration = nil
        selectedExternalSubtitleLabel = nil
        desiredEmbeddedSubtitleName = track.name
        subtitlesDisabled = false
        mediaPlayer.currentVideoSubTitleIndex = track.id
        selectedSubtitleTrackId = track.id
        subtitleError = nil
    }

    func selectExternalSubtitle(url: URL, label: String) {
        externalSubtitleURL = url
        externalSubtitleAppliedGeneration = nil
        selectedExternalSubtitleLabel = label
        desiredEmbeddedSubtitleName = nil
        subtitlesDisabled = false
        subtitleError = nil
        applyDesiredAccessories()
    }

    func disableSubtitles() {
        externalSubtitleURL = nil
        externalSubtitleAppliedGeneration = nil
        selectedExternalSubtitleLabel = nil
        desiredEmbeddedSubtitleName = nil
        subtitlesDisabled = true
        mediaPlayer.currentVideoSubTitleIndex = -1
        selectedSubtitleTrackId = -1
        subtitleError = nil
    }

    func setSubtitleDelay(_ seconds: TimeInterval) {
        let clamped = max(-10, min(seconds, 10))
        subtitleDelay = clamped
        mediaPlayer.currentVideoSubTitleDelay = Int(clamped * 1_000_000)
    }

    func applySubtitleAppearance(scale: Double, verticalPosition: Double) {
        let newScale = max(50, min(scale, 200))
        let newPosition = max(0, min(verticalPosition, 300))
        guard abs(newScale - subtitleScale) > 0.1
                || abs(newPosition - subtitleVerticalPosition) > 0.1 else { return }

        subtitleScale = newScale
        subtitleVerticalPosition = newPosition
        guard let currentMediaURL else { return }
        let resumeTime = currentTime
        pauseAfterReload = state == .paused
        startPlayback(
            url: currentMediaURL,
            startAt: resumeTime,
            seekBehavior: .preserveTimestamp
        )
    }

    private func refreshFromPlayer() {
        let mediaLength = mediaPlayer.media?.length.intValue ?? 0
        let previousTime = currentTime
        duration = max(TimeInterval(mediaLength) / 1000, 0)
        currentTime = max(TimeInterval(mediaPlayer.time.intValue) / 1000, 0)
        let timeAdvanced = currentTime > previousTime + 0.02
        if timeAdvanced { lastProgressAt = Date() }
        let recentlyAdvanced = lastProgressAt.map { Date().timeIntervalSince($0) < 1.5 } ?? false

        if let pendingStart, duration > 0 {
            self.pendingStart = nil
            switch pendingStart.behavior {
            case .resume:
                seek(to: min(pendingStart.time, max(duration - 15, 0)))
            case .preserveTimestamp:
                let requestedTime = max(pendingStart.time, 0)
                mediaPlayer.time = VLCTime(int: Int32(requestedTime * 1000))
                currentTime = requestedTime
            }
        }

        let newState: PlayState
        switch mediaPlayer.state {
        case .playing: newState = .playing
        case .paused: newState = .paused
        case .buffering:
            newState = mediaPlayer.isPlaying || recentlyAdvanced ? .playing : .buffering
        case .ended: newState = .ended
        case .error: newState = .errored
        case .stopped: newState = .stopped
        default:
            if mediaPlayer.isPlaying || timeAdvanced {
                newState = .playing
            } else {
                newState = state == .buffering ? .buffering : state
            }
        }
        if newState != state {
            state = newState
            if newState == .playing && abs(mediaPlayer.rate - rate) > 0.01 {
                mediaPlayer.rate = rate
            }
        }

        if newState == .playing || newState == .paused {
            refreshTracks()
            applyDesiredAccessories()
        }

        if pauseAfterReload, pendingStart == nil, newState == .playing {
            pauseAfterReload = false
            pause()
        }
    }

    private func refreshTracks() {
        let newAudioTracks = Self.tracks(
            names: mediaPlayer.audioTrackNames,
            indexes: mediaPlayer.audioTrackIndexes
        )
        let newSubtitleTracks = Self.tracks(
            names: mediaPlayer.videoSubTitlesNames,
            indexes: mediaPlayer.videoSubTitlesIndexes
        )
        if newAudioTracks != audioTracks { audioTracks = newAudioTracks }
        if newSubtitleTracks != subtitleTracks { subtitleTracks = newSubtitleTracks }

        selectedAudioTrackId = mediaPlayer.currentAudioTrackIndex
        if externalSubtitleURL == nil {
            selectedSubtitleTrackId = mediaPlayer.currentVideoSubTitleIndex
        }
    }

    private func applyDesiredAccessories() {
        if let name = desiredAudioTrackName,
           let track = audioTracks.first(where: { $0.name == name }),
           mediaPlayer.currentAudioTrackIndex != track.id {
            mediaPlayer.currentAudioTrackIndex = track.id
            selectedAudioTrackId = track.id
        }

        if let name = desiredEmbeddedSubtitleName,
           let track = subtitleTracks.first(where: { $0.name == name }),
           mediaPlayer.currentVideoSubTitleIndex != track.id {
            mediaPlayer.currentVideoSubTitleIndex = track.id
            selectedSubtitleTrackId = track.id
        }

        if subtitlesDisabled, mediaPlayer.currentVideoSubTitleIndex != -1 {
            mediaPlayer.currentVideoSubTitleIndex = -1
            selectedSubtitleTrackId = -1
        }

        if let externalSubtitleURL,
           externalSubtitleAppliedGeneration != mediaGeneration,
           state == .playing || state == .paused {
            externalSubtitleAppliedGeneration = mediaGeneration
            let result = mediaPlayer.addPlaybackSlave(externalSubtitleURL, type: .subtitle, enforce: true)
            if result != 0 {
                subtitleError = "VLC could not load this subtitle file. Try another result."
                self.externalSubtitleURL = nil
                selectedExternalSubtitleLabel = nil
            } else {
                mediaPlayer.currentVideoSubTitleDelay = Int(subtitleDelay * 1_000_000)
            }
        }
    }

    private static func tracks(names: [Any], indexes: [Any]) -> [PlayerMediaTrack] {
        let count = min(names.count, indexes.count)
        return (0..<count).compactMap { index in
            guard let number = indexes[index] as? NSNumber else { return nil }
            return PlayerMediaTrack(
                id: number.int32Value,
                name: String(describing: names[index])
            )
        }
    }
}

extension VLCPlayerController: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor [weak self] in
            self?.refreshFromPlayer()
        }
    }

    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor [weak self] in
            self?.refreshFromPlayer()
        }
    }
}
