import Foundation
import Darwin

/// Incremental SSE framing works in bytes, so UTF-8 scalars may cross callbacks.
struct StreamingResponseDecoder {
    static let maximumEventBytes = 1_024 * 1_024
    static let maximumTextBytes = 4 * 1_024 * 1_024
    private let jsonDecoder = JSONDecoder()
    private var line = Data()
    private var event = Data()
    private var hasData = false
    private var eventBytes = 0
    private var textBytes = 0
    private var sawCR = false
    private var firstLine = true
    private var stopped = false
    private var done = false
    private(set) var text = ""

    mutating func append(_ bytes: Data) throws -> String? {
        let oldBytes = textBytes
        try bytes.withUnsafeBytes { raw in
            let buffer = raw.bindMemory(to: UInt8.self)
            guard let base = raw.baseAddress, !buffer.isEmpty else { return }
            var start = 0
            if sawCR {
                sawCR = false
                if buffer[0] == 10 { start = 1 }
            }
            func position(of byte: Int32, from start: Int) -> Int? {
                guard start < buffer.count else { return nil }
                return memchr(base.advanced(by: start), byte, buffer.count - start)
                    .map { base.distance(to: UnsafeRawPointer($0)) }
            }
            // Cache both next separators: an absent CR must not cause a new
            // full suffix scan for every LF in a large comment-only body.
            var lf = position(of: 10, from: start)
            var cr = position(of: 13, from: start)
            while start < buffer.count {
                let end = min(lf ?? buffer.count, cr ?? buffer.count)
                try appendLine(buffer, from: start, to: end)
                guard end < buffer.count else { break }
                try endLine()
                sawCR = buffer[end] == 13
                start = end + 1
                if sawCR && start < buffer.count {
                    sawCR = false
                    if buffer[start] == 10 { start += 1 }
                }
                if let next = lf, next < start { lf = position(of: 10, from: start) }
                if let next = cr, next < start { cr = position(of: 13, from: start) }
            }
        }
        return oldBytes == textBytes ? nil : text
    }

    private mutating func appendLine(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int) throws {
        let count = end - start
        guard count <= Self.maximumEventBytes - eventBytes - line.count else {
            throw APIError.responseTooLarge
        }
        if count > 0 { line.append(bytes.baseAddress!.advanced(by: start), count: count) }
    }

    mutating func finish() throws -> String {
        if !line.isEmpty { try endLine() }
        guard !hasData, stopped, done else { throw APIError.invalidStreamingResponse }
        guard !text.isEmpty else { throw APIError.emptyResponse }
        return text
    }

    private mutating func endLine() throws {
        var bytes = line
        line.removeAll(keepingCapacity: true)
        if firstLine {
            firstLine = false
            if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        }
        if bytes.isEmpty {
            try dispatchEvent()
            eventBytes = 0
            return
        }
        guard bytes.count + 1 <= Self.maximumEventBytes - eventBytes else { throw APIError.responseTooLarge }
        eventBytes += bytes.count + 1
        let colon = bytes.firstIndex(of: 58) ?? bytes.endIndex
        guard bytes[..<colon].elementsEqual([100, 97, 116, 97]) else {
            guard String(data: bytes, encoding: .utf8) != nil else { throw APIError.invalidStreamingResponse }
            return
        }
        var value = colon == bytes.endIndex ? Data() : Data(bytes[bytes.index(after: colon)...])
        if value.first == 32 { value.removeFirst() }
        if hasData {
            event.append(10)
            event.append(value)
        } else {
            event = value
        }
        hasData = true
    }

    private mutating func dispatchEvent() throws {
        guard hasData else { return }
        hasData = false
        let data = event
        event.removeAll(keepingCapacity: true)
        guard !data.isEmpty else { return }
        guard !done else { throw APIError.invalidStreamingResponse }
        if data.elementsEqual([91, 68, 79, 78, 69, 93]) {
            guard stopped else { throw APIError.invalidStreamingResponse }
            done = true
            return
        }
        let chunk: Chunk
        do { chunk = try jsonDecoder.decode(Chunk.self, from: data) }
        catch { throw APIError.invalidStreamingResponse }
        if chunk.choices.isEmpty { return }
        guard chunk.choices.count == 1, let choice = chunk.choices.first,
              choice.index == 0, choice.delta.toolCalls == nil,
              choice.delta.functionCall == nil else { throw APIError.invalidStreamingResponse }
        if let content = choice.delta.content, !content.isEmpty {
            guard !stopped else { throw APIError.invalidStreamingResponse }
            let count = content.utf8.count
            guard count <= Self.maximumTextBytes - textBytes else { throw APIError.responseTooLarge }
            text.append(content)
            textBytes += count
        }
        if let reason = choice.finishReason {
            guard reason == "stop", !stopped else { throw APIError.invalidStreamingResponse }
            stopped = true
        }
    }

    private struct Chunk: Decodable { let choices: [Choice] }
    private struct Choice: Decodable {
        let index: Int
        let delta: Delta
        let finishReason: String?
        enum CodingKeys: String, CodingKey { case index, delta; case finishReason = "finish_reason" }
    }
    private struct Delta: Decodable {
        let content: String?
        let toolCalls: [IgnoredValue]?
        let functionCall: IgnoredValue?
        enum CodingKeys: String, CodingKey { case content; case toolCalls = "tool_calls"; case functionCall = "function_call" }
    }
    private struct IgnoredValue: Decodable {}
}
