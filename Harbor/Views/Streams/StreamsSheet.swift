import SwiftUI

struct StreamsSheet: View {
    let target: StreamTarget

    @StateObject private var engine = StreamEngine()
    @State private var playingStream: ScoredStream?

    private let tierColors: [String: Color] = [
        "4K": .purple,
        "1080p": Theme.accent,
        "720p": .teal,
        "SD": Color(white: 0.45),
        "?": Color(white: 0.3),
    ]

    var body: some View {
        Group {
            if engine.isLoading && engine.streams.isEmpty {
                loadingState
            } else if engine.streams.isEmpty {
                emptyState
            } else {
                streamList
            }
        }
        .background(Theme.background)
        .navigationTitle("Streams")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: target) {
            await engine.load(target: target)
        }
        .fullScreenCover(item: $playingStream) { stream in
            Group {
                if let urlString = stream.raw.url, let url = URL(string: urlString) {
                    PlayerScreen(streamURL: url, title: target.title, target: target)
                } else {
                    Color.black.ignoresSafeArea()
                }
            }
        }
    }

    private var subtitle: String {
        let done = engine.progress.filter {
            if case .done = $0.state { return true }
            return false
        }.count
        return "\(target.title) · \(engine.streams.count) sources · \(done)/\(engine.progress.count) addons"
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView().tint(Theme.accent)
            Text("Querying \(engine.progress.count) addons")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(Theme.textSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: engine.errorMessage == nil ? "water.waves.slash" : "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(Theme.textSecondary)
            Text(emptyTitle)
                .font(.title3.bold())
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        if engine.errorMessage != nil { return "Could not load streams" }
        if engine.progress.isEmpty { return "No stream addons available" }
        return "No streams found"
    }

    private var emptyMessage: String {
        if let error = engine.errorMessage { return error }
        if engine.progress.isEmpty {
            return "Harbor automatically uses streaming addons installed in your Stremio account. Install or configure one in Stremio on any device, then try again."
        }
        return "Your \(engine.progress.count) synced streaming addon(s) returned no sources for this title."
    }

    private var streamList: some View {
            ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(engine.streams) { scored in
                    StreamRow(scored: scored, tierColor: tierColors[scored.tierLabel] ?? Color(white: 0.3))
                        .onTapGesture {
                            guard scored.playable else { return }
                            playingStream = scored
                        }
                }

                if engine.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().tint(Theme.accent)
                        Text("More results incoming")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                    .padding(.top, 6)
                }
            }
            .padding(14)
        }
    }
}

struct StreamRow: View {
    let scored: ScoredStream
    let tierColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(scored.tierLabel)
                .font(.system(size: 11, weight: .heavy))
                .frame(width: 44)
                .padding(.vertical, 5)
                .background(tierColor.opacity(0.25), in: RoundedRectangle(cornerRadius: 7))
                .foregroundColor(tierColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(StreamScorer.cleanTitle(scored.raw.title ?? scored.raw.description ?? "Stream"))
                    .font(.footnote.weight(.medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Label(scored.raw.addonName ?? "", systemImage: "puzzlepiece.extension")
                        .lineLimit(1)

                    if let size = scored.parsed.sizeGB {
                        Text(String(format: "%.1f GB", size))
                    }

                    if let seeders = scored.parsed.seeders {
                        Label("\(seeders)", systemImage: "person.2")
                    }

                    if scored.parsed.hdr != .none {
                        Text(scored.parsed.hdr.rawValue)
                            .foregroundColor(.orange)
                    }

                    if scored.parsed.hasAtmos || scored.parsed.isLosslessAudio {
                        Image(systemName: "hifispeaker.2.fill")
                            .foregroundColor(.pink)
                    }
                }
                .font(.system(size: 10))
                .foregroundColor(Theme.textSecondary)
            }

            Spacer(minLength: 0)

            Image(systemName: scored.playable ? "play.circle.fill" : "link.circle")
                .font(.system(size: 24))
                .foregroundColor(scored.playable ? Theme.accent : Theme.textSecondary.opacity(0.6))
                .padding(.top, 2)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .opacity(scored.playable ? 1 : 0.65)
    }
}
