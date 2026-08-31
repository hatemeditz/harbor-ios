import SwiftUI

struct AdaptiveMediaRail: View {
    let title: String
    var subtitle: String?
    let metas: [Meta]
    var source: HarborNavigationSource = .search
    var ranked = false

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var posterWidth: CGFloat { horizontalSizeClass == .regular ? 148 : 116 }
    private var horizontalPadding: CGFloat { horizontalSizeClass == .regular ? 28 : 16 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HarborSectionHeader(title: title, subtitle: subtitle)
                .padding(.horizontal, horizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .bottom, spacing: ranked ? 5 : 13) {
                    ForEach(Array(metas.prefix(ranked ? 10 : 24).enumerated()), id: \.element.id) { index, meta in
                        NavigationLink(value: MetaNavigation(meta: meta, base: nil, source: source)) {
                            if ranked {
                                rankedCard(meta: meta, rank: index + 1)
                            } else {
                                PosterCard(meta: meta, width: posterWidth)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, horizontalPadding)
            }
        }
    }

    private func rankedCard(meta: Meta, rank: Int) -> some View {
        let numberWidth: CGFloat = horizontalSizeClass == .regular ? 102 : 76
        let cardWidth: CGFloat = horizontalSizeClass == .regular ? 136 : 105
        return ZStack(alignment: .bottomLeading) {
            Text("\(rank)")
                .font(.system(size: horizontalSizeClass == .regular ? 144 : 108, weight: .black, design: .rounded))
                .foregroundColor(Theme.background)
                .shadow(color: .white.opacity(0.5), radius: 1.2)
                .frame(width: numberWidth, alignment: .leading)
                .offset(y: 5)

            PosterCard(meta: meta, width: cardWidth, showTitle: false)
                .offset(x: numberWidth * 0.54)
        }
        .frame(
            width: cardWidth + numberWidth * 0.54,
            height: cardWidth * 1.5,
            alignment: .bottomLeading
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Number \(rank), \(meta.name)")
    }
}

struct TMDBStreamingProvidersRow: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HarborSectionHeader(
                title: "Your Streaming",
                subtitle: "Popular titles available in your region"
            )
            .padding(.horizontal, horizontalSizeClass == .regular ? 28 : 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 11) {
                    ForEach(TMDBStreamingProvider.all) { provider in
                        NavigationLink {
                            TMDBServiceView(provider: provider)
                        } label: {
                            TMDBProviderCard(provider: provider)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, horizontalSizeClass == .regular ? 28 : 16)
            }
        }
    }
}

private struct TMDBProviderCard: View {
    let provider: TMDBStreamingProvider
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(harborHex: provider.tintHex).opacity(0.95), Theme.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 10) {
                Text(provider.shortMark)
                    .font(.system(size: provider.shortMark.count <= 2 ? 30 : 21, weight: .black, design: .rounded))
                    .foregroundColor(provider.id == "apple" ? .black : .white)
                Spacer(minLength: 0)
                Text(provider.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)
                Label("Explore", systemImage: "arrow.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white.opacity(0.72))
            }
            .padding(14)
        }
        .frame(
            width: horizontalSizeClass == .regular ? 190 : 152,
            height: horizontalSizeClass == .regular ? 118 : 96
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border, lineWidth: 1))
        .accessibilityLabel("Popular on \(provider.name)")
    }
}

struct TMDBGenreRow: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HarborSectionHeader(
                title: "Browse by Genre",
                subtitle: "Find the mood you want"
            )
            .padding(.horizontal, horizontalSizeClass == .regular ? 28 : 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(TMDBGenreDefinition.all) { genre in
                        NavigationLink {
                            TMDBCollectionView(definition: genre.collection)
                        } label: {
                            genreTile(genre)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, horizontalSizeClass == .regular ? 28 : 16)
            }
        }
    }

    private func genreTile(_ genre: TMDBGenreDefinition) -> some View {
        let width: CGFloat = horizontalSizeClass == .regular ? 220 : 168
        return ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(harborHex: genre.tintHex), Color(harborHex: genre.tintHex).opacity(0.38), Theme.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: genre.symbol)
                .font(.system(size: 62, weight: .bold))
                .foregroundColor(.white.opacity(0.12))
                .offset(x: width * 0.52, y: -20)
            HStack(alignment: .bottom) {
                Text(genre.name)
                    .font(.system(size: horizontalSizeClass == .regular ? 24 : 20, weight: .bold, design: .serif))
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.75))
            }
            .padding(15)
        }
        .frame(width: width, height: width * 0.68)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border, lineWidth: 1))
    }
}

