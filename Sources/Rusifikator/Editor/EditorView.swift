import AppKit
import SwiftUI

struct EditorView: View {
    @Bindable var editor: EditorViewModel
    let settings: SettingsViewModel

    @FocusState private var sourceIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            sourceEditor

            if editor.state == .error, let message = editor.errorMessage {
                errorPanel(message)
            } else if editor.state == .cancelled {
                Label("Обработка отменена. Исходный текст сохранён.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Обработка отменена. Исходный текст сохранён.")
            }

            primaryAction

            if let result = editor.result, editor.state == .success {
                resultPanel(result)
            }

            footer
        }
        .padding(16)
        .frame(width: 420, height: 560)
        .task {
            sourceIsFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Русификатор")
                .font(.headline)

            Spacer()

            Button {
                editor.clear()
                sourceIsFocused = true
            } label: {
                Label("Очистить", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .disabled(!editor.canClear)
            .help("Очистить исходный текст и результат")
            .accessibilityLabel("Очистить")

            SettingsLink {
                Label("Настройки", systemImage: "gearshape")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(",", modifiers: .command)
            .help("Открыть настройки")
            .accessibilityLabel("Настройки")
        }
    }

    private var sourceEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Расшифровка")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            TextEditor(text: $editor.source)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator, lineWidth: 1)
                }
                .overlay(alignment: .topLeading) {
                    if editor.source.isEmpty {
                        Text("Вставь сюда голосовую расшифровку…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }
                .focused($sourceIsFocused)
                .disabled(!editor.isSourceEditable)
                .frame(
                    minHeight: editor.result == nil ? 210 : 120,
                    maxHeight: editor.result == nil ? .infinity : 180
                )
                .accessibilityLabel("Исходная расшифровка")
                .accessibilityHint("Вставь текст, который нужно очистить")
        }
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
            HStack(spacing: 8) {
                if editor.state == .loading {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(editor.state == .loading ? "Отменить" : "Очистить текст")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(editor.state == .loading ? false : !editor.canSubmit)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityHint(
            editor.state == .loading
                ? "Отменяет текущий запрос и сохраняет исходный текст"
                : "Отправляет текущую расшифровку на обработку"
        )
    }

    private func errorPanel(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.caption)

                HStack {
                    Button("Повторить") {
                        settings.submit(editor)
                    }
                    .disabled(!editor.canSubmit)

                    SettingsLink {
                        Text("Открыть настройки")
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private func resultPanel(_ result: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Готовый текст", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)

                Spacer()

                Button {
                    editor.copyResult()
                } label: {
                    Label(
                        editor.copiedConfirmationVisible ? "Скопировано" : "Скопировать",
                        systemImage: editor.copiedConfirmationVisible ? "checkmark" : "doc.on.doc"
                    )
                }
                .controlSize(.small)
                .disabled(!editor.canCopy)
                .accessibilityHint("Копирует готовый текст в системный буфер")
            }

            ScrollView {
                Text(result)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator, lineWidth: 1)
            }
            .frame(maxHeight: .infinity)
            .accessibilityLabel("Готовый текст")
        }
        .frame(minHeight: 120, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Text("⌘↩ — обработать")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()

            Button("Выйти") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("q", modifiers: .command)
            .help("Завершить Русификатор")
        }
    }
}
