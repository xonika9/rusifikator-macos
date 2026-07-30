import XCTest
@testable import Rusifikator

final class CharacterCountFormatterTests: XCTestCase {
    func testUsesCorrectRussianPluralForms() {
        let examples: [(Int, String)] = [
            (0, "0 знаков"),
            (1, "1 знак"),
            (2, "2 знака"),
            (4, "4 знака"),
            (5, "5 знаков"),
            (11, "11 знаков"),
            (14, "14 знаков"),
            (21, "21 знак"),
            (22, "22 знака")
        ]

        for (count, expected) in examples {
            XCTAssertEqual(
                CharacterCountFormatter.string(for: count),
                expected
            )
        }
    }
}
