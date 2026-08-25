import SwiftUI
import UIKit

struct PlayerScreen: View {
    let streamURL: URL

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var player = VLCPlayerController.shared

    @State private var activeTitle: String
    @State private var activeTarget: StreamTarget
    @State private var showControls = true
    @State private var controlsHideTask: Task<Void, Never>?
    @State private var syncCounter = 0
    @State private var markedWatched = false
    @State private var resumeApplied = false
    @State private var nextVideo: MetaVideo?
    @State private var showNextPrompt = false
    @State private var persistenceTask: Task<Void, Never>?

    private let uiTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(streamURL: URL, title: String, target: StreamTarget) {
        self.streamURL = streamURL
        _activeTitle = State(initialValue: title)
        _activeTarget = State(initialValue: target)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlayerHostView(controller: player)
                .ignoresSafeArea()
                .onTapGesture { toggleControls() }

            if player.state == .buffering {
                ProgressView()
                    .scaleEffect(1.4)
                    .tint(.white)
            }

            if player.state == .errored {
                errorOverlay
            }

            if showControls {
                controlsOverlay
            }

            if showNextPrompt, let _ = nextVideo {
                nextEpisodePrompt
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { begin() }
        .onDisappear {
            persistProgress(force: true)
            player.stop()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                persistProgress(force: true)
            }
        }
        .onReceive(uiTimer) { _ in
            tick()
        }
    }

    // MARK: - Lifecycle

    private func begin() {
        guard !resumeApplied else { return }
        resumeApplied = true

        let offset = resumeOffset()
        player.load(url: streamURL, startAt: offset)

        scheduleControlsHide()
        loadNextEpisodeCandidate()
    }

    private func resumeOffset() -> TimeInterval {
        guard let item = LibraryStore.shared.item(id: activeTarget.metaId),
              let state = item.state else { return 0 }
        let sameVideo: Bool
        if let videoId = activeTarget.videoId {
            sameVideo = state.videoId == videoId
        } else {
            sameVideo = state.videoId == nil || state.videoId?.hasPrefix(activeTarget.metaId + ":") != true
        }
        guard sameVideo, let offset = state.timeOffset, offset > 30_000 else { return 0 }
        return offset / 1000
    }

