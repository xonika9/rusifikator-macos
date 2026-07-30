import Foundation
import XCTest
@testable import Rusifikator

final class SystemPromptTests: XCTestCase {
    func testBundledPromptMatchesFixedPrompt() throws {
        let expectedURL = try XCTUnwrap(
            Bundle.module.url(
                forResource: "ExpectedSystemPrompt",
                withExtension: "txt",
                subdirectory: "Fixtures"
            )
        )
        let expected = try String(contentsOf: expectedURL, encoding: .utf8)

        XCTAssertEqual(FixedSystemPrompt.text, expected)
    }
}
