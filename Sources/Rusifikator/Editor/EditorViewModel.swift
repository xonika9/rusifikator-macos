import Foundation
import Observation

struct EditorRequest: Equatable, Sendable {
    let id: UUID
    let source: String
    let baseURL: URL
    let model: String
    let apiKey: String
    let systemPrompt: String
}

protocol EditorAPIClient: Sendable {
    func clean(_ request: EditorRequest) async throws -> String
}

struct OpenAIEditorAPIClient: EditorAPIClient {
    private let client: OpenAICompatibleClient

    init(client: OpenAICompatibleClient = OpenAICompatibleClient()) {
        self.client = client
    }

    func clean(_ request: EditorRequest) async throws -> String {
        try await client.clean(
            text: request.source,
            baseURL: request.baseURL,
            model: request.model,
            apiKey: request.apiKey,
            systemPrompt: request.systemPrompt
        )
    }
}

@Observable
@MainActor
final class EditorViewModel {
    var source = "" {
        didSet {
            sourceDidChange(from: oldValue)
        }
    }

    private(set) var state: EditorState = .empty
    private(set) var result: String?
    private(set) var errorMessage: String?
    private(set) var copiedConfirmationVisible = false

    @ObservationIgnored
    private let apiClient: any EditorAPIClient

    @ObservationIgnored
    private let clipboard: any ClipboardService

    @ObservationIgnored
    private var requestTask: Task<Void, Never>?

    @ObservationIgnored
    private var activeRequestID: UUID?

    @ObservationIgnored
    private var copyConfirmationID: UUID?

    init(
        apiClient: any EditorAPIClient = OpenAIEditorAPIClient(),
        clipboard: any ClipboardService = SystemClipboardService()
    ) {
        self.apiClient = apiClient
        self.clipboard = clipboard
    }

    var canSubmit: Bool {
        requestTask == nil && !trimmedSource.isEmpty
    }

    var canCancel: Bool {
        state == .loading
    }

    var canCopy: Bool {
        state == .success && result != nil
    }

    var canClear: Bool {
        state != .empty || !source.isEmpty
    }

    var isSourceEditable: Bool {
        state != .loading
    }

    func submit(
        baseURL: URL,
        model: String,
        apiKey: String,
        systemPrompt: String = FixedSystemPrompt.text
    ) {
        guard requestTask == nil, !trimmedSource.isEmpty else {
            return
        }

        let request = EditorRequest(
            id: UUID(),
            source: source,
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            systemPrompt: systemPrompt
        )

        activeRequestID = request.id
        result = nil
        errorMessage = nil
        hideCopyConfirmation()
        state = .loading

        requestTask = Task { [weak self, apiClient] in
            do {
                let result = try await apiClient.clean(request)
                guard !Task.isCancelled else {
                    return
                }
                self?.finish(request: request, with: .success(result))
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                self?.finish(request: request, with: .failure(error))
            }
        }
    }

    func cancel() {
        guard state == .loading else {
            return
        }

        invalidateActiveRequest()
        result = nil
        errorMessage = nil
        hideCopyConfirmation()
        state = .cancelled
    }

    func clear() {
        invalidateActiveRequest()
        result = nil
        errorMessage = nil
        hideCopyConfirmation()
        source = ""
        state = .empty
    }

    func copyResult() {
        guard let result, state == .success else {
            return
        }

        clipboard.copy(result)
        let confirmationID = UUID()
        copyConfirmationID = confirmationID
        copiedConfirmationVisible = true

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard self?.copyConfirmationID == confirmationID else {
                return
            }
            self?.copyConfirmationID = nil
            self?.copiedConfirmationVisible = false
        }
    }

    private var trimmedSource: String {
        source.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sourceDidChange(from oldValue: String) {
        guard source != oldValue, state != .loading else {
            return
        }

        result = nil
        errorMessage = nil
        hideCopyConfirmation()
        state = trimmedSource.isEmpty ? .empty : .ready
    }

    private func finish(
        request: EditorRequest,
        with outcome: Result<String, any Error>
    ) {
        guard activeRequestID == request.id else {
            return
        }

        activeRequestID = nil
        requestTask = nil

        switch outcome {
        case let .success(result):
            self.result = result
            errorMessage = nil
            state = .success

        case let .failure(error):
            result = nil
            if error is CancellationError || error as? APIError == .cancelled {
                errorMessage = nil
                state = .cancelled
            } else {
                errorMessage = Self.userMessage(for: error)
                state = .error
            }
        }
    }

    private func invalidateActiveRequest() {
        activeRequestID = nil
        requestTask?.cancel()
        requestTask = nil
    }

    private func hideCopyConfirmation() {
        copyConfirmationID = nil
        copiedConfirmationVisible = false
    }

    private static func userMessage(for error: any Error) -> String {
        if let error = error as? any LocalizedError,
           let description = error.errorDescription {
            return description
        }
        return "Не удалось обработать текст. Попробуй ещё раз."
    }
}
