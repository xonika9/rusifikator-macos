import Foundation
import Observation
import SwiftUI

protocol ConnectionChecking: Sendable {
    func checkConnection(
        baseURL: URL,
        model: String,
        apiKey: String
    ) async throws
}

extension OpenAICompatibleClient: ConnectionChecking {
    func checkConnection(
        baseURL: URL,
        model: String,
        apiKey: String
    ) async throws {
        try await checkConnection(
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            systemPrompt: FixedSystemPrompt.text
        )
    }
}

@Observable
@MainActor
final class SettingsViewModel {
    enum FeedbackState: Equatable {
        case idle
        case checking
        case success
        case failure(String)
    }

    var draftProviderURL: String {
        didSet {
            clearCarriedKeyForChangedOrigin()
            connectionState = .idle
            saveState = .idle
        }
    }
    var draftModel: String
    var draftAPIKey: String
    var showsAPIKey = false

    private(set) var connectionState: FeedbackState = .idle
    private(set) var saveState: FeedbackState = .idle
    private(set) var loadMessage: String?
    private(set) var loginItemStatus: LoginItemController.Status
    private(set) var loginItemMessage: String?

    private(set) var currentProviderURLString: String
    private(set) var currentModel: String
    private(set) var currentAPIKey: String

    @ObservationIgnored
    private let store: SettingsStore

    @ObservationIgnored
    private let credentials: any CredentialStore

    @ObservationIgnored
    private let connectionChecker: any ConnectionChecking

    @ObservationIgnored
    private let loginItem: LoginItemController

    @ObservationIgnored
    private var connectionTask: Task<Void, Never>?

    init(
        store: SettingsStore = SettingsStore(),
        credentials: any CredentialStore = KeychainCredentialStore(),
        connectionChecker: any ConnectionChecking = OpenAICompatibleClient(),
        loginItem: LoginItemController = LoginItemController()
    ) {
        self.store = store
        self.credentials = credentials
        self.connectionChecker = connectionChecker
        self.loginItem = loginItem

        let providerURL = store.providerURLString
        let model = store.model
        currentProviderURLString = providerURL
        currentModel = model
        draftProviderURL = providerURL
        draftModel = model
        loginItemStatus = loginItem.status

        if let url = URL(string: providerURL) {
            do {
                let apiKey = try credentials.apiKey(for: url) ?? ""
                currentAPIKey = apiKey
                draftAPIKey = apiKey
            } catch {
                currentAPIKey = ""
                draftAPIKey = ""
                loadMessage = Self.userMessage(for: error)
            }
        } else {
            currentAPIKey = ""
            draftAPIKey = ""
            loadMessage = APIError.invalidURL.localizedDescription
        }
    }

    var canCheckConnection: Bool {
        connectionState != .checking
    }

    var loginItemIsEnabled: Bool {
        loginItemStatus == .enabled
    }

    var loginItemRequiresApproval: Bool {
        loginItemStatus == .requiresApproval
    }

    func submit(_ editor: EditorViewModel) {
        guard let baseURL = URL(string: currentProviderURLString) else {
            return
        }
        editor.submit(
            baseURL: baseURL,
            model: currentModel,
            apiKey: currentAPIKey
        )
    }

    func save() {
        do {
            let values = try validatedDraft()
            let key = draftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty {
                try credentials.deleteAPIKey()
            } else {
                try credentials.saveAPIKey(key, for: values.url)
            }

            store.providerURLString = values.urlString
            store.model = values.model
            currentProviderURLString = values.urlString
            currentModel = values.model
            currentAPIKey = key
            draftProviderURL = values.urlString
            draftModel = values.model
            draftAPIKey = key
            loadMessage = nil
            saveState = .success
        } catch {
            saveState = .failure(Self.userMessage(for: error))
        }
    }

    func checkConnection() {
        guard connectionTask == nil else {
            return
        }

        let values: (url: URL, urlString: String, model: String)
        do {
            values = try validatedDraft()
        } catch {
            connectionState = .failure(Self.userMessage(for: error))
            return
        }

        let key = draftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        connectionState = .checking
        connectionTask = Task { [weak self, connectionChecker] in
            do {
                try await connectionChecker.checkConnection(
                    baseURL: values.url,
                    model: values.model,
                    apiKey: key
                )
                guard !Task.isCancelled else { return }
                self?.finishConnectionCheck(with: .success)
            } catch {
                guard !Task.isCancelled else { return }
                self?.finishConnectionCheck(
                    with: .failure(Self.userMessage(for: error))
                )
            }
        }
    }

    func reset() {
        connectionTask?.cancel()
        connectionTask = nil
        connectionState = .idle

        do {
            try credentials.deleteAPIKey()
            store.reset()
            currentProviderURLString = SettingsStore.defaultProviderURLString
            currentModel = SettingsStore.defaultModel
            currentAPIKey = ""
            draftProviderURL = currentProviderURLString
            draftModel = currentModel
            draftAPIKey = ""
            showsAPIKey = false
            loadMessage = nil
            saveState = .success
        } catch {
            saveState = .failure(Self.userMessage(for: error))
        }
    }

    func refreshLoginItemStatus() {
        loginItemStatus = loginItem.status
    }

    func setLoginItemEnabled(_ enabled: Bool) {
        do {
            try loginItem.setEnabled(enabled)
            loginItemStatus = loginItem.status
            loginItemMessage = nil
        } catch {
            loginItemStatus = loginItem.status
            loginItemMessage = Self.userMessage(for: error)
        }
    }

    func openLoginItemSettings() {
        loginItem.openSystemSettings()
        refreshLoginItemStatus()
    }