struct TMDBKeyPrompt: View {
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "key.fill")
                .font(.title2)
                .foregroundColor(Theme.accent)
            Text("Unlock richer discovery")
                .font(.system(size: compact ? 19 : 24, weight: .bold, design: .serif))
            Text("Add a free TMDB API key for weekly trends, top-rated collections, genres and streaming-service charts. The key stays in the device Keychain and is never sent to analytics.")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink {
                TMDBSetupView()
            } label: {
                Label("Connect TMDB", systemImage: "arrow.right")
            }
            .buttonStyle(HarborPrimaryButtonStyle())
        }
        .padding(compact ? 16 : 20)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border, lineWidth: 1))
    }
}

struct TMDBSetupView: View {
    @ObservedObject private var settings = TMDBSettingsStore.shared
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HarborPageHeader(
                    title: "Connect TMDB",
                    eyebrow: "Metadata",
                    subtitle: "Unlock weekly trends and curated discovery"
                )

                VStack(alignment: .leading, spacing: 12) {
                    Label("Your key stays on this device", systemImage: "lock.shield.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.accent)
                    Text("Harbor stores the key in Keychain. It is used only for requests to api.themoviedb.org and is never included in analytics or crash reports.")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(16)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 10) {
                    Text("TMDB v3 API key")
                        .font(.caption.weight(.bold))
                        .foregroundColor(Theme.textSecondary)
                    SecureField("Paste API key", text: $draft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.border, lineWidth: 1))
                    if let error = settings.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        guard let url = URL(string: "https://www.themoviedb.org/settings/api") else { return }
                        openURL(url)
                    } label: {
                        Label("Get a free key", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(HarborSecondaryButtonStyle())

                    Button {
                        Task {
                            if await settings.verifyAndSave(draft) {
                                await TMDBCatalogStore.shared.loadDiscovery(
                                    apiKey: settings.apiKey,
                                    region: UserDefaults.standard.string(forKey: "harbor.region") ?? "US",
                                    force: true
                                )
                                dismiss()
                            }
                        }
                    } label: {
                        if settings.validationState == .checking {
                            ProgressView().tint(.black)
                        } else {
                            Label("Verify & Save", systemImage: "checkmark")
                        }
                    }
                    .buttonStyle(HarborPrimaryButtonStyle())
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || settings.validationState == .checking)
                }

                if settings.hasAPIKey {
                    Button("Remove saved TMDB key", role: .destructive) {
                        settings.removeAPIKey()
                        draft = ""
                    }
                    .font(.subheadline)
                }
            }
            .frame(maxWidth: 660, alignment: .leading)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("TMDB")
        .harborNavigationChrome()
        .onAppear { draft = settings.apiKey }
    }
}

@MainActor
private final class TMDBCollectionViewModel: ObservableObject {
    @Published var metas: [Meta] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(definition: TMDBCollectionDefinition, apiKey: String, region: String) async {
        guard !apiKey.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            metas = try await TMDBClient.shared.collection(
                apiKey: apiKey,
                definition: definition,
                region: region
            )
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "TMDB is unavailable."
        }
    }
}

struct TMDBCollectionView: View {
    let definition: TMDBCollectionDefinition
    @StateObject private var viewModel = TMDBCollectionViewModel()
    @ObservedObject private var settings = TMDBSettingsStore.shared
    @AppStorage("harbor.region") private var region = "US"
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: horizontalSizeClass == .regular ? 148 : 108), spacing: 14)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HarborPageHeader(
                    title: definition.title,
                    eyebrow: "Discover",
                    subtitle: definition.subtitle
                )
                .padding(.horizontal, 20)

                if viewModel.isLoading && viewModel.metas.isEmpty {
                    ProgressView().tint(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 80)
                } else if let error = viewModel.errorMessage, viewModel.metas.isEmpty {
                    ContentUnavailableCompat(icon: "wifi.exclamationmark", title: "Couldn’t load collection", message: error)
                        .frame(minHeight: 320)
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(viewModel.metas) { meta in
                            NavigationLink(value: MetaNavigation(meta: meta, base: nil, source: .search)) {
                                PosterCard(meta: meta, width: horizontalSizeClass == .regular ? 148 : 108)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 16)
        }
        .background(Theme.background)
        .navigationTitle(definition.title)
        .harborNavigationChrome()
        .task { await viewModel.load(definition: definition, apiKey: settings.apiKey, region: region) }
    }
}

