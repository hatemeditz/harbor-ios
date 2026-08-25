import Foundation
import XCTest
@testable import Harbor

final class TitleParserTests: XCTestCase {
    func testParsesQualityAudioSourceSizeAndSeeders() {
        let parsed = TitleParser.parse(
            title: "Movie.2026.2160p.WEB-DL.DV.TrueHD.Atmos.12.5 GB.Seeders: 120-GROUP",
            description: nil
        )

        XCTAssertEqual(parsed.resolution, .uhd2160)
        XCTAssertEqual(parsed.hdr, .dolbyVision)
        XCTAssertEqual(parsed.source, .webDl)
        XCTAssertTrue(parsed.hasAtmos)
        XCTAssertTrue(parsed.isLosslessAudio)
        XCTAssertEqual(parsed.sizeGB ?? 0, 12.5, accuracy: 0.001)
        XCTAssertEqual(parsed.seeders, 120)
        XCTAssertEqual(parsed.releaseGroup, "GROUP")
    }

    func testRejectsSamplesAsJunk() {
        let parsed = TitleParser.parse(title: "Movie.1080p.sample.mkv", description: nil)
        XCTAssertTrue(parsed.isJunk)
    }

    func testParsesMegabytesAsGigabytes() {
        let parsed = TitleParser.parse(title: "Episode.720p.1536 MB", description: nil)
        XCTAssertEqual(parsed.sizeGB ?? 0, 1.5, accuracy: 0.001)
    }
}

final class StreamScorerTests: XCTestCase {
    func testDirectHTTPSStreamIsPlayableAndOutranksBareHash() throws {
        let direct = try XCTUnwrap(StreamScorer.score(
            raw: raw(title: "Movie.1080p.WEB-DL", url: "https://cdn.example.com/movie.mkv"),
            id: 1
        ))
        let hash = try XCTUnwrap(StreamScorer.score(
            raw: raw(title: "Movie.1080p.WEB-DL", infoHash: "abcdef"),
            id: 2
        ))

        XCTAssertTrue(direct.playable)
        XCTAssertFalse(hash.playable)
        XCTAssertGreaterThan(direct.score, hash.score)
    }

    func testEmptyDirectURLWithoutHashIsRejected() {
        XCTAssertNil(StreamScorer.score(
            raw: raw(title: "Movie.1080p", url: ""),
            id: 1
        ))
    }

    func testSortsHighestScoreFirst() throws {
        let hd = try XCTUnwrap(StreamScorer.score(
            raw: raw(title: "Movie.720p", url: "https://example.com/720"),
            id: 1
        ))
        let uhd = try XCTUnwrap(StreamScorer.score(
            raw: raw(title: "Movie.2160p", url: "https://example.com/2160"),
            id: 2
        ))

        XCTAssertEqual(StreamScorer.sort([hd, uhd]).first?.id, uhd.id)
    }

    private func raw(
        title: String,
        url: String? = nil,
        infoHash: String? = nil
    ) -> RawStream {
        RawStream(
            title: title,
            description: nil,
            url: url,
            infoHash: infoHash,
            fileIdx: nil,
            behaviorHints: nil,
            sources: nil,
            addonName: "Tests"
        )
    }
}

final class AddonClientTests: XCTestCase {
    func testNormalizesManifestURLWithTrailingSlash() {
        XCTAssertEqual(
            AddonClient.baseURL(for: "https://example.com/config/manifest.json/"),
            "https://example.com/config"
        )
    }

    func testBuildsEncodedCatalogURLWithStableExtras() throws {
        let url = try AddonClient.catalogURL(
            base: "https://example.com/manifest.json",
            type: "movie",
            id: "top",
            extras: ["skip": "50", "search": "The Matrix"]
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://example.com/catalog/movie/top/search=The%20Matrix&skip=50.json"
        )
    }

    func testRejectsNonHTTPManifestURL() {
        XCTAssertThrowsError(try AddonClient.manifestURL(for: "file:///tmp/addon"))
    }

    func testStreamResponseSkipsMalformedEntries() throws {
        let data = Data(#"{"streams":[{"title":"Good","url":"https://example.com/video"},42,{"url":7}]}"#.utf8)
        let response = try JSONDecoder().decode(StreamResponse.self, from: data)

        XCTAssertEqual(response.streams.count, 1)
        XCTAssertEqual(response.streams.first?.title, "Good")
    }
}

final class ModelBehaviorTests: XCTestCase {
    func testMetaVideoParsesFractionalISODate() throws {
        let data = Data(#"{"id":"tt1:1:1","released":"2026-08-25T12:34:56.789Z"}"#.utf8)
        let video = try JSONDecoder().decode(MetaVideo.self, from: data)
        XCTAssertNotNil(video.released)
    }

    func testContinueWatchingProgressAndEpisodeParsing() {
        var state = LibraryState()
        state.timeOffset = 45_000
        state.duration = 90_000
        state.videoId = "tt123:2:7"
        let item = libraryItem(state: state)

        XCTAssertTrue(item.isContinueWatching)
        XCTAssertEqual(item.progressRatio, 0.5, accuracy: 0.001)
        XCTAssertEqual(item.episodeFromVideoId?.season, 2)
        XCTAssertEqual(item.episodeFromVideoId?.episode, 7)
    }

    func testInProgressBookmarkRemainsBookmarked() {
        var state = LibraryState()
        state.timeOffset = 45_000
        state.duration = 90_000
        let item = libraryItem(state: state)

        XCTAssertTrue(item.isBookmarked)
        XCTAssertFalse(item.isInWatchlist)
        XCTAssertTrue(item.isContinueWatching)
    }

    func testTemporaryProgressItemIsNotBookmarked() {
        var state = LibraryState()
        state.timeOffset = 45_000
        state.duration = 90_000
        let item = libraryItem(temp: true, state: state)

        XCTAssertFalse(item.isBookmarked)
        XCTAssertTrue(item.isContinueWatching)
    }

    func testFractionalTimestampParticipatesInSorting() {
        let item = libraryItem(
            mtime: "2026-08-25T12:34:56.789Z",
            state: LibraryState()
        )
        XCTAssertGreaterThan(item.sortTimestamp, 0)
    }

    private func libraryItem(
        mtime: String = "2026-08-25T12:34:56Z",
        temp: Bool = false,
        state: LibraryState?
    ) -> Harbor.LibraryItem {
        Harbor.LibraryItem(
            id: "tt123",
            type: "series",
            name: "Example",
            poster: nil,
            background: nil,
            posterShape: "poster",
            removed: false,
            temp: temp,
            ctime: mtime,
            mtime: mtime,
            state: state,
            behaviorHints: LibraryBehaviorHints()
        )
    }
}
