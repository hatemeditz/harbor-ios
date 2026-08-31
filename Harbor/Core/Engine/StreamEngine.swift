import Foundation

@MainActor
final class StreamEngine: ObservableObject {
    private struct FetchOutcome {
        let addonId: String
        let streams: [RawStream]?
        let errorCategory: HarborAnalyticsErrorCategory?
    }

    struct AddonProgress: Identifiable {
        let id: String
        let name: String
        var state: State

        enum State {
            case pending
            case done(Int)
            case failed
        }
    }

    @Published var streams: [ScoredStream] = []
    @Published private(set) var availableAddons: [Addon] = []
    @Published var progress: [AddonProgress] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var nextId = 0
    private var loadToken = UUID()
    private var activeTrace: HarborPerformanceTrace?

    /// All addons that declare a `stream` resource usable for this target.
    func streamAddons(for target: StreamTarget) async -> [Addon] {
        let all = await CatalogStore.shared.gatherAddons(authKey: AuthStore.shared.authKey)
        return all.filter { addon in
            guard !(addon.manifest.behaviorHints?.configurationRequired ?? false) else { return false }
            let resources = addon.manifest.resources ?? []
            let hasStreamResource = resources.contains { resource in
                switch resource {
                case .named(let name):
                    return name == "stream"
                case .detailed(let def):
                    if def.name != "stream" { return false }
                    if let types = def.types, !types.isEmpty, !types.contains(target.type) { return false }
                    return true
                }
            }
            guard hasStreamResource else { return false }

            if let types = addon.manifest.types, !types.isEmpty, !types.contains(target.type) {
                return false
            }
            if let prefixes = addon.manifest.idPrefixes, !prefixes.isEmpty,
               !prefixes.contains(where: { target.metaId.hasPrefix($0) }) {
                return false
            }
            return true
        }
    }

