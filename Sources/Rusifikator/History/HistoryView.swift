import SwiftUI

struct HistoryView: View {
    let history: HistoryStore
    let close: () -> Void
    let openEntry: (HistoryEntry.ID) -> Void

    @State private var clearConfirmationVisible = false
    @State private var clearErrorVisible = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if history.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Загружается история")
            } else if history.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(history.entries) { entry in
                            historyRow(entry)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(AppTheme.window)
        .confirmationDialog(
            "Очистить всю историю?",
            isPresented: $clearConfirmationVisible
        ) {
            Button("Очистить", role: .destructive) {
                Task {
                    do {
                        try await history.clear()
                    } catch {
                        clearErrorVisible = true
                    }
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Локальные записи будут удалены. Текущий черновик не изменится.")
        }
        .alert(
            "Не удалось очистить историю",
            isPresented: $clearErrorVisible
        ) {
            Button("ОК", role: .cancel) {}
        } message: {
            Text("Записи остались на месте. Проверь доступ к диску и попробуй ещё раз.")
        }
    }

    private var toolbar: some View {
        ZStack {
            VStack(spacing: 1) {
                Text("История")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.text)

                Text("последние \(HistoryStore.maximumEntryCount) обработок")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textFaint)
            }

            HStack {
                Button(action: close) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(QuietIconButtonStyle())
                .help("Вернуться к тексту")
                .accessibilityLabel("Вернуться к тексту")

                Spacer()

                Button {
                    clearConfirmationVisible = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(QuietIconButtonStyle())
                .disabled(history.entries.isEmpty)
                .help("Очистить историю")
                .accessibilityLabel("Очистить историю")
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

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(AppTheme.textFaint)

            Text("Здесь появятся последние обработанные тексты")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textSoft)

            Text("Они хранятся только на этом Mac и не добавляются в новые запросы.")
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textFaint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        let date = Self.dateFormatter.string(from: entry.createdAt)
        let characterCount = CharacterCountFormatter.string(
            for: entry.source.count
        )
        let preview = accessibilityPreview(for: entry)

        return Button {
            openEntry(entry.id)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(date)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppTheme.accent)

                    Spacer()

                    Text(characterCount)
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textFaint)
                }

                Text(entry.result)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 66)
            .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(AppTheme.line, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(date). \(characterCount). \(preview)"
        )
        .accessibilityHint("Открывает исходный и готовый текст")
    }

    private func accessibilityPreview(for entry: HistoryEntry) -> String {
        let preview = entry.result.prefix(141)
        return preview.count > 140
            ? "\(preview.dropLast())…"
            : String(preview)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.setLocalizedDateFormatFromTemplate("d MMM, HH:mm")
        return formatter
    }()
}

struct HistoryDetailView: View {
    let entry: HistoryEntry
    let close: () -> Void

    @State private var copied = false
    @State private var copyConfirmationTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            VStack(alignment: .leading, spacing: 0) {
                sectionTitle("Расшифровка")
                readOnlySurface(text: entry.source)
                    .frame(height: 150)

                sectionTitle("Готовый текст")
                    .padding(.top, 12)
                resultSurface
                    .frame(height: 192)

                Label(
                    "Эта запись не меняет текст в редакторе",
                    systemImage: "lock.fill"
                )
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textFaint)
                .frame(height: 30, alignment: .bottomLeading)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .background(AppTheme.window)
        .onDisappear {
            copyConfirmationTask?.cancel()
        }
    }

    private var toolbar: some View {
        ZStack {
            VStack(spacing: 1) {
                Text("Обработка")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.text)

                Text(Self.dateFormatter.string(from: entry.createdAt))
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textFaint)
            }

            HStack {
                Button(action: close) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(QuietIconButtonStyle())
                .help("Вернуться к истории")
                .accessibilityLabel("Вернуться к истории")

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

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppTheme.textSoft)
            .frame(height: 22)
    }

    private func readOnlySurface(text: String) -> some View {
        AlignedTextView(
            text: .constant(text),
            isEditable: false
        )
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.line, lineWidth: 1)
        }
    }

    private var resultSurface: some View {
        HStack(spacing: 0) {
            AlignedTextView(
                text: .constant(entry.result),
                isEditable: false
            )

            VStack {
                Button {
                    SystemClipboardService().copy(entry.result)
                    copied = true
                    copyConfirmationTask?.cancel()
                    copyConfirmationTask = Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        guard !Task.isCancelled else {
                            return
                        }
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 34, height: 30)
                }
                .buttonStyle(QuietIconButtonStyle())
                .help(copied ? "Скопировано" : "Скопировать готовый текст")
                .accessibilityLabel(copied ? "Скопировано" : "Скопировать готовый текст")

                Spacer()
            }
            .frame(width: 40)
            .padding(.top, 3)
        }
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.line, lineWidth: 1)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
