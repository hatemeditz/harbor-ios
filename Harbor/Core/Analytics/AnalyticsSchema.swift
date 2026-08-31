import Foundation

/// Version of Harbor's compact analytics contract. Increment only when event
/// semantics or parameter meanings change incompatibly.
enum HarborAnalyticsSchema {
    static let version = 1
}

/// Firebase's automatic events provide users, sessions, engagement, and
/// retention. These custom events measure discovery and playback health.
enum HarborAnalyticsEvent: String, CaseIterable {
    case searchSubmitted = "search_submitted"
    case searchResultsReturned = "search_results_returned"
    case searchResultClicked = "search_result_clicked"
    case searchNoResults = "search_no_results"
    case searchFailed = "search_failed"

    case movieOpened = "movie_opened"
    case seriesOpened = "series_opened"
    case playClicked = "play_clicked"
    case streamFetchStarted = "stream_fetch_started"
    case streamFetchSuccess = "stream_fetch_success"
    case streamFetchFailed = "stream_fetch_failed"
    case streamSelected = "stream_selected"
    case playbackStartRequested = "playback_start_requested"
    case playbackStarted = "playback_started"
    case playbackFailed = "playback_failed"
    case playback90 = "playback_90"
    case playbackCompleted = "playback_completed"
    case playbackStopped = "playback_stopped"

    /// The only parameters accepted for each event. Unknown parameters are
    /// dropped at the centralized boundary before Firebase sees them.
    var allowedParameters: Set<HarborAnalyticsParameter> {
        switch self {
        case .searchSubmitted:
            return [.queryLength, .searchScope]
        case .searchResultsReturned:
            return [.queryLength, .resultCount, .searchScope, .searchDurationMs, .resultType]
        case .searchResultClicked:
            return [.mediaType, .mediaId, .source, .resultPosition, .searchScope]
        case .searchNoResults:
            return [.queryLength, .searchScope, .searchDurationMs]
        case .searchFailed:
            return [.queryLength, .searchScope, .searchDurationMs, .errorType]
        case .movieOpened, .seriesOpened:
            return [.mediaType, .mediaId, .source]
        case .playClicked, .streamFetchStarted, .playbackStartRequested:
            return Self.playbackIdentity
        case .streamFetchSuccess:
            return Self.playbackIdentity.union([
                .streamCount, .addonCount, .addonSuccessCount, .addonFailureCount, .fetchDurationMs,
            ])
        case .streamFetchFailed:
            return Self.playbackIdentity.union([
                .streamCount, .addonCount, .addonSuccessCount, .addonFailureCount,
                .fetchDurationMs, .errorType,
            ])
        case .streamSelected:
            return Self.playbackIdentity.union([
                .streamPosition, .quality, .resolution, .codec, .container,
                .streamType, .providerType,
            ])
        case .playbackStarted:
            return Self.playbackIdentity.union([.playbackStartupMs, .durationBucket])
        case .playbackFailed:
            return Self.playbackIdentity.union([.playbackStartupMs, .watchTimeSeconds, .errorType])
        case .playback90, .playbackCompleted:
            return Self.playbackIdentity.union([.durationBucket, .watchTimeSeconds])
        case .playbackStopped:
            return Self.playbackIdentity.union([
                .durationBucket, .watchTimeSeconds, .progressPercent, .bufferCount,
                .totalBufferSeconds, .stopReason,
            ])
        }
    }

    private static let playbackIdentity: Set<HarborAnalyticsParameter> = [
        .mediaType, .mediaId, .source, .seasonNumber, .episodeNumber, .playbackSessionId,
    ]
}

