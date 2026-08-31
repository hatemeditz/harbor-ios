import Foundation
import XCTest
@testable import Harbor

final class AnalyticsSchemaTests: XCTestCase {
    private let reservedPrefixes = ["firebase_", "google_", "ga_"]
    private let defaultParameters: Set<HarborAnalyticsParameter> = [
        .analyticsSchemaVersion,
        .buildEnvironment,
    ]

    func testEventNamesAreUniqueFixedAndFirebaseCompatible() {
        let actual = HarborAnalyticsEvent.allCases.map(\.rawValue)
        let expected: Set<String> = [
            "search_submitted",
            "search_results_returned",
            "search_result_clicked",
            "search_no_results",
            "search_failed",
            "movie_opened",
            "series_opened",
            "play_clicked",
            "stream_fetch_started",
            "stream_fetch_success",
            "stream_fetch_failed",
            "stream_selected",
            "playback_start_requested",
            "playback_started",
            "playback_failed",
            "playback_90",
            "playback_completed",
            "playback_stopped",
        ]

        XCTAssertEqual(actual.count, Set(actual).count, "Analytics event names must be unique")
        XCTAssertEqual(Set(actual), expected, "Update the fixed event contract intentionally")

        for name in actual {
            XCTAssertTrue(isSnakeCaseName(name, maximumLength: 40), "Invalid event name: \(name)")
            XCTAssertFalse(hasReservedPrefix(name), "Reserved Firebase event prefix: \(name)")
        }
    }

    func testParameterNamesAndPerEventCountsAreFirebaseCompatible() {
        for parameter in HarborAnalyticsParameter.allCases {
            XCTAssertTrue(
                isSnakeCaseName(parameter.rawValue, maximumLength: 40),
                "Invalid parameter name: \(parameter.rawValue)"
            )
            XCTAssertFalse(
                hasReservedPrefix(parameter.rawValue),
                "Reserved Firebase parameter prefix: \(parameter.rawValue)"
            )
        }

        for event in HarborAnalyticsEvent.allCases {
            XCTAssertTrue(
                event.allowedParameters.isDisjoint(with: defaultParameters),
                "Event-specific parameters must not redefine defaults for \(event.rawValue)"
            )
            XCTAssertLessThanOrEqual(
                event.allowedParameters.union(defaultParameters).count,
                25,
                "\(event.rawValue) exceeds Firebase's 25-parameter limit including defaults"
            )
        }
    }

    func testSchemaVersionIsPositive() {
        XCTAssertGreaterThan(HarborAnalyticsSchema.version, 0)
    }

    func testSchemaCannotRepresentKnownSensitiveFields() {
        let prohibited: Set<String> = [
            "query", "raw_query", "email", "username", "password", "token",
            "auth_key", "api_key", "authorization", "url", "stream_url",
            "addon_url", "magnet", "torrent_hash", "error_description",
        ]

        XCTAssertTrue(
            Set(HarborAnalyticsParameter.allCases.map(\.rawValue)).isDisjoint(with: prohibited)
        )
    }

    private func hasReservedPrefix(_ value: String) -> Bool {
        reservedPrefixes.contains { value.hasPrefix($0) }
    }

    private func isSnakeCaseName(_ value: String, maximumLength: Int) -> Bool {
        guard !value.isEmpty, value.count <= maximumLength else { return false }
        let bytes = value.utf8
        guard let first = bytes.first, (97...122).contains(first) else { return false }
        return bytes.allSatisfy { byte in
            (97...122).contains(byte) || (48...57).contains(byte) || byte == 95
        }
    }
}

final class AnalyticsPrivacyTests: XCTestCase {
    func testAllowsOnlyPublicIMDbTitleIdentifiers() {
        let maximumLengthId = "tt" + String(repeating: "9", count: 22)

        XCTAssertEqual(AnalyticsService.publicMediaId("tt0111161"), "tt0111161")
        XCTAssertEqual(AnalyticsService.publicMediaId("tt12345678"), "tt12345678")
        XCTAssertEqual(AnalyticsService.publicMediaId(maximumLengthId), maximumLengthId)
    }

