import Foundation
import XCTest
@testable import Harbor

final class TMDBCatalogTests: XCTestCase {
    func testRequestedDiscoverCollectionsMatchProductContract() {
        let collections = TMDBCollectionDefinition.requestedCollections(
            now: Date(timeIntervalSince1970: 1_788_134_400)
        )
        XCTAssertEqual(
            collections.map(\.title),
            [
                "Trending This Week",
                "Top Rated",
                "Award Winning",
                "Top Rated History",
                "New Documentary Series",
                "Top Rated Action",
                "New in Drama",
                "Adventure + Sci-Fi",
                "Best of the 80s",
                "Documentary + Animation",
                "Cult Classics",
            ]
        )
        XCTAssertEqual(collections.count, Set(collections.map(\.id)).count)
    }

    func testStreamingProviderCatalogIncludesNetflixUSProviderID() throws {
        let netflix = try XCTUnwrap(TMDBStreamingProvider.all.first { $0.id == "netflix" })
        XCTAssertEqual(netflix.name, "Netflix")
        XCTAssertEqual(netflix.providerIDs, [8])
    }

    func testGenreCatalogContainsRequestedCombinationGenres() {
        let genres = Dictionary(uniqueKeysWithValues: TMDBGenreDefinition.all.map { ($0.name, $0.movieGenreID) })
        XCTAssertEqual(genres["Adventure"], 12)
        XCTAssertEqual(genres["Animation"], 16)
        XCTAssertEqual(genres["Documentary"], 99)
        XCTAssertEqual(genres["Drama"], 18)
        XCTAssertEqual(genres["History"], 36)
        XCTAssertEqual(genres["Sci-Fi"], 878)
    }
}
