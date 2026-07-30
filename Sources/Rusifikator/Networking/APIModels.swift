import Foundation

struct ChatCompletionRequest: Codable, Sendable {
    let model: String
    let messages: [Message]
    let stream: Bool

    struct Message: Codable, Sendable {
        let role: Role
        let content: String
    }

    enum Role: String, Codable, Sendable {
        case system
        case user
    }
}

struct ChatCompletionResponse: Codable, Sendable {
    let choices: [Choice]

    struct Choice: Codable, Sendable {
        let message: Message
    }

    struct Message: Codable, Sendable {
        let content: String
    }
}