    func testRejectsArbitraryIdentifiersURLsEmailsAndPrivateValues() {
        let rejected = [
            "",
            "tt",
            "TT0111161",
            "tmdb:550",
            "1234567",
            "tt123:1:2",
            "tt1234567?token=secret",
            "tt" + String(repeating: "9", count: 23),
            "https://www.imdb.com/title/tt0111161/",
            "https://stream.example/video?token=secret",
            "magnet:?xt=urn:btih:secret",
            "viewer@example.com",
            "tt١٢٣٤٥٦٧",
        ]

        for value in rejected {
            XCTAssertNil(AnalyticsService.publicMediaId(value), "Unexpectedly allowed: \(value)")
        }
    }
}

final class AnalyticsErrorClassificationTests: XCTestCase {
    func testClassifiesURLSessionErrorsWithoutUsingDescriptions() {
        let cases: [(URLError.Code, HarborAnalyticsErrorCategory)] = [
            (.timedOut, .timeout),
            (.notConnectedToInternet, .offline),
            (.networkConnectionLost, .offline),
            (.cannotFindHost, .dnsError),
            (.dnsLookupFailed, .dnsError),
            (.cannotConnectToHost, .dnsError),
            (.cancelled, .cancelled),
            (.badURL, .invalidURL),
            (.unsupportedURL, .invalidURL),
            (.secureConnectionFailed, .networkError),
        ]

        for (code, expected) in cases {
            XCTAssertEqual(
                HarborAnalyticsErrorCategory.classify(URLError(code)),
                expected,
                "Unexpected category for URLError.Code \(code.rawValue)"
            )
        }

        XCTAssertEqual(
            HarborAnalyticsErrorCategory.classify(CancellationError()),
            .cancelled
        )
    }

    func testClassifiesStremioHTTPStatusFamilies() {
        let cases: [(Int, HarborAnalyticsErrorCategory)] = [
            (401, .http401),
            (403, .http403),
            (404, .http404),
            (400, .http4xx),
            (418, .http4xx),
            (499, .http4xx),
            (500, .http5xx),
            (503, .http5xx),
            (599, .http5xx),
            (302, .networkError),
            (600, .networkError),
        ]

        for (statusCode, expected) in cases {
            XCTAssertEqual(
                HarborAnalyticsErrorCategory.classify(StremioAPIError.http(statusCode)),
                expected,
                "Unexpected category for HTTP \(statusCode)"
            )
        }
    }

    func testClassifiesStremioServerAndDecodingErrors() {
        XCTAssertEqual(
            HarborAnalyticsErrorCategory.classify(
                StremioAPIError.server("Session does not exist")
            ),
            .invalidAuth
        )
        XCTAssertEqual(
            HarborAnalyticsErrorCategory.classify(
                StremioAPIError.server("Invalid auth key")
            ),
            .invalidAuth
        )
        XCTAssertEqual(
            HarborAnalyticsErrorCategory.classify(
                StremioAPIError.server("Upstream service unavailable")
            ),
            .serverError
        )
        XCTAssertEqual(
            HarborAnalyticsErrorCategory.classify(StremioAPIError.decoding),
            .decodingError
        )
    }
}

final class AnalyticsHelperTests: XCTestCase {
    func testDurationBucketsAtEveryBoundary() {
        let cases: [(TimeInterval, String)] = [
            (0, "under_30m"),
            (1_799.999, "under_30m"),
            (1_800, "30_60m"),
            (3_599.999, "30_60m"),
            (3_600, "60_90m"),
            (5_399.999, "60_90m"),
            (5_400, "90_120m"),
            (7_199.999, "90_120m"),
            (7_200, "120m_plus"),
        ]

        for (seconds, expected) in cases {
            XCTAssertEqual(AnalyticsService.durationBucket(seconds: seconds), expected)
        }
    }

    func testMillisecondsAreDeterministicAndNeverNegative() {
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(
            AnalyticsService.milliseconds(
                since: start,
                now: Date(timeIntervalSince1970: 1_001.25)
            ),
            1_250
        )
        XCTAssertEqual(
            AnalyticsService.milliseconds(
                since: start,
                now: Date(timeIntervalSince1970: 999)
            ),
            0
        )
    }
}
