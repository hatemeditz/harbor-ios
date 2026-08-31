import Foundation

#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif
#if canImport(FirebasePerformance)
import FirebasePerformance
#endif

/// Harbor's single analytics boundary. Feature code only uses the typed Harbor
/// schema above; Firebase symbols, collection policy, and sanitization stay here.
final class AnalyticsService {
    static let shared = AnalyticsService()
    static let collectionPreferenceKey = "harbor.analytics.collection_enabled"

    private let stateLock = NSLock()
    private let nonFatalQueue = DispatchQueue(label: "site.harbor.analytics.nonfatal", qos: .utility)
    private var configured = false
    private var collectionActive = false
    private var recentNonFatals: [String: Date] = [:]
    private var activeOperations: [(token: UUID, operation: HarborNetworkOperation)] = []

    private init() {}

    var isCollectionEnabledByUser: Bool {
        if UserDefaults.standard.object(forKey: Self.collectionPreferenceKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: Self.collectionPreferenceKey)
    }

    /// Configures Firebase only when a real, bundled project configuration is
    /// available. Missing configuration is an intentional no-op for forks,
    /// tests, previews, and Harbor's public unsigned IPA build.
    func configure() {
        stateLock.lock()
        guard !configured else {
            stateLock.unlock()
            return
        }
        configured = true
        stateLock.unlock()

        #if canImport(FirebaseCore)
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path)
        else {
            debugLog("Firebase disabled (GoogleService-Info.plist is absent or invalid)")
            return
        }

        #if canImport(FirebasePerformance)
        // Harbor addon/debrid credentials can appear in URL path components.
        // Disable all automatic instrumentation before configuration and use
        // only fixed-name, category-only custom traces.
        Performance.sharedInstance().isInstrumentationEnabled = false
        #endif

        if FirebaseApp.app() == nil {
            FirebaseApp.configure(options: options)
        }

