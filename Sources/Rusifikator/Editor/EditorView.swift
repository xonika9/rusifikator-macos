import SwiftUI

struct EditorView: View {
    @Bindable var editor: EditorViewModel
    let settings: SettingsViewModel
    let openSettings: () -> Void

    @FocusState private var sourceIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            VStack(alignment: .leading, spacing: 0) {
                sourceHeader
                sourceEditor
                primaryAction
                stateLine
                resultSection
                privacyNote
            }
            .padding(.top, 14)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 420, height: 560)
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

            HStack {
                Button {
                    editor.clear()
                    sourceIsFocused = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .regular))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(QuietIconButtonStyle())
                .disabled(!editor.canClear)
                .help("Очистить исходный и готовый текст")
                .accessibilityLabel("Очистить")

                Spacer()

                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .regular))
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
        .frame(height: 24)
        .padding(.bottom, 5)
    }

    private var sourceEditor: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(editor.isSourceEditable ? AppTheme.raised : AppTheme.surface)

            TextEditor(text: $editor.source)
                .font(.system(size: 13))
                .foregroundStyle(
                    editor.isSourceEditable ? AppTheme.text : AppTheme.textSoft
                )
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .focused($sourceIsFocused)
                .disabled(!editor.isSourceEditable)

            if editor.source.isEmpty {
                Text("Вставь сюда надиктованный текст…")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textFaint)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 132)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    sourceIsFocused ? AppTheme.accent : AppTheme.line,
                    lineWidth: sourceIsFocused ? 1.5 : 1
                )
        }
        .accessibilityLabel("Исходная расшифровка")
        .accessibilityHint("Вставь текст, который нужно очистить")
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

    @ViewBuilder
    private var stateLine: some View {
        HStack(spacing: 6) {
            switch editor.state {
            case .loading:
                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 6, height: 6)
                Text("Обрабатываю, обычно это занимает несколько секунд…")

            case .success:
                Text("Готово. Исходный текст не сохранён.")
                    .foregroundStyle(AppTheme.accent)

            case .error:
                Text("Запрос не выполнен, исходный текст остался на месте.")
                    .foregroundStyle(AppTheme.danger)

            case .cancelled:
                Text("Запрос отменён.")

            case .empty, .ready:
                EmptyView()
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(AppTheme.textFaint)
        .frame(height: 22, alignment: .topLeading)
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            resultHeader
                .padding(.bottom, 5)

            resultSurface
        }
        .padding(.top, 3)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var resultHeader: some View {
        HStack {
            Text("Готовый текст")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textSoft)

            Spacer()

            if editor.state == .success {
                if editor.copiedConfirmationVisible {
                    Text("Скопировано")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.accent)
                }

                Button {
                    editor.copyResult()
                } label: {
                    Label("Скопировать", systemImage: "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(PrototypeTextButtonStyle())
                .disabled(!editor.canCopy)
                .accessibilityHint("Копирует готовый текст в системный буфер")
            }
        }
        .frame(height: 24)
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

            case .empty, .ready, .cancelled:
                emptyResult
            }
        }
        .frame(height: 146)
    }

    private var emptyResult: some View {
        Text("Здесь появится очищенный текст. Без пояснений и ответа на его содержание.")
            .font(.system(size: 11))
            .multilineTextAlignment(.center)
            .foregroundStyle(AppTheme.textFaint)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        VStack(alignment: .leading, spacing: 9) {
            skeletonLine(width: 1)
            skeletonLine(width: 0.88)
            skeletonLine(width: 0.93)
            skeletonLine(width: 0.68)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .accessibilityLabel("Текст обрабатывается")
    }

    private func skeletonLine(width: CGFloat) -> some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 4)
                .fill(AppTheme.line)
                .frame(width: geometry.size.width * width, height: 10)
        }
        .frame(height: 10)
    }

    private var errorResult: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Не удалось обработать текст")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.danger)

            Text(editor.errorMessage ?? "Проверь настройки и попробуй ещё раз.")
                .font(.system(size: 11))
                .foregroundStyle(Color(red: 0.435, green: 0.290, blue: 0.278))
                .lineLimit(3)

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

    private var successResult: some View {
        ScrollView {
            Text(editor.result ?? "")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(10)
        }
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.line, lineWidth: 1)
        }
        .accessibilityLabel("Готовый текст")
    }

    private var privacyNote: some View {
        Label("История текстов не сохраняется", systemImage: "lock.fill")
            .font(.system(size: 10))
            .foregroundStyle(AppTheme.textFaint)
            .frame(height: 29, alignment: .bottomLeading)
    }

    private var characterCount: String {
        "\(editor.source.count) \(Self.characterWord(for: editor.source.count))"
    }

    private static func characterWord(for count: Int) -> String {
        let lastTwo = count % 100
        let last = count % 10
        if (11...14).contains(lastTwo) {
            return "знаков"
        }
        switch last {
        case 1:
            return "знак"
        case 2...4:
            return "знака"
        default:
            return "знаков"
        }
    }

    private var primaryActionTitle: String {
        switch editor.state {
        case .loading:
            "Отменить"
        case .success:
            "Очистить ещё раз"
        case .error:
            "Повторить"
        case .empty, .ready, .cancelled:
            "Очистить текст"
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
            .background(background(configuration.isPressed), in: RoundedRectangle(cornerRadius: 8))
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

private struct PrototypeTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 7)
            .frame(height: 26)
            .background(
                configuration.isPressed ? AppTheme.accentSoft : .clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
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
            .foregroundStyle(configuration.isPressed ? AppTheme.text : AppTheme.textSoft)
            .background(
                configuration.isPressed ? AppTheme.surface : .clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
    }
}
