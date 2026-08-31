import Foundation

/// Per-attempt playback analytics state. This deliberately tracks wall-clock
/// time spent in VLC's playing state instead of treating seeking/resume offsets
/// as watch time.
final class PlaybackAnalyticsSession {
    let id: UUID

    private let target: StreamTarget
    private let requestedAt: Date
    private let analytics: AnalyticsService
    private var startupTrace: HarborPerformanceTrace?

    private var didStart = false
    private var didFail = false
    private var didComplete = false
    private var didStop = false
    private var startupMilliseconds: Int?
    private var previousState: VLCPlayerController.PlayState = .idle
    private var playingSince: Date?
    private var bufferingSince: Date?
    private var watchedSeconds: TimeInterval = 0
    private var bufferedSeconds: TimeInterval = 0
    private var bufferCount = 0
    private var reachedMilestones = Set<Int>()

    init(
        target: StreamTarget,
        requestedAt: Date = Date(),
        analytics: AnalyticsService = .shared
    ) {
        self.id = target.playbackSessionId
        self.target = target
        self.requestedAt = requestedAt
        self.analytics = analytics
    }

    /// Starts the custom trace only after SwiftUI has retained this session.
    /// View initializers may be evaluated more than once, so initialization
    /// itself must remain side-effect free.
    func begin() {
        guard startupTrace == nil, !didStart, !didFail, !didStop else { return }
        startupTrace = analytics.startTrace(
            .playbackStart,
            attributes: [.mediaType: HarborMediaType(target.type).rawValue]
        )
    }

    func prepareForResume(offset: TimeInterval, knownDuration: TimeInterval) {
        guard offset > 0, knownDuration > 0 else { return }
        suppressMilestones(alreadyReachedAt: offset / knownDuration)
    }

    func update(
        state: VLCPlayerController.PlayState,
        currentTime: TimeInterval,
        duration: TimeInterval,
        now: Date = Date()
    ) {
        guard !didStop else { return }
        analytics.setPlayerContext(state: state.analyticsName, mediaType: HarborMediaType(target.type))

        if previousState == .playing, state != .playing {
            closePlayingSegment(at: now)
        }
        if previousState == .buffering, state != .buffering {
            closeBufferingSegment(at: now)
        }

        if state == .playing {
            if !didStart {
                didStart = true
                let startupMs = AnalyticsService.milliseconds(since: requestedAt, now: now)
                startupMilliseconds = startupMs
                var parameters = baseParameters
                parameters[.playbackStartupMs] = .int(startupMs)
                if duration > 0 {
                    parameters[.durationBucket] = .string(AnalyticsService.durationBucket(seconds: duration))
                }
                analytics.log(.playbackStarted, parameters: parameters)
                startupTrace?.stop(outcome: "success", metrics: [.success: 1])
                startupTrace = nil
            }
            if playingSince == nil { playingSince = now }
        } else if state == .buffering, didStart, previousState != .buffering {
            bufferCount += 1
            bufferingSince = now
        }

        emitMilestones(currentTime: currentTime, duration: duration, now: now)

        if state == .errored, !didFail {
            didFail = true
            var parameters = baseParameters
            parameters[.playbackStartupMs] = .int(
                startupMilliseconds ?? AnalyticsService.milliseconds(since: requestedAt, now: now)
            )
            parameters[.watchTimeSeconds] = .int(Int(totalWatchTime(at: now).rounded(.down)))
            parameters[.errorType] = .string(HarborAnalyticsErrorCategory.vlcError.rawValue)
            analytics.log(.playbackFailed, parameters: parameters)
            startupTrace?.stop(
                outcome: "failure",
                attributes: [.errorCategory: HarborAnalyticsErrorCategory.vlcError.rawValue],
                metrics: [.success: 0]
            )
            startupTrace = nil
            analytics.recordNonFatal(
                .playback,
                category: .vlcError,
                context: HarborErrorContext(
                    screen: .player,
                    mediaType: HarborMediaType(target.type),
                    playerState: state.analyticsName
                )
            )
        }

        if state == .ended, !didComplete {
            emitMilestones(currentTime: duration > 0 ? duration : currentTime, duration: duration, now: now)
            didComplete = true
            var parameters = baseParameters
            addDurationAndWatchTime(to: &parameters, duration: duration, now: now)
            analytics.log(.playbackCompleted, parameters: parameters)
        }

        previousState = state
    }