    private func loadNextEpisodeCandidate() {
        guard activeTarget.type == "series", let currentVideoId = activeTarget.videoId else { return }
        let candidateTarget = activeTarget
        Task {
            let meta = try? await AddonClient.shared.metaDetail(
                base: candidateTarget.base, type: "series", id: candidateTarget.metaId
            )
            let videos = (meta?.videos ?? []).sorted {
                ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0)
            }
            guard let currentIndex = videos.firstIndex(where: { $0.id == currentVideoId }),
                  currentIndex + 1 < videos.count else { return }
            await MainActor.run {
                nextVideo = videos[currentIndex + 1]
            }
        }
    }

    // MARK: - Tick / sync

    private func tick() {
        syncCounter += 1
        let ratio = player.duration > 0 ? player.currentTime / player.duration : 0

        if ratio >= 0.9 {
            if !markedWatched, let authKey = AuthStore.shared.authKey {
                markedWatched = true
                let watchedTarget = activeTarget
                let previous = persistenceTask
                persistenceTask = Task {
                    await previous?.value
                    await LibraryStore.shared.markWatched(
                        authKey: authKey,
                        metaId: watchedTarget.metaId,
                        videoId: watchedTarget.videoId
                    )
                }
            }
        } else if syncCounter % 10 == 0, player.isPlaying || player.state == .paused {
            persistProgress(force: false)
        }

        if player.state == .ended, nextVideo != nil {
            showNextPrompt = true
        }

        if player.isPlaying && showControls {
            scheduleControlsHide()
        } else if !player.isPlaying {
            controlsHideTask?.cancel()
            showControls = true
        }
    }

    private func persistProgress(force: Bool) {
        guard player.duration > 5, player.state != .errored else { return }
        guard !markedWatched else { return }
        guard force || player.currentTime > 5 else { return }
        guard let authKey = AuthStore.shared.authKey else { return }
        let offset = player.currentTime
        let duration = player.duration
        let progressTarget = activeTarget
        let previous = persistenceTask
        persistenceTask = Task {
            await previous?.value
            await LibraryStore.shared.saveProgress(
                authKey: authKey,
                metaId: progressTarget.metaId,
                videoId: progressTarget.videoId,
                offset: offset * 1000,
                duration: duration * 1000
            )
        }
    }

    // MARK: - Controls

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls.toggle()
        }
        if showControls {
            scheduleControlsHide()
        }
    }

    private func scheduleControlsHide() {
        controlsHideTask?.cancel()
        controlsHideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                showControls = false
            }
        }
    }

    private func playNext() {
        guard let next = nextVideo else { return }
        persistProgress(force: true)
        showNextPrompt = false
        let nextTarget = StreamTarget(
            metaId: activeTarget.metaId,
            type: "series",
            title: next.displayTitle,
            videoId: next.id,
            base: activeTarget.base
        )

        Task {
            let streams = StreamEngine()
            await streams.load(target: nextTarget)
            guard let best = streams.streams.first(where: \.playable) ?? streams.streams.first,
                  let urlString = best.raw.url, let url = URL(string: urlString) else { return }
            await MainActor.run {
                markedWatched = false
                syncCounter = 0
                resumeApplied = true
                nextVideo = nil
                activeTitle = next.displayTitle
                activeTarget = nextTarget
                player.load(url: url, startAt: 0)
                loadNextEpisodeCandidate()
            }
        }
    }

    // MARK: - Overlay views

    private var controlsOverlay: some View {
        VStack {
            topBar
            Spacer()
            centerControls
            Spacer()
            seekBar
        }
        .padding(.horizontal, 16)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.45), in: Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(activeTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let videoId = activeTarget.videoId {
                    Text(videoId.components(separatedBy: ":").suffix(2).joined(separator: " · ").replacingOccurrences(of: ":", with: " "))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            Spacer()
            Menu {
                ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                    Button(String(format: "%.2fx", speed)) {
                        player.setRate(Float(speed))
                    }
                }
            } label: {
                Text(String(format: "%.2fx", player.rate))
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(.black.opacity(0.45), in: Capsule())
            }
        }
        .padding(.top, 8)
    }

    private var centerControls: some View {
        HStack(spacing: 44) {
            Button {
                player.seek(by: -10)
            } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(.white)
            }

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 68))
                    .foregroundColor(.white)
            }

            Button {
                if nextVideo != nil {
                    playNext()
                } else {
                    player.seek(by: 10)
                }
            } label: {
                Image(systemName: nextVideo != nil ? "forward.end.fill" : "goforward.10")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(nextVideo != nil ? Theme.accent : .white)
            }
        }
    }

    private var seekBar: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { player.duration > 0 ? player.currentTime / player.duration : 0 },
                    set: { fraction in
                        player.seek(to: fraction * player.duration)
                    }
                ),
                in: 0...1
            )
            .tint(Theme.accent)

            HStack {
                Text(timeString(player.currentTime))
                Spacer()
                if nextVideo != nil {
                    Button("Next: \(nextVideo!.displayTitle)") {
                        playNext()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.accent)
                    .lineLimit(1)
                    Spacer()
                }
                Text("-\(timeString(max(player.duration - player.currentTime, 0)))")
            }
            .font(.caption.monospacedDigit())
            .foregroundColor(.white.opacity(0.85))
        }
        .padding(.bottom, 14)
    }

    private var errorOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundColor(.orange)
            Text("Playback failed")
                .font(.headline)
                .foregroundColor(.white)
            Text("This source could not be decoded. Try another stream.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
    }

    private var nextEpisodePrompt: some View {
        VStack(spacing: 14) {
            Text("Up next")
                .font(.headline)
                .foregroundColor(.white)
            if let next = nextVideo {
                Text(next.displayTitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
            HStack(spacing: 12) {
                Button("Dismiss") { showNextPrompt = false }
                    .buttonStyle(.bordered)
                    .tint(.white)
                Button("Play now") { playNext() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
        .padding(20)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// Bridges a plain UIView into SwiftUI so VLC can render into it.
struct PlayerHostView: UIViewRepresentable {
    let controller: VLCPlayerController

    final class RenderView: UIView {}

    func makeUIView(context: Context) -> UIView {
        let view = RenderView()
        view.backgroundColor = .black
        controller.attach(drawable: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
