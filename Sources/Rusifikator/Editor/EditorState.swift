enum EditorState: Equatable, Sendable {
    case empty
    case ready
    case loading
    case success
    case error
    case cancelled
}
