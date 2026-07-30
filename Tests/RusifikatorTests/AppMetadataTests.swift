import XCTest
@testable import Rusifikator

final class AppMetadataTests: XCTestCase {
    func testMenuHeaderContainsNameVersionAndDistinctBuild() {
        XCTAssertEqual(
            AppMetadata.menuHeader(
                info: [
                    "CFBundleShortVersionString": "1.2",
                    "CFBundleVersion": "7"
                ]
            ),
            "Русификатор 1.2 (7)"
        )
    }

    func testMenuHeaderDoesNotRepeatMatchingBuild() {
        XCTAssertEqual(
            AppMetadata.menuHeader(
                info: [
                    "CFBundleShortVersionString": "1.0",
                    "CFBundleVersion": "1.0"
                ]
            ),
            "Русификатор 1.0"
        )
    }
}