        applyCollectionState()
        #else
        debugLog("Firebase SDK is not linked; analytics is a no-op")
        #endif
    }

    func setCollectionEnabledByUser(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.collectionPreferenceKey)
        applyCollectionState()
    }

    func log(_ event: HarborAnalyticsEvent, parameters: HarborAnalyticsParameters = [:]) {
        let sanitized = sanitizedParameters(for: event, parameters: parameters)
        debugLog(event.rawValue)

        guard canCollect else { return }
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent(event.rawValue, parameters: sanitized)
        #endif
    }

    /// Screen navigation is Crashlytics context only; it does not create an
    /// Analytics event in Harbor's intentionally compact event contract.
    func setCurrentScreen(_ screen: HarborScreen, screenClass _: String) {
        guard canCollect else { return }
        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().setCustomValue(screen.rawValue, forKey: "current_screen")
        #endif
    }

    @discardableResult
    func beginOperation(_ operation: HarborNetworkOperation) -> UUID {
        let token = UUID()
        stateLock.lock()
        activeOperations.append((token, operation))
        stateLock.unlock()
        setCrashlyticsOperation(operation)
        return token
    }

    func endOperation(_ token: UUID) {
        stateLock.lock()
        activeOperations.removeAll { $0.token == token }
        let current = activeOperations.last?.operation
        stateLock.unlock()
        setCrashlyticsOperation(current)
    }

    private func setCrashlyticsOperation(_ operation: HarborNetworkOperation?) {
        guard canCollect else { return }
        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().setCustomValue(
            operation?.rawValue ?? "idle",
            forKey: "current_operation"
        )
        #endif
    }

    func setPlayerContext(state: String, mediaType: HarborMediaType) {
        guard let safeState = Self.safeToken(state, maximumLength: 32), canCollect else { return }
        #if canImport(FirebaseCrashlytics)
        let crashlytics = Crashlytics.crashlytics()
        crashlytics.setCustomValue(safeState, forKey: "player_state")
        crashlytics.setCustomValue(mediaType.rawValue, forKey: "media_type")
        #endif
    }

    func startTrace(
        _ name: HarborPerformanceTraceName,
        attributes: [HarborTraceAttribute: String] = [:]
    ) -> HarborPerformanceTrace {
        HarborPerformanceTrace(name: name, enabled: canCollect, attributes: attributes)
    }

    /// Records a synthetic, bounded non-fatal. The original Error/NSError is
    /// deliberately never handed to Crashlytics because it can contain URLs,
    /// response text, credentials, or other private metadata.
    func recordNonFatal(
        _ kind: HarborNonFatalError,
        category: HarborAnalyticsErrorCategory,
        context: HarborErrorContext = HarborErrorContext()
    ) {
        guard canCollect else { return }
        let fingerprint = [
            kind.rawValue,
            category.rawValue,
            context.screen?.rawValue ?? "none",
            context.operation?.rawValue ?? "none",
            context.mediaType?.rawValue ?? "none",
        ].joined(separator: "|")

        stateLock.lock()
        let now = Date()
        if let last = recentNonFatals[fingerprint], now.timeIntervalSince(last) < 30 {
            stateLock.unlock()
            return
        }
        recentNonFatals[fingerprint] = now
        recentNonFatals = recentNonFatals.filter { now.timeIntervalSince($0.value) < 300 }
        stateLock.unlock()

        nonFatalQueue.async {
            #if canImport(FirebaseCrashlytics)
            var info: [String: Any] = [
                NSLocalizedDescriptionKey: "\(kind.rawValue):\(category.rawValue)",
                "error_category": category.rawValue,
            ]
            if let screen = context.screen { info["screen"] = screen.rawValue }
            if let operation = context.operation { info["operation"] = operation.rawValue }
            if let mediaType = context.mediaType { info["media_type"] = mediaType.rawValue }
            if let playerState = context.playerState.flatMap({ Self.safeToken($0, maximumLength: 32) }) {
                info["player_state"] = playerState
            }
            let error = NSError(
                domain: "site.harbor.nonfatal.\(kind.rawValue)",
                code: Self.errorCode(for: category),
                userInfo: info
            )
            Crashlytics.crashlytics().record(error: error)
            #endif
        }
    }

    func mediaParameters(
        mediaType: String,
        mediaId: String,
        source: HarborNavigationSource,
        playbackSessionId: UUID? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil
    ) -> HarborAnalyticsParameters {
        var parameters: HarborAnalyticsParameters = [
            .mediaType: .string(HarborMediaType(mediaType).rawValue),
            .source: .string(source.rawValue),
        ]
        if let publicId = Self.publicMediaId(mediaId) {
            parameters[.mediaId] = .string(publicId)
        }
        if let playbackSessionId {
            parameters[.playbackSessionId] = .string(playbackSessionId.uuidString.lowercased())
        }
        if let seasonNumber { parameters[.seasonNumber] = .int(seasonNumber) }
        if let episodeNumber { parameters[.episodeNumber] = .int(episodeNumber) }
        return parameters
    }

    static func publicMediaId(_ value: String) -> String? {
        guard value.count <= 24, value.hasPrefix("tt") else { return nil }
        let suffix = value.dropFirst(2)
        guard !suffix.isEmpty,
              suffix.unicodeScalars.allSatisfy({ (48...57).contains(Int($0.value)) })
        else { return nil }
        return value
    }

    static func durationBucket(seconds: TimeInterval) -> String {
        switch seconds {
        case ..<1_800: return "under_30m"
        case ..<3_600: return "30_60m"
        case ..<5_400: return "60_90m"
        case ..<7_200: return "90_120m"
        default: return "120m_plus"
        }
    }

    static func milliseconds(since start: Date, now: Date = Date()) -> Int {
        max(0, Int(now.timeIntervalSince(start) * 1_000))
    }

    private var canCollect: Bool {
        stateLock.lock()
        let active = collectionActive
        stateLock.unlock()
        return active
    }

    private func applyCollectionState() {
        #if canImport(FirebaseCore)
        guard FirebaseApp.app() != nil else { return }
        #else
        return
        #endif

        let shouldCollect = isCollectionEnabledByUser && Self.buildAllowsCollection
        stateLock.lock()
        collectionActive = shouldCollect
        stateLock.unlock()

        #if canImport(FirebaseAnalytics)
        Analytics.setAnalyticsCollectionEnabled(shouldCollect)
        #endif
        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(shouldCollect)
        #endif
        #if canImport(FirebasePerformance)
        Performance.sharedInstance().isDataCollectionEnabled = shouldCollect
        #endif
        debugLog("Firebase collection \(shouldCollect ? "enabled" : "disabled")")
    }

    private func sanitizedParameters(
        for event: HarborAnalyticsEvent,
        parameters: HarborAnalyticsParameters
    ) -> [String: Any] {
        var result: [String: Any] = [
            HarborAnalyticsParameter.analyticsSchemaVersion.rawValue: HarborAnalyticsSchema.version,
            HarborAnalyticsParameter.buildEnvironment.rawValue: Self.buildEnvironment,
        ]
        for (key, value) in parameters where event.allowedParameters.contains(key) {
            guard let sanitized = Self.sanitize(value, for: key) else { continue }
            result[key.rawValue] = sanitized
        }
        return result
    }

    private static func sanitize(_ value: HarborAnalyticsValue, for key: HarborAnalyticsParameter) -> Any? {
        switch value {
        case .string(let string):
            switch key {
            case .mediaId:
                return publicMediaId(string)
            case .playbackSessionId:
                guard UUID(uuidString: string) != nil else { return nil }
                return string.lowercased()
            default:
                return safeToken(string, maximumLength: 100)
            }
        case .int(let integer):
            guard integer >= 0 else { return nil }
            return min(integer, 604_800_000)
        case .double(let number):
            guard number.isFinite, number >= 0 else { return nil }
            return min(number, 604_800)
        case .bool(let boolean):
            return boolean
        }
    }

    private static func safeToken(_ value: String, maximumLength: Int) -> String? {
        guard !value.isEmpty, value.count <= maximumLength else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        guard value.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return value
    }

    private static func errorCode(for category: HarborAnalyticsErrorCategory) -> Int {
        (HarborAnalyticsErrorCategory.allCases.firstIndex(of: category) ?? 0) + 1
    }

    private static var buildEnvironment: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }

    private static var buildAllowsCollection: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains { argument in
            argument == "-FIRDebugEnabled" || argument.hasPrefix("-FIRDebugEnabled=")
        }
        #else
        return true
        #endif
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[Analytics] \(message)")
        #endif
    }
}

