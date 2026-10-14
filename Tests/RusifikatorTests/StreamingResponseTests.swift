import Foundation
import XCTest
@testable import Rusifikator

final class StreamingResponseTests: XCTestCase {
    private let fragment = #"data: {"choices":[{"index":0,"delta":{"content":"Привет 👋\n"}}]}"# + "\n\n"
    private let end = #"data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"# + "\n\ndata: [DONE]\n\n"

    func testEveryByteSplitPreservesUTF8CRLFBOMAndFinal() throws {
        for newline in ["\n", "\r", "\r\n"] {
            let data = Data(("\u{FEFF}: comment\n\n" + fragment + end).replacingOccurrences(of: "\n", with: newline).utf8)
            for split in 0...data.count {
                var decoder = StreamingResponseDecoder()
                _ = try decoder.append(data.prefix(split))
                _ = try decoder.append(data.dropFirst(split))
                XCTAssertEqual(try decoder.finish(), "Привет 👋\n")
            }
        }
    }

    func testEOFWithoutStopOrDoneIsNotSuccess() throws {
        for body in [fragment, fragment + #"data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"# + "\n\n"] {
            var decoder = StreamingResponseDecoder()
            XCTAssertEqual(try decoder.append(Data(body.utf8)), "Привет 👋\n")
            XCTAssertThrowsError(try decoder.finish())
        }
    }
    func testMultipleDataLinesCommentsAndEmptyDeltas() throws {
        let body = ": ping\n\ndata: {\n" + #"data: "choices":[{"index":0,"delta":{}}]}"# + "\n\n" + fragment + end
        var decoder = StreamingResponseDecoder()
        XCTAssertEqual(try decoder.append(Data(body.utf8)), "Привет 👋\n")
        XCTAssertEqual(try decoder.finish(), "Привет 👋\n")
    }

    func testMalformedAndUnconfirmedEventsAreRejected() throws {
        let invalid = [
            #"{"choices":[{"index":0,"delta":{},"finish_reason":"length"}]}"#,
            #"{"choices":[{"index":0,"delta":{},"finish_reason":"content_filter"}]}"#,
            #"{"choices":[{"index":0,"delta":{"tool_calls":[]}}]}"#,
            #"{"choices":[{"index":0,"delta":{"function_call":{}}}]}"#,
            #"{"choices":[{"index":1,"delta":{"content":"wrong"}}]}"#,
            #"{"choices":[{"index":0,"delta":{}},{"index":1,"delta":{}}]}"#,
            "broken", "[DONE]"
        ]
        for event in invalid {
            var decoder = StreamingResponseDecoder()
            _ = try decoder.append(Data(fragment.utf8))
            XCTAssertThrowsError(try decoder.append(Data(("data: " + event + "\n\n").utf8)))
        }
        var decoder = StreamingResponseDecoder()
        _ = try decoder.append(Data((fragment + end).utf8))
        XCTAssertThrowsError(try decoder.append(Data(fragment.utf8)))
        var utf8 = StreamingResponseDecoder()
        XCTAssertThrowsError(try utf8.append(Data([0xFF,10])))
        let prefix = Data(#"data: {"choices":[{"index":0,"delta":{"content":""#.utf8)
        let suffix = Data((#""}}]}"# + "\n\n").utf8)
        var payloadUTF8 = StreamingResponseDecoder()
        XCTAssertThrowsError(try payloadUTF8.append(prefix + Data([0xFF]) + suffix))
    }

    func testEventLimitIncludesCommentsAndResultLimitAccumulates() throws {
        var exact = StreamingResponseDecoder()
        _ = try exact.append(Data((":" + String(repeating: "x", count: 1_024 * 1_024 - 2) + "\n\n").utf8))
        var oversized = StreamingResponseDecoder()
        XCTAssertThrowsError(try oversized.append(Data((":" + String(repeating: "x", count: 1_024 * 1_024 - 1) + "\n\n").utf8)))
        let content = String(repeating: "x", count: 500_000)
        let chunk = Data((#"data: {"choices":[{"index":0,"delta":{"content":""# + content + #""}}]}"# + "\n\n").utf8)
        var text = StreamingResponseDecoder()
        for _ in 0..<8 { _ = try text.append(chunk) }
        XCTAssertThrowsError(try text.append(chunk))
    }

    @MainActor
    func testBurstPublishesOnlyLatestAndCancelledPublicationCannotResume() async throws {
        var publications: [String] = []
        let publication = PreviewPublication { publications.append($0) }
        for i in 0..<10_000 { publication.receive("fragment \(i)") }
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while publications.isEmpty && ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertEqual(publications, ["fragment 9999"])
        publication.receive("late fragment")
        publication.cancel()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(publications, ["fragment 9999"])
    }

    func testDoneMustBeACompleteSSEEventAndEmptyDataLinesAreNotDropped() throws {
        let stop = #"data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"# + "\n\n"
        for body in [fragment + stop + "data: [DONE]", fragment + stop + "data: [DONE]\n", fragment + stop + "data:\ndata: [DONE]\n\n"] {
            var decoder = StreamingResponseDecoder()
            do {
                _ = try decoder.append(Data(body.utf8))
                _ = try decoder.finish()
                XCTFail("Incomplete or multiline DONE must not confirm a stream")
            } catch { XCTAssertEqual(error as? APIError, .invalidStreamingResponse) }
        }
    }

    func testFieldTypesRejectBooleanIndexAndPreserveNullServiceFields() throws {
        let invalid = [
            #"{"choices":[{"index":false,"delta":{"content":"wrong"}}]}"#,
            #"{"choices":[{"index":"0","delta":{"content":"wrong"}}]}"#,
            #"{"choices":[{"index":0.5,"delta":{"content":"wrong"}}]}"#,
            #"{"choices":[{"index":null,"delta":{"content":"wrong"}}]}"#,
            #"{"choices":{}}"#, #"{"choices":null}"#,
            #"{"choices":[null]}"#, #"{"choices":[[]]}"#,
            #"{"choices":[{"index":0,"delta":null}]}"#,
            #"{"choices":[{"index":0,"delta":[]}]}"#,
            #"{"choices":[{"index":0,"delta":{"content":7}}]}"#,
            #"{"choices":[{"index":0,"delta":{},"finish_reason":7}]}"#
        ]
        for value in invalid {
            var decoder = StreamingResponseDecoder()
            XCTAssertThrowsError(try decoder.append(Data(("data: " + value + "\n\n").utf8)))
        }
        var decoder = StreamingResponseDecoder()
        let service = #"data: {"choices":[{"index":0,"delta":{"content":null,"tool_calls":null,"function_call":null},"finish_reason":null}]}"# + "\n\n"
        XCTAssertNil(try decoder.append(Data(service.utf8)))
        _ = try decoder.append(Data((fragment + end).utf8))
        XCTAssertEqual(try decoder.finish(), "Привет 👋\n")
    }

}
