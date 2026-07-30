import SwiftUI

struct EditorView: View {
    private static let textSurfaceHeight: CGFloat = 149
    private static let textSurfaceAccessorySize = CGSize(width: 40, height: 36)

    @Bindable var editor: EditorViewModel
    let history: HistoryStore
    let settings: SettingsViewModel
    let openHistory: () -> Void
    let openSettings: () -> Void

    @State private var sourceIsFocused = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            VStack(alignment: .leading, spacing: 0) {
                sourceHeader
                sourceEditor
                primaryAction
                resultHeader
                resultSurface
                footer
            }
            .padding(.top, 8)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background(AppTheme.window)
        .task {
            sourceIsFocused = true
        }
    }

    private var toolbar: some View {
        ZStack {
            VStack(spacing: 1) {
                Text("Русификатор")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.text)

                Text("готовит текст к отправке")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textFaint)
            }

            HStack(spacing: 2) {
                Spacer()

                Button(action: openHistory) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(QuietIconButtonStyle())
                .help("История последних обработок")
                .accessibilityLabel("Открыть историю")

                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(QuietIconButtonStyle())
                .keyboardShortcut(",", modifiers: .command)
                .help("Настройки (⌘,)")
                .accessibilityLabel("Открыть настройки")
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

    private var sourceHeader: some View {
        HStack {
            Text("Расшифровка")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textSoft)

            Spacer()

            Text(characterCount)
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textFaint)
        }
        .frame(height: 22)
        .padding(.bottom, 4)
    }

    private var sourceEditor: some View {
        AlignedTextView(
            text: $editor.source,
            isFocused: $sourceIsFocused,
            placeholder: "Вставь сюда надиктованный текст…",
            isEditable: editor.isSourceEditable,
            trailingAccessorySize: Self.textSurfaceAccessorySize
        )
        .overlay(alignment: .topTrailing) {
            Button {
                editor.clear()
                sourceIsFocused = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .frame(width: 34, height: 30)
            }
            .buttonStyle(QuietIconButtonStyle())
            .disabled(!editor.canClear || !editor.isSourceEditable)
            .opacity(editor.source.isEmpty ? 0 : 1)
            .help("Очистить исходный и готовый текст")
            .accessibilityLabel("Очистить текст")
            .frame(width: 40)
            .padding(.top, 3)
        }
        .frame(height: Self.textSurfaceHeight)
        .background(editor.isSourceEditable ? AppTheme.raised : AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    sourceIsFocused ? AppTheme.accent : AppTheme.line,
                    lineWidth: sourceIsFocused ? 1.5 : 1
                )
        }
        .accessibilityLabel("Исходная расшифровка")
        .accessibilityHint("Вставь текст, который нужно обработать")
    }

    private var primaryAction: some View {
        Button {
            if editor.canCancel {
                editor.cancel()
                sourceIsFocused = true
            } else {
                settings.submit(editor)
            }
        } label: {
            ZStack {
                Text(primaryActionTitle)
                    .font(.system(size: 13, weight: .semibold))

                if editor.state != .loading {
                    HStack {
                        Spacer()
                        Text("⌘ ↩")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(shortcutColor.opacity(0.35), lineWidth: 1)
                            )
                            .foregroundStyle(shortcutColor)
                    }
                    .padding(.horizontal, 10)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
        }
        .buttonStyle(
            PrototypePrimaryButtonStyle(
                state: editor.state,
                enabled: editor.canSubmit || editor.canCancel
            )
        )
        .disabled(!editor.canSubmit && !editor.canCancel)
        .keyboardShortcut(.return, modifiers: .command)
        .padding(.top, 10)
        .accessibilityHint(
            editor.canCancel
                ? "Отменяет текущий запрос и сохраняет исходный текст"
                : "Отправляет текущую расшифровку на обработку"
        )
    }

    private var resultHeader: some View {
        Text("Готовый текст")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppTheme.textSoft)
            .frame(height: 22)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private var resultSurface: some View {
        Group {
            switch editor.state {
            case .loading:
                loadingResult
            case .error:
                errorResult
            case .success:
                successResult
            case .cancelled:
                cancelledResult
            case .empty, .ready:
                emptyResult
            }
        }
        .frame(height: Self.textSurfaceHeight)
    }

    private var emptyResult: some View {
        Text("Здесь появится обработанный текст")
            .font(.system(size: 11))
            .foregroundStyle(AppTheme.textFaint)
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        AppTheme.line,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
            }
    }

    private var loadingResult: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Обрабатываю…")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.textSoft)
            Text(
                "Запрос завершится не позднее чем через \(Int(OpenAICompatibleClient.processingTimeout)) секунд"
            )
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textFaint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.line, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Текст обрабатывается")
    }

    private var errorResult: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Не удалось обработать текст")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.danger)

            Text(editor.errorMessage ?? "Проверь настройки и попробуй ещё раз.")
                .font(.system(size: 11))
                .foregroundStyle(Color(red: 0.435, green: 0.290, blue: 0.278))
                .fixedSize(horizontal: false, vertical: true)

            Button("Открыть настройки", action: openSettings)
                .buttonStyle(PrototypeErrorLinkStyle())

            Spacer()
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.dangerSoft, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.danger.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var cancelledResult: some View {
        VStack(spacing: 6) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 18))
                .foregroundStyle(AppTheme.textFaint)
            Text("Обработка отменена")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textSoft)
            Text("Исходный текст остался на месте.")
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textFaint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.line, lineWidth: 1)
        }
    }

    private var successResult: some View {
        AlignedTextView(
            text: .constant(editor.result ?? ""),
            isEditable: false,
            trailingAccessorySize: Self.textSurfaceAccessorySize
        )
        .overlay(alignment: .topTrailing) {
            Button {
                editor.copyResult()
            } label: {
                Image(
                    systemName: editor.copiedConfirmationVisible
                        ? "checkmark"
                        : "doc.on.doc"
                )
                .font(.system(size: 13, weight: .medium))
                .frame(width: 34, height: 30)
            }
            .buttonStyle(QuietIconButtonStyle())
            .disabled(!editor.canCopy)
            .help(
                editor.copiedConfirmationVisible
                    ? "Скопировано"
                    : "Скопировать готовый текст"
            )
            .accessibilityLabel(
                editor.copiedConfirmationVisible
                    ? "Скопировано"
                    : "Скопировать готовый текст"
            )
            .frame(width: 40)
            .padding(.top, 3)
        }
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.line, lineWidth: 1)
        }
        .accessibilityLabel("Готовый текст")
    }

    @ViewBuilder
    private var footer: some View {
        if let message = history.persistenceErrorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)

                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textSoft)
                    .lineLimit(1)
                    .help(message)

                Spacer(minLength: 0)

                Button(
                    history.isRetryingPersistence
                        ? "Сохранение…"
                        : "Повторить"
                ) {
                    history.retryPersistence()
                }
                .font(.system(size: 10, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accent)
                .disabled(history.isRetryingPersistence)
            }
            .frame(height: 28)
            .accessibilityElement(children: .contain)
        } else {
            Label(
                "Последние \(HistoryStore.maximumEntryCount) обработок хранятся только на этом Mac",
                systemImage: "lock.fill"
            )
            .font(.system(size: 10))
            .foregroundStyle(AppTheme.textFaint)
            .frame(height: 28, alignment: .bottomLeading)
        }
    }

    private var characterCount: String {
        CharacterCountFormatter.string(for: editor.source.count)
    }

    private var primaryActionTitle: String {
        switch editor.state {
        case .loading:
            "Отменить"
        case .success:
            "Отправить ещё раз"
        case .error:
            "Повторить"
        case .empty, .ready, .cancelled:
            "Отправить"
        }
    }

    private var shortcutColor: Color {
        editor.canSubmit ? .white.opacity(0.74) : AppTheme.textFaint
    }
}

private struct PrototypePrimaryButtonStyle: ButtonStyle {
    let state: EditorState
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background(
                background(configuration.isPressed),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .offset(y: configuration.isPressed && enabled ? 1 : 0)
    }

    private var foreground: Color {
        if state == .loading {
            return AppTheme.text
        }
        return enabled ? .white : AppTheme.textFaint
    }

    private func background(_ pressed: Bool) -> Color {
        if state == .loading {
            return AppTheme.surface
        }
        guard enabled else {
            return Color(red: 0.812, green: 0.827, blue: 0.816)
        }
        return pressed ? AppTheme.accentHover : AppTheme.accent
    }
}

private struct PrototypeErrorLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppTheme.danger)
            .underline()
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

struct QuietIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(
                configuration.isPressed ? AppTheme.text : AppTheme.textSoft
            )
            .background(
                configuration.isPressed ? AppTheme.surface : .clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
    }
}