@MainActor
private final class TMDBServiceViewModel: ObservableObject {
    @Published var catalog = TMDBServiceCatalog(movies: [], series: [])
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(provider: TMDBStreamingProvider, apiKey: String, region: String) async {
        guard !apiKey.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            catalog = try await TMDBClient.shared.serviceCatalog(
                apiKey: apiKey,
                provider: provider,
                region: region
            )
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "TMDB is unavailable."
        }
    }
}

struct TMDBServiceView: View {
    private enum Scope: String, CaseIterable, Identifiable {
        case all = "All"
        case movies = "Movies"
        case series = "Series"
        var id: String { rawValue }
    }

    let provider: TMDBStreamingProvider
    @StateObject private var viewModel = TMDBServiceViewModel()
    @ObservedObject private var settings = TMDBSettingsStore.shared
    @AppStorage("harbor.region") private var region = "US"
    @State private var scope: Scope = .all
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                serviceHeader
                scopePicker

                if !settings.hasAPIKey {
                    TMDBKeyPrompt()
                        .padding(.horizontal, 20)
                } else if viewModel.isLoading && viewModel.catalog.movies.isEmpty && viewModel.catalog.series.isEmpty {
                    ProgressView().tint(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 90)
                } else if let error = viewModel.errorMessage,
                          viewModel.catalog.movies.isEmpty,
                          viewModel.catalog.series.isEmpty {
                    ContentUnavailableCompat(icon: "wifi.exclamationmark", title: "Couldn’t load \(provider.name)", message: error)
                        .frame(minHeight: 320)
                } else {
                    if scope != .series, !viewModel.catalog.movies.isEmpty {
                        AdaptiveMediaRail(
                            title: "Top 10 Movies on \(provider.name)",
                            subtitle: "Ranked by TMDB popularity in \(region)",
                            metas: viewModel.catalog.movies,
                            source: .home,
                            ranked: true
                        )
                    }
                    if scope != .movies, !viewModel.catalog.series.isEmpty {
                        AdaptiveMediaRail(
                            title: "Top 10 Series on \(provider.name)",
                            subtitle: "Ranked by TMDB popularity in \(region)",
                            metas: viewModel.catalog.series,
                            source: .home,
                            ranked: true
                        )
                    }
                    if scope != .series, viewModel.catalog.movies.count > 10 {
                        AdaptiveMediaRail(
                            title: "More Movies",
                            metas: Array(viewModel.catalog.movies.dropFirst(10)),
                            source: .home
                        )
                    }
                    if scope != .movies, viewModel.catalog.series.count > 10 {
                        AdaptiveMediaRail(
                            title: "More Series",
                            metas: Array(viewModel.catalog.series.dropFirst(10)),
                            source: .home
                        )
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .background(Theme.background)
        .navigationTitle(provider.name)
        .harborNavigationChrome()
        .task { await viewModel.load(provider: provider, apiKey: settings.apiKey, region: region) }
    }

    private var serviceHeader: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(harborHex: provider.tintHex).opacity(0.5), Theme.background],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 8) {
                Text("POPULAR ON")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(2.2)
                    .foregroundColor(.white.opacity(0.65))
                Text(provider.name)
                    .font(.system(size: horizontalSizeClass == .regular ? 46 : 34, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("Popular movies and series available on \(provider.name) right now in \(region), ranked by TMDB popularity.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.72))
                Text("Streaming availability data by JustWatch")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(22)
        }
        .frame(height: horizontalSizeClass == .regular ? 230 : 190)
    }

    private var scopePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Scope.allCases) { item in
                    HarborFilterPill(title: item.rawValue, selected: scope == item) {
                        scope = item
                    }
                }
            }
            .padding(.horizontal, horizontalSizeClass == .regular ? 28 : 16)
        }
    }
}