    private func validatedDraft() throws -> (url: URL, urlString: String, model: String) {
        let urlString = draftProviderURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }
        _ = try OpenAICompatibleClient.endpoint(for: url)

        let model = draftModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw SettingsValidationError.emptyModel
        }
        return (url, urlString, model)
    }

    private func clearCarriedKeyForChangedOrigin() {
        guard !currentAPIKey.isEmpty, draftAPIKey == currentAPIKey,
              let currentURL = URL(string: currentProviderURLString),
              let draftURL = URL(string: draftProviderURL),
              let currentOrigin = try? ProviderOrigin.canonicalString(for: currentURL),
              let draftOrigin = try? ProviderOrigin.canonicalString(for: draftURL),
              currentOrigin != draftOrigin
        else {
            return
        }

        draftAPIKey = ""
    }

    private func finishConnectionCheck(with state: FeedbackState) {
        connectionTask = nil
        connectionState = state
    }

    private static func userMessage(for error: any Error) -> String {
        if let localized = error as? any LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return "Не удалось выполнить действие. Попробуй ещё раз."
    }
}

private enum SettingsValidationError: LocalizedError {
    case emptyModel

    var errorDescription: String? {
        "Укажи модель."
    }
}

struct SettingsView: View {
    @Bindable var model: SettingsViewModel
    @State private var resetConfirmationVisible = false

    var body: some View {
        Form {
            Section("Подключение") {
                TextField("Адрес API", text: $model.draftProviderURL)
                    .textContentType(.URL)
                    .accessibilityHint("HTTPS-адрес OpenAI-совместимого сервера")

                TextField("Модель", text: $model.draftModel)
                    .accessibilityHint("Точное имя модели у провайдера")

                HStack {
                    Group {
                        if model.showsAPIKey {
                            TextField("API-ключ", text: $model.draftAPIKey)
                        } else {
                            SecureField("API-ключ", text: $model.draftAPIKey)
                        }
                    }
                    .accessibilityLabel("API-ключ")

                    Button {
                        model.showsAPIKey.toggle()
                    } label: {
                        Label(
                            model.showsAPIKey ? "Скрыть ключ" : "Показать ключ",
                            systemImage: model.showsAPIKey ? "eye.slash" : "eye"
                        )
                        .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help(model.showsAPIKey ? "Скрыть API-ключ" : "Показать API-ключ")
                    .accessibilityLabel(model.showsAPIKey ? "Скрыть API-ключ" : "Показать API-ключ")
                }

                if let message = model.loadMessage {
                    feedbackLabel(message, systemImage: "exclamationmark.triangle", color: .orange)
                }

                connectionFeedback

                HStack {
                    Button("Проверить соединение") {
                        model.checkConnection()
                    }
                    .disabled(!model.canCheckConnection)

                    Spacer()

                    Button("Сохранить") {
                        model.save()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }

            Section("Система") {
                Toggle(
                    "Запускать при входе",
                    isOn: Binding(
                        get: { model.loginItemIsEnabled },
                        set: { model.setLoginItemEnabled($0) }
                    )
                )
                .disabled(model.loginItemStatus == .unavailable)

                loginItemStatus

                if model.loginItemRequiresApproval {
                    Button("Открыть системные настройки") {
                        model.openLoginItemSettings()
                    }
                }

                if let message = model.loginItemMessage {
                    feedbackLabel(message, systemImage: "exclamationmark.triangle", color: .red)
                }
            }

            Section {
                Button("Сбросить настройки…", role: .destructive) {
                    resetConfirmationVisible = true
                }
            } footer: {
                Text("Сброс удалит адрес, модель и API-ключ из Keychain.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 560)
        .navigationTitle("Настройки Русификатора")
        .onAppear {
            model.refreshLoginItemStatus()
        }
        .confirmationDialog(
            "Сбросить настройки и удалить API-ключ?",
            isPresented: $resetConfirmationVisible
        ) {
            Button("Сбросить", role: .destructive) {
                model.reset()
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var connectionFeedback: some View {
        switch model.connectionState {
        case .idle:
            if model.saveState == .success {
                feedbackLabel("Настройки сохранены.", systemImage: "checkmark.circle", color: .green)
            } else if case let .failure(message) = model.saveState {
                feedbackLabel(message, systemImage: "exclamationmark.triangle", color: .red)
            }
        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Проверяем соединение…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        case .success:
            feedbackLabel(
                "Соединение работает. Нажми «Сохранить», чтобы применить настройки.",
                systemImage: "checkmark.circle",
                color: .green
            )
        case let .failure(message):
            feedbackLabel(message, systemImage: "exclamationmark.triangle", color: .red)
        }
    }

    @ViewBuilder
    private var loginItemStatus: some View {
        switch model.loginItemStatus {
        case .disabled:
            feedbackLabel("Автозапуск выключен.", systemImage: "minus.circle", color: .secondary)
        case .enabled:
            feedbackLabel("Автозапуск включён.", systemImage: "checkmark.circle", color: .green)
        case .requiresApproval:
            feedbackLabel(
                "macOS ожидает подтверждения автозапуска.",
                systemImage: "exclamationmark.circle",
                color: .orange
            )
        case .unavailable:
            feedbackLabel(
                "Автозапуск доступен после установки приложения в «Программы».",
                systemImage: "info.circle",
                color: .secondary
            )
        }
    }

    private func feedbackLabel(
        _ text: String,
        systemImage: String,
        color: Color
    ) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(color)
            .accessibilityElement(children: .combine)
    }
}
