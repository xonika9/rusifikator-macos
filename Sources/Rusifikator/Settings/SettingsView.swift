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
    private struct ConnectionDraft: Equatable, Sendable {
        let providerURL: String
        let model: String
        let apiKey: String
    }

    enum ConnectionState: Equatable {
        case idle
        case checking
        case success
        case failure(String)
    }

    enum SaveState: Equatable {
        case idle
        case success
        case failure(String)
    }

    var draftProviderURL: String {
        didSet {
            clearCarriedKeyForChangedOrigin()
            draftDidChange()
        }
    }
    var draftModel: String {
        didSet {
            draftDidChange()
        }
    }
    var draftAPIKey: String {
        didSet {
            draftDidChange()
        }
    }
    var showsAPIKey = false

    private(set) var connectionState: ConnectionState = .idle
    private(set) var saveState: SaveState = .idle
    private(set) var loadMessage: String?
    private(set) var loginItemStatus: LoginItemController.Status
    private(set) var loginItemMessage: String?

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

    @ObservationIgnored
    private var activeConnectionCheckID: UUID?

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
        connectionTask == nil
    }

    var loginItemIsEnabled: Bool {
        loginItemStatus == .enabled || loginItemStatus == .requiresApproval
    }

    var loginItemRequiresApproval: Bool {
        loginItemStatus == .requiresApproval
    }

    func submit(_ editor: EditorViewModel) {
        guard let baseURL = URL(string: store.providerURLString) else {
            return
        }

        let apiKey: String
        do {
            apiKey = try credentials.apiKey(for: baseURL) ?? ""
            loadMessage = nil
        } catch {
            apiKey = ""
            loadMessage = Self.userMessage(for: error)
        }

        editor.submit(
            baseURL: baseURL,
            model: store.model,
            apiKey: apiKey
        )
    }

    func save() {
        do {
            let values = try validatedDraft()
            let key = draftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveKey: String
            if !key.isEmpty {
                try credentials.saveAPIKey(key, for: values.url)
                effectiveKey = key
            } else {
                do {
                    effectiveKey = try credentials.apiKey(for: values.url) ?? ""
                } catch CredentialStoreError.providerOriginMismatch {
                    effectiveKey = ""
                }
            }

            store.providerURLString = values.urlString
            store.model = values.model
            currentAPIKey = effectiveKey
            draftProviderURL = values.urlString
            draftModel = values.model
            draftAPIKey = effectiveKey
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
        let connectionDraft = currentConnectionDraft
        let checkID = UUID()
        activeConnectionCheckID = checkID
        connectionState = .checking
        connectionTask = Task { [weak self, connectionChecker] in
            do {
                try await connectionChecker.checkConnection(
                    baseURL: values.url,
                    model: values.model,
                    apiKey: key
                )
                guard !Task.isCancelled else { return }
                self?.finishConnectionCheck(
                    id: checkID,
                    draft: connectionDraft,
                    with: .success
                )
            } catch {
                guard !Task.isCancelled else { return }
                self?.finishConnectionCheck(
                    id: checkID,
                    draft: connectionDraft,
                    with: .failure(Self.userMessage(for: error))
                )
            }
        }
    }

    func reset() {
        invalidateConnectionCheck()
        connectionState = .idle

        do {
            try credentials.deleteAPIKey()
            store.reset()
            currentAPIKey = ""
            draftProviderURL = store.providerURLString
            draftModel = store.model
            draftAPIKey = ""
            showsAPIKey = false
            loadMessage = nil
            saveState = .success
        } catch {
            saveState = .failure(Self.userMessage(for: error))
        }
    }

    func discardDraftChanges() {
        invalidateConnectionCheck()
        connectionState = .idle
        saveState = .idle

        let providerURL = store.providerURLString
        draftProviderURL = providerURL
        draftModel = store.model

        guard let url = URL(string: providerURL) else {
            currentAPIKey = ""
            draftAPIKey = ""
            loadMessage = APIError.invalidURL.localizedDescription
            return
        }

        do {
            let apiKey = try credentials.apiKey(for: url) ?? ""
            currentAPIKey = apiKey
            draftAPIKey = apiKey
            loadMessage = nil
        } catch {
            currentAPIKey = ""
            draftAPIKey = ""
            loadMessage = Self.userMessage(for: error)
        }
    }

    func refreshLoginItemStatus() {
        let status = loginItem.status
        guard loginItemStatus != status else {
            return
        }
        loginItemStatus = status
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
              let currentURL = URL(string: store.providerURLString),
              let draftURL = URL(string: draftProviderURL),
              let currentOrigin = try? ProviderOrigin.canonicalString(for: currentURL),
              let draftOrigin = try? ProviderOrigin.canonicalString(for: draftURL),
              currentOrigin != draftOrigin
        else {
            return
        }

        draftAPIKey = ""
    }

    private var currentConnectionDraft: ConnectionDraft {
        ConnectionDraft(
            providerURL: draftProviderURL.trimmingCharacters(in: .whitespacesAndNewlines),
            model: draftModel.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: draftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func draftDidChange() {
        invalidateConnectionCheck()
        connectionState = .idle
        saveState = .idle
    }

    private func invalidateConnectionCheck() {
        activeConnectionCheckID = nil
        connectionTask?.cancel()
        connectionTask = nil
    }

    private func finishConnectionCheck(
        id: UUID,
        draft: ConnectionDraft,
        with state: ConnectionState
    ) {
        guard activeConnectionCheckID == id, currentConnectionDraft == draft else {
            return
        }

        activeConnectionCheckID = nil
        connectionTask = nil
        connectionState = state
    }

    private static func userMessage(for error: any Error) -> String {
        if let apiError = error as? APIError,
           let description = apiError.errorDescription {
            return description
        }
        if let credentialError = error as? CredentialStoreError,
           let description = credentialError.errorDescription {
            return description
        }
        if let validationError = error as? SettingsValidationError,
           let description = validationError.errorDescription {
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
    let close: () -> Void

    @State private var resetConfirmationVisible = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Параметры хранятся только на этом Mac. API-ключ лежит в Keychain.")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 13)

                    fieldGroup(
                        title: "Адрес API",
                        hint: "Приложение само приведёт адрес к /v1/chat/completions."
                    ) {
                        styledTextField(
                            TextField("https://example.com/v1", text: $model.draftProviderURL)
                                .textContentType(.URL)
                        )
                        .accessibilityHint("HTTPS-адрес OpenAI-совместимого сервера")
                    }

                    fieldGroup(
                        title: "API-ключ",
                        hint: "Ключ не записывается в настройки или журналы."
                    ) {
                        ZStack(alignment: .trailing) {
                            Group {
                                if model.showsAPIKey {
                                    TextField("API-ключ", text: $model.draftAPIKey)
                                } else {
                                    SecureField("API-ключ", text: $model.draftAPIKey)
                                }
                            }
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.text)
                            .padding(.leading, 9)
                            .padding(.trailing, 38)
                            .frame(height: 34)
                            .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppTheme.line, lineWidth: 1)
                            }
                            .accessibilityLabel("API-ключ")

                            Button {
                                model.showsAPIKey.toggle()
                            } label: {
                                Image(systemName: model.showsAPIKey ? "eye.slash" : "eye")
                                    .font(.system(size: 13))
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(QuietIconButtonStyle())
                            .padding(.trailing, 2)
                            .help(model.showsAPIKey ? "Скрыть API-ключ" : "Показать API-ключ")
                            .accessibilityLabel(
                                model.showsAPIKey ? "Скрыть API-ключ" : "Показать API-ключ"
                            )
                        }
                    }

                    fieldGroup(
                        title: "Модель",
                        hint: "Точное имя модели или алиаса у провайдера."
                    ) {
                        styledTextField(
                            TextField("Модель", text: $model.draftModel)
                        )
                    }

                    loginItemRow
                    connectionPanel

                }
                .padding(.top, 14)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            settingsFeedbackBar
            footer
        }
        .background(AppTheme.window)
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
        } message: {
            Text("Адрес и модель вернутся к исходным, ключ будет удалён из Keychain.")
        }
    }

    private var toolbar: some View {
        ZStack {
            VStack(spacing: 1) {
                Text("Настройки")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.text)

                Text("OpenAI-совместимый API")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textFaint)
            }

            HStack {
                Button {
                    model.discardDraftChanges()
                    close()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(QuietIconButtonStyle())
                .help("Вернуться к тексту")
                .accessibilityLabel("Вернуться к тексту")

                Spacer()
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 46)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.text.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func fieldGroup<Content: View>(
        title: String,
        hint: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textSoft)
                .padding(.bottom, 5)

            content()

            Text(hint)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textFaint)
                .padding(.top, 4)
        }
        .padding(.bottom, 12)
    }

    private func styledTextField<Field: View>(_ field: Field) -> some View {
        field
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(AppTheme.text)
            .padding(.horizontal, 9)
            .frame(height: 34)
            .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.line, lineWidth: 1)
            }
    }

    private var loginItemRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Запускать при входе")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.text)

                    Text(loginItemDescription)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textFaint)
                }

                Spacer()

                Toggle(
                    "Запускать при входе",
                    isOn: Binding(
                        get: { model.loginItemIsEnabled },
                        set: { model.setLoginItemEnabled($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(AppTheme.accent)
                .disabled(model.loginItemStatus == .unavailable)
            }
            .frame(minHeight: 42)

            if model.loginItemRequiresApproval {
                Button("Подтвердить в системных настройках") {
                    model.openLoginItemSettings()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.accent)
                .padding(.bottom, 6)
            }
        }
        .padding(.vertical, 2)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.text.opacity(0.08))
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.text.opacity(0.08))
                .frame(height: 1)
        }
        .padding(.bottom, 13)
    }

    private var connectionPanel: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(connectionTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(connectionTitleColor)

                Text("Проверка отправит короткий тестовый запрос.")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textSoft)
            }

            Spacer()

            Button(model.connectionState == .checking ? "Проверяю…" : "Проверить") {
                model.checkConnection()
            }
            .buttonStyle(SettingsSecondaryButtonStyle())
            .disabled(!model.canCheckConnection)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 48)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Сбросить…", role: .destructive) {
                resetConfirmationVisible = true
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(AppTheme.danger)

            Spacer()

            Button("Отмена") {
                model.discardDraftChanges()
                close()
            }
            .buttonStyle(SettingsSecondaryButtonStyle())

            Button("Сохранить") {
                model.save()
                if model.saveState == .success {
                    close()
                }
            }
            .buttonStyle(SettingsSaveButtonStyle())
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.text.opacity(0.08))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var settingsFeedbackBar: some View {
        if let feedback = settingsFeedback {
            Text(feedback.text)
                .font(.system(size: 10))
                .foregroundStyle(feedback.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(AppTheme.window)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AppTheme.text.opacity(0.08))
                        .frame(height: 1)
                }
                .accessibilityElement(children: .combine)
        }
    }

    private var connectionTitle: String {
        switch model.connectionState {
        case .idle:
            "Соединение не проверено"
        case .checking:
            "Проверяю соединение…"
        case .success:
            "Соединение работает"
        case .failure:
            "Соединение не установлено"
        }
    }

    private var connectionTitleColor: Color {
        switch model.connectionState {
        case .success:
            AppTheme.accent
        case .failure:
            AppTheme.danger
        case .idle, .checking:
            AppTheme.text
        }
    }

    private var loginItemDescription: String {
        switch model.loginItemStatus {
        case .disabled:
            "Автозапуск выключен"
        case .enabled:
            "Значок появится в строке меню"
        case .requiresApproval:
            "macOS ожидает подтверждения"
        case .unavailable:
            "Доступно после установки в «Программы»"
        }
    }

    private var settingsFeedback: (text: String, color: Color)? {
        if let message = model.loadMessage {
            return (message, AppTheme.danger)
        }
        if let message = model.loginItemMessage {
            return (message, AppTheme.danger)
        }
        if case let .failure(message) = model.connectionState {
            return (message, AppTheme.danger)
        }
        if case let .failure(message) = model.saveState {
            return (message, AppTheme.danger)
        }
        if model.saveState == .success {
            return ("Настройки сохранены.", AppTheme.accent)
        }
        return nil
    }
}

private struct SettingsSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppTheme.text)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                configuration.isPressed ? AppTheme.surface : AppTheme.raised,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(AppTheme.lineStrong, lineWidth: 1)
            }
    }
}

private struct SettingsSaveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minWidth: 92, minHeight: 32)
            .background(
                configuration.isPressed ? AppTheme.accentHover : AppTheme.accent,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .offset(y: configuration.isPressed ? 1 : 0)
    }
}