/// A single-stop wrapper around Firebase custom traces. It accepts only fixed
/// trace, attribute, and metric enums, and never accepts a URL.
final class HarborPerformanceTrace {
    private let lock = NSLock()
    private var stopped = false

    #if canImport(FirebasePerformance)
    private var firebaseTrace: Trace?
    #endif

    init(
        name: HarborPerformanceTraceName,
        enabled: Bool,
        attributes: [HarborTraceAttribute: String]
    ) {
        #if canImport(FirebasePerformance)
        if enabled {
            firebaseTrace = Performance.startTrace(name: name.rawValue)
            for (key, value) in attributes {
                guard let safe = Self.safeAttribute(value) else { continue }
                firebaseTrace?.setValue(safe, forAttribute: key.rawValue)
            }
        }
        #endif
    }

    func stop(
        outcome: String,
        attributes: [HarborTraceAttribute: String] = [:],
        metrics: [HarborTraceMetric: Int64] = [:]
    ) {
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        stopped = true
        lock.unlock()

        #if canImport(FirebasePerformance)
        if let safeOutcome = Self.safeAttribute(outcome) {
            firebaseTrace?.setValue(safeOutcome, forAttribute: HarborTraceAttribute.outcome.rawValue)
        }
        for (key, value) in attributes {
            guard let safe = Self.safeAttribute(value) else { continue }
            firebaseTrace?.setValue(safe, forAttribute: key.rawValue)
        }
        for (key, value) in metrics {
            firebaseTrace?.incrementMetric(key.rawValue, by: max(0, value))
        }
        firebaseTrace?.stop()
        firebaseTrace = nil
        #endif
    }

    private static func safeAttribute(_ value: String) -> String? {
        guard !value.isEmpty, value.count <= 32 else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        guard value.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return value
    }
}
