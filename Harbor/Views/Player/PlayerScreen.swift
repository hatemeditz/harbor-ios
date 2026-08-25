import SwiftUI
import UIKit

struct PlayerScreen: View {
    let streamURL: URL

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var player = VLCPlayerController.shared
    @StateObject private var subtitleEngine = SubtitleEngine()

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
    @State private var showPlaybackOptions = false

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

            if player.isBuffering {
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
            controlsHideTask?.cancel()
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
        .onChange(of: player.state) { state in
            handlePlaybackState(state)
        }
        .onChange(of: showPlaybackOptions) { isShowing in
            if !isShowing, player.isPlaying, showControls {
                scheduleControlsHide()
            }
        }
        .sheet(isPresented: $showPlaybackOptions) {
            PlayerOptionsSheet(player: player, subtitleEngine: subtitleEngine)
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
        let target = activeTarget
        Task {
            await subtitleEngine.load(target: target)
        }
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
        player.poll()
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
                        target: watchedTarget
                    )
                }
            }
        } else if syncCounter % 10 == 0, player.isPlaying || player.state == .paused {
            persistProgress(force: false)
        }

        if player.state == .ended, nextVideo != nil {
            showNextPrompt = true
        }

    }

    private func handlePlaybackState(_ state: VLCPlayerController.PlayState) {
        switch state {
        case .playing:
            if showControls { scheduleControlsHide() }
        case .paused, .ended, .errored:
            controlsHideTask?.cancel()
            withAnimation(.easeInOut(duration: 0.2)) {
                showControls = true
            }
        case .idle, .buffering, .stopped:
            break
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
                target: progressTarget,
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
            base: activeTarget.base,
            metaName: activeTarget.metaName,
            poster: activeTarget.poster,
            background: activeTarget.background
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
                showControls = true
                scheduleControlsHide()
                loadNextEpisodeCandidate()
                Task {
                    await subtitleEngine.load(target: nextTarget)
                }
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
                ForEach([0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 3.5, 4.0], id: \.self) { speed in
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

            Button {
                controlsHideTask?.cancel()
                showPlaybackOptions = true
            } label: {
                Image(systemName: "captions.bubble.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.45), in: Circle())
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
                if let nextVideo {
                    Button("Next: \(nextVideo.displayTitle)") {
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

@MainActor
struct PlayerOptionsSheet: View {
    @ObservedObject var player: VLCPlayerController
    @ObservedObject var subtitleEngine: SubtitleEngine

    @Environment(\.dismiss) private var dismiss
    @State private var subtitleScale: Double
    @State private var subtitleVerticalPosition: Double
    @State private var isSelectingSubtitle = false
    @State private var selectionError: String?
    @State private var embeddedLanguageCodeByTrackID: [Int32: String]

    private let speeds: [Float] = [
        0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 3.5, 4.0,
    ]

    init(player: VLCPlayerController, subtitleEngine: SubtitleEngine) {
        self.player = player
        self.subtitleEngine = subtitleEngine
        _subtitleScale = State(initialValue: player.subtitleScale)
        _subtitleVerticalPosition = State(initialValue: player.subtitleVerticalPosition)
        _embeddedLanguageCodeByTrackID = State(
            initialValue: Self.resolveEmbeddedLanguageCodes(player.subtitleTracks)
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                playbackSection
                audioSection
                subtitleSection
                subtitleTimingSection
            }
            .navigationTitle("Playback options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: player.subtitleTracks) { tracks in
                embeddedLanguageCodeByTrackID = Self.resolveEmbeddedLanguageCodes(tracks)
            }
        }
    }

    private var playbackSection: some View {
        Section("Playback speed") {
            Picker("Speed", selection: Binding(
                get: { player.rate },
                set: { player.setRate($0) }
            )) {
                ForEach(speeds, id: \.self) { speed in
                    Text(String(format: "%.2fx", speed)).tag(speed)
                }
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private var audioSection: some View {
        Section("Audio track") {
            if player.audioTracks.isEmpty {
                Text("No selectable embedded audio tracks detected yet.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(player.audioTracks) { track in
                    Button {
                        player.selectAudioTrack(track)
                    } label: {
                        optionLabel(track.name, selected: player.selectedAudioTrackId == track.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var subtitleSection: some View {
        Section("Subtitle language") {
            Button {
                player.disableSubtitles()
                selectionError = nil
            } label: {
                optionLabel("Off", selected: player.selectedSubtitleTrackId == -1
                    && player.selectedExternalSubtitleLabel == nil)
            }

            if subtitleEngine.isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading installed subtitle addons")
                        .foregroundColor(.secondary)
                }
            }

            ForEach(languageCodes, id: \.self) { code in
                Menu {
                    Button("Automatic · embedded first") {
                        selectPreferredSource(for: code)
                    }

                    ForEach(embeddedTracks(for: code)) { track in
                        Button("Embedded · \(track.name)") {
                            player.selectEmbeddedSubtitle(track)
                            selectionError = nil
                        }
                    }

                    ForEach(subtitleEngine.options(for: code)) { subtitle in
                        Button("\(subtitle.addonName) · \(subtitle.displayName)") {
                            selectExternal(subtitle)
                        }
                    }
                } label: {
                    HStack {
                        Text(SubtitleLanguages.displayName(for: code))
                        Spacer()
                        Text(sourceSummary(for: code))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let selected = player.selectedExternalSubtitleLabel {
                Label(selected, systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if isSelectingSubtitle {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Preparing subtitle")
                }
            }

            if let error = selectionError ?? player.subtitleError ?? subtitleEngine.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundColor(.orange)
            } else if !subtitleEngine.isLoading, subtitleEngine.addonNames.isEmpty,
                      externalLanguageCodes.isEmpty {
                Text("No installed subtitle addons support this title.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var subtitleTimingSection: some View {
        Section("Subtitle appearance") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Delay")
                    Spacer()
                    Text(String(format: "%+.2f s", player.subtitleDelay))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                Slider(value: Binding(
                    get: { player.subtitleDelay },
                    set: { player.setSubtitleDelay($0) }
                ), in: -10...10, step: 0.25)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Size")
                    Spacer()
                    Text("\(Int(subtitleScale))%")
                        .foregroundColor(.secondary)
                }
                Slider(value: $subtitleScale, in: 50...200, step: 5)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Vertical position")
                    Spacer()
                    Text("\(Int(subtitleVerticalPosition)) px higher")
                        .foregroundColor(.secondary)
                }
                Slider(value: $subtitleVerticalPosition, in: 0...300, step: 10)
            }

            Button("Apply size and position") {
                player.applySubtitleAppearance(
                    scale: subtitleScale,
                    verticalPosition: subtitleVerticalPosition
                )
            }

            Text("Applying size or position reloads the current stream at the same timestamp. Delay changes apply immediately.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var externalLanguageCodes: Set<String> {
        Set(subtitleEngine.subtitles.map(\.languageCode))
    }

    private var languageCodes: [String] {
        Set(embeddedLanguageCodeByTrackID.values).union(externalLanguageCodes).sorted {
            SubtitleLanguages.displayName(for: $0)
                .localizedCaseInsensitiveCompare(SubtitleLanguages.displayName(for: $1)) == .orderedAscending
        }
    }

    private func embeddedTracks(for code: String) -> [PlayerMediaTrack] {
        player.subtitleTracks.filter {
            $0.id >= 0 && embeddedLanguageCodeByTrackID[$0.id] == code
        }
    }

    private static func resolveEmbeddedLanguageCodes(
        _ tracks: [PlayerMediaTrack]
    ) -> [Int32: String] {
        Dictionary(uniqueKeysWithValues: tracks.compactMap { track in
            guard track.id >= 0,
                  let code = SubtitleLanguages.code(forTrackName: track.name) else { return nil }
            return (track.id, code)
        })
    }

    private func sourceSummary(for code: String) -> String {
        let embeddedCount = embeddedTracks(for: code).count
        let addonResults = subtitleEngine.options(for: code)
        let addonCount = Set(addonResults.map(\.addonId)).count
        var parts: [String] = []
        if embeddedCount > 0 { parts.append("embedded") }
        if addonCount > 0 { parts.append("\(addonCount) addon\(addonCount == 1 ? "" : "s")") }
        return parts.joined(separator: " + ")
    }

    private func selectPreferredSource(for code: String) {
        if let embedded = embeddedTracks(for: code).first {
            player.selectEmbeddedSubtitle(embedded)
            selectionError = nil
        } else if let external = subtitleEngine.options(for: code).first {
            selectExternal(external)
        } else {
            selectionError = "No subtitle is available for this language."
        }
    }

    private func selectExternal(_ subtitle: AddonSubtitle) {
        isSelectingSubtitle = true
        selectionError = nil
        Task {
            do {
                let localURL = try await subtitleEngine.cachedFile(for: subtitle)
                guard !Task.isCancelled else { return }
                player.selectExternalSubtitle(
                    url: localURL,
                    label: "\(SubtitleLanguages.displayName(for: subtitle.languageCode)) · \(subtitle.addonName)"
                )
            } catch {
                selectionError = "Could not download this subtitle: \(error.localizedDescription)"
            }
            isSelectingSubtitle = false
        }
    }

    private func optionLabel(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            if selected {
                Image(systemName: "checkmark")
            }
        }
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