    func load(target: StreamTarget) async {
        activeTrace?.stop(outcome: "cancelled", metrics: [.success: 0])
        loadToken = UUID()
        let token = loadToken
        let operationToken = AnalyticsService.shared.beginOperation(.streams)
        defer { AnalyticsService.shared.endOperation(operationToken) }
        let startedAt = Date()
        let trace = AnalyticsService.shared.startTrace(
            .streamFetch,
            attributes: [.mediaType: HarborMediaType(target.type).rawValue]
        )
        activeTrace = trace
        isLoading = true
        streams = []
        progress = []
        errorMessage = nil
        nextId = 0

        let baseParameters = AnalyticsService.shared.mediaParameters(
            mediaType: target.type,
            mediaId: target.metaId,
            source: target.analyticsSource,
            playbackSessionId: target.playbackSessionId,
            seasonNumber: target.seasonNumber,
            episodeNumber: target.episodeNumber
        )
        AnalyticsService.shared.log(.streamFetchStarted, parameters: baseParameters)

        let stremioId = target.videoId ?? target.metaId
        let addons = await streamAddons(for: target)
        guard token == loadToken else {
            trace.stop(outcome: "cancelled", metrics: [.success: 0])
            return
        }
        availableAddons = addons

        if let syncError = CatalogStore.shared.errorMessage {
            errorMessage = "Could not sync the addons in your Stremio account: \(syncError)"
        }

        progress = addons.map { addon in
            AddonProgress(id: addon.id, name: addon.manifest.name, state: .pending)
        }

        guard !addons.isEmpty else {
            isLoading = false
            var parameters = baseParameters
            parameters[.addonCount] = .int(0)
            parameters[.streamCount] = .int(0)
            parameters[.fetchDurationMs] = .int(AnalyticsService.milliseconds(since: startedAt))
            parameters[.errorType] = .string(HarborAnalyticsErrorCategory.noAddons.rawValue)
            AnalyticsService.shared.log(.streamFetchFailed, parameters: parameters)
            trace.stop(
                outcome: "failure",
                attributes: [.errorCategory: HarborAnalyticsErrorCategory.noAddons.rawValue],
                metrics: [.success: 0, .addonCount: 0, .streamCount: 0]
            )
            if activeTrace === trace { activeTrace = nil }
            return
        }

        var didLogSuccess = false
        await withTaskGroup(of: FetchOutcome.self) { group in
            for addon in addons {
                group.addTask {
                    do {
                        let response: StreamResponse = try await AddonClient.shared.fetchJSON(
                            try AddonClient.streamURL(
                                base: AddonClient.baseURL(for: addon.transportUrl),
                                type: target.type,
                                id: stremioId
                            )
                        )
                        return FetchOutcome(
                            addonId: addon.id,
                            streams: response.streams,
                            errorCategory: nil
                        )
                    } catch {
                        return FetchOutcome(
                            addonId: addon.id,
                            streams: nil,
                            errorCategory: HarborAnalyticsErrorCategory.classify(error)
                        )
                    }
                }
            }

            for await outcome in group {
                guard token == loadToken else { return }
                let ok = outcome.errorCategory == nil
                if let index = progress.firstIndex(where: { $0.id == outcome.addonId }) {
                    progress[index].state = ok ? .done(outcome.streams?.count ?? 0) : .failed
                }

                var batch: [ScoredStream] = []
                for var raw in (outcome.streams ?? []) {
                    raw.addonId = outcome.addonId
                    raw.addonName = progress.first { $0.id == outcome.addonId }?.name
                    nextId += 1
                    if let scored = StreamScorer.score(raw: raw, id: nextId) {
                        batch.append(scored)
                    }
                }
                streams = StreamScorer.sort(streams + batch)
            }
        }

        if token == loadToken {
            if streams.isEmpty,
               !progress.isEmpty,
               progress.allSatisfy({
                   if case .failed = $0.state { return true }
                   return false
               }) {
                errorMessage = "Your Stremio stream addons synced, but none of them could be reached."
            }
            isLoading = false

            if !streams.isEmpty {
                didLogSuccess = true
                var parameters = baseParameters
                parameters[.streamCount] = .int(streams.count)
                parameters[.addonCount] = .int(addons.count)
                parameters[.addonSuccessCount] = .int(successCount)
                parameters[.addonFailureCount] = .int(failureCount)
                parameters[.fetchDurationMs] = .int(AnalyticsService.milliseconds(since: startedAt))
                AnalyticsService.shared.log(.streamFetchSuccess, parameters: parameters)
            } else {
                let category: HarborAnalyticsErrorCategory = failureCount == addons.count
                    ? .allAddonsFailed
                    : .noStreams
                var parameters = baseParameters
                parameters[.streamCount] = .int(0)
                parameters[.addonCount] = .int(addons.count)
                parameters[.addonSuccessCount] = .int(successCount)
                parameters[.addonFailureCount] = .int(failureCount)
                parameters[.fetchDurationMs] = .int(AnalyticsService.milliseconds(since: startedAt))
                parameters[.errorType] = .string(category.rawValue)
                AnalyticsService.shared.log(.streamFetchFailed, parameters: parameters)
                if category == .allAddonsFailed {
                    AnalyticsService.shared.recordNonFatal(
                        .streamFetch,
                        category: category,
                        context: HarborErrorContext(
                            screen: .streams,
                            operation: .streams,
                            mediaType: HarborMediaType(target.type)
                        )
                    )
                }
            }
            trace.stop(
                outcome: didLogSuccess ? "success" : "failure",
                attributes: didLogSuccess ? [:] : [
                    .errorCategory: (failureCount == addons.count
                        ? HarborAnalyticsErrorCategory.allAddonsFailed
                        : HarborAnalyticsErrorCategory.noStreams).rawValue,
                ],
                metrics: [
                    .success: didLogSuccess ? 1 : 0,
                    .streamCount: Int64(streams.count),
                    .addonCount: Int64(addons.count),
                    .failureCount: Int64(failureCount),
                ]
            )
            if activeTrace === trace { activeTrace = nil }
        } else {
            trace.stop(outcome: "cancelled", metrics: [.success: 0])
        }
    }

    func cancel() {
        loadToken = UUID()
        activeTrace?.stop(outcome: "cancelled", metrics: [.success: 0])
        activeTrace = nil
        isLoading = false
    }

    private var successCount: Int {
        progress.filter {
            if case .done = $0.state { return true }
            return false
        }.count
    }

    private var failureCount: Int {
        progress.filter {
            if case .failed = $0.state { return true }
            return false
        }.count
    }
}