enum HarborAnalyticsParameter: String, CaseIterable, Hashable {
    case analyticsSchemaVersion = "analytics_schema_version"
    case buildEnvironment = "build_environment"
    case mediaType = "media_type"
    case mediaId = "media_id"
    case source
    case queryLength = "query_length"
    case resultCount = "result_count"
    case resultType = "result_type"
    case resultPosition = "result_position"
    case searchScope = "search_scope"
    case searchDurationMs = "search_duration_ms"
    case seasonNumber = "season_number"
    case episodeNumber = "episode_number"
    case playbackSessionId = "playback_session_id"
    case streamCount = "stream_count"
    case addonCount = "addon_count"
    case addonSuccessCount = "addon_success_count"
    case addonFailureCount = "addon_failure_count"
    case fetchDurationMs = "fetch_duration_ms"
    case streamPosition = "stream_position"
    case quality
    case resolution
    case codec
    case container
    case streamType = "stream_type"
    case providerType = "provider_type"
    case playbackStartupMs = "playback_startup_ms"
    case durationBucket = "duration_bucket"
    case watchTimeSeconds = "watch_time_seconds"
    case progressPercent = "progress_percent"
    case bufferCount = "buffer_count"
    case totalBufferSeconds = "total_buffer_seconds"
    case stopReason = "stop_reason"
    case errorType = "error_type"
}

enum HarborAnalyticsValue: Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
}

typealias HarborAnalyticsParameters = [HarborAnalyticsParameter: HarborAnalyticsValue]

enum HarborScreen: String {
    case login, home, search, library, settings, detail, streams, player, addons
    case debridSetup = "debrid_setup"
}

enum HarborNavigationSource: String, Hashable {
    case home, search, watchlist, continueWatching = "continue_watching", library, unknown
}

enum HarborMediaType: String {
    case movie, series, other

    init(_ value: String) {
        self = HarborMediaType(rawValue: value.lowercased()) ?? .other
    }
}

enum HarborAddonType: String {
    case official, thirdParty = "third_party", unknown
}

enum HarborPlaybackStopReason: String {
    case dismissed, ended, failed, replaced, unknown
}

enum HarborNetworkOperation: String {
    case catalog, metadata, streams, unknown
}

enum HarborAnalyticsErrorCategory: String, CaseIterable {
    case networkError = "network_error"
    case timeout
    case offline
    case dnsError = "dns_error"
    case cancelled
    case http401 = "http_401"
    case http403 = "http_403"
    case http404 = "http_404"
    case http4xx = "http_4xx"
    case http5xx = "http_5xx"
    case invalidAuth = "invalid_auth"
    case invalidURL = "invalid_url"
    case decodingError = "decoding_error"
    case serverError = "server_error"
    case noAddons = "no_addons"
    case noStreams = "no_streams"
    case allAddonsFailed = "all_addons_failed"
    case vlcError = "vlc_error"
    case unknown

    static func classify(_ error: Error) -> HarborAnalyticsErrorCategory {
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return .timeout
            case .notConnectedToInternet, .networkConnectionLost: return .offline
            case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost: return .dnsError
            case .cancelled: return .cancelled
            case .badURL, .unsupportedURL: return .invalidURL
            default: return .networkError
            }
        }
        if let apiError = error as? StremioAPIError {
            switch apiError {
            case .http(let status):
                switch status {
                case 401: return .http401
                case 403: return .http403
                case 404: return .http404
                case 400..<500: return .http4xx
                case 500..<600: return .http5xx
                default: return .networkError
                }
            case .server:
                return apiError.invalidatesSession ? .invalidAuth : .serverError
            case .decoding:
                return .decodingError
            }
        }
        if error is AddonClientError { return .invalidURL }
        if error is DecodingError { return .decodingError }
        return .unknown
    }
}

enum HarborNonFatalError: String {
    case streamFetch = "stream_fetch_error"
    case playback = "playback_error"
}

struct HarborErrorContext {
    var screen: HarborScreen?
    var operation: HarborNetworkOperation?
    var mediaType: HarborMediaType?
    var playerState: String?

    init(
        screen: HarborScreen? = nil,
        operation: HarborNetworkOperation? = nil,
        mediaType: HarborMediaType? = nil,
        playerState: String? = nil
    ) {
        self.screen = screen
        self.operation = operation
        self.mediaType = mediaType
        self.playerState = playerState
    }
}

enum HarborPerformanceTraceName: String {
    case streamFetch = "stream_fetch"
    case playbackStart = "playback_start"
}

enum HarborTraceAttribute: String {
    case outcome
    case errorCategory = "error_category"
    case mediaType = "media_type"
}

enum HarborTraceMetric: String {
    case success
    case streamCount = "stream_count"
    case addonCount = "addon_count"
    case failureCount = "failure_count"
}