    func stop(
        reason: HarborPlaybackStopReason,
        currentTime: TimeInterval,
        duration: TimeInterval,
        now: Date = Date()
    ) {
        guard !didStop else { return }
        if previousState == .playing { closePlayingSegment(at: now) }
        if previousState == .buffering { closeBufferingSegment(at: now) }
        didStop = true

        if !didStart {
            startupTrace?.stop(
                outcome: reason == .failed ? "failure" : "cancelled",
                metrics: [.success: 0]
            )
            startupTrace = nil
        }

        var parameters = baseParameters
        addDurationAndWatchTime(to: &parameters, duration: duration, now: now)
        if duration > 0 {
            let progress = Int((max(0, min(currentTime / duration, 1)) * 100).rounded())
            parameters[.progressPercent] = .int(progress)
        }
        parameters[.bufferCount] = .int(bufferCount)
        parameters[.totalBufferSeconds] = .double((bufferedSeconds * 10).rounded() / 10)
        parameters[.stopReason] = .string(reason.rawValue)
        analytics.log(.playbackStopped, parameters: parameters)
    }

    var accumulatedWatchTime: TimeInterval {
        totalWatchTime(at: Date())
    }

    private var baseParameters: HarborAnalyticsParameters {
        analytics.mediaParameters(
            mediaType: target.type,
            mediaId: target.metaId,
            source: target.analyticsSource,
            playbackSessionId: target.playbackSessionId,
            seasonNumber: target.seasonNumber,
            episodeNumber: target.episodeNumber
        )
    }

    private func emitMilestones(
        currentTime: TimeInterval,
        duration: TimeInterval,
        now: Date
    ) {
        guard didStart, duration > 0 else { return }
        let ratio = max(0, min(currentTime / duration, 1))
        for milestone in [90] where ratio >= Double(milestone) / 100 {
            guard reachedMilestones.insert(milestone).inserted else { continue }
            var parameters = baseParameters
            addDurationAndWatchTime(to: &parameters, duration: duration, now: now)
            analytics.log(.playback90, parameters: parameters)
        }
    }

    private func suppressMilestones(alreadyReachedAt ratio: Double) {
        for milestone in [90] where ratio >= Double(milestone) / 100 {
            reachedMilestones.insert(milestone)
        }
    }

    private func closePlayingSegment(at now: Date) {
        if let playingSince {
            watchedSeconds += max(0, now.timeIntervalSince(playingSince))
        }
        playingSince = nil
    }

    private func closeBufferingSegment(at now: Date) {
        if let bufferingSince {
            bufferedSeconds += max(0, now.timeIntervalSince(bufferingSince))
        }
        bufferingSince = nil
    }

    private func totalWatchTime(at now: Date) -> TimeInterval {
        watchedSeconds + (playingSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    private func addDurationAndWatchTime(
        to parameters: inout HarborAnalyticsParameters,
        duration: TimeInterval,
        now: Date
    ) {
        if duration > 0 {
            parameters[.durationBucket] = .string(AnalyticsService.durationBucket(seconds: duration))
        }
        parameters[.watchTimeSeconds] = .int(Int(totalWatchTime(at: now).rounded(.down)))
    }
}

extension VLCPlayerController.PlayState {
    var analyticsName: String {
        switch self {
        case .idle: return "idle"
        case .buffering: return "buffering"
        case .playing: return "playing"
        case .paused: return "paused"
        case .stopped: return "stopped"
        case .ended: return "ended"
        case .errored: return "errored"
        }
    }
}
