import SwiftUI
import UIKit
import XCTest
@testable import Harbor

final class AdaptiveLayoutTests: XCTestCase {
    func testIPhoneKeepsPhoneLayoutAcrossHorizontalSizeClassChanges() {
        let portrait = HarborAdaptiveLayout.resolve(
            userInterfaceIdiom: .phone,
            horizontalSizeClass: .compact
        )
        let landscape = HarborAdaptiveLayout.resolve(
            userInterfaceIdiom: .phone,
            horizontalSizeClass: .regular
        )

        XCTAssertEqual(portrait, .phone)
        XCTAssertEqual(landscape, .phone)
    }

    func testIPadUsesExpandedLayout() {
        XCTAssertEqual(
            HarborAdaptiveLayout.resolve(
                userInterfaceIdiom: .pad,
                horizontalSizeClass: .regular
            ),
            .pad
        )
    }
}
