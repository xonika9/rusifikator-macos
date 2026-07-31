import SwiftUI

struct HistoryView: View {
    private static let previewLineLimit = 3
    private static let rowSpacing: CGFloat = 8
    private static let listBottomInset: CGFloat = 10

    /// Все записи должны помещаться на экран целиком, поэтому высота карточки
    /// выводится из окна, а не подбирается на глаз.
    private static let rowHeight: CGFloat = {
        let count = CGFloat(HistoryStore.maximumEntryCount)
        let free = PopoverLayout.height
            - PopoverLayout.headerHeight
            - PopoverLayout.contentTopInset
            - listBottomInset
            - rowSpacing * (count - 1)
        return (free / count).rounded(.down)
    }()

    let history: HistoryStore
    let close: () -> Void
    let openEntry: (HistoryEntry.ID) -> Void

    @State private var clearConfirmationVisible = false
    @State private var clearErrorVisible = false
    @State private var copiedEntryID: HistoryEntry.ID?
    @State private var copyConfirmationTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if let message = history.persistenceErrorMessage,
               !clearErrorVisible {
                persistenceError(message)
            }

            if history.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Загружается история")
            } else if history.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: Self.rowSpacing) {
                        ForEach(history.entries) { entry in
                            historyRow(entry)
                        }
                    }
                    .padding(.top, PopoverLayout.contentTopInset)
                    .padding(.horizontal, 16)
                    .padding(.bottom, Self.listBottomInset)
                }
                // Все записи помещаются на экран, поэтому список не должен
                // пружинить: прокручивать здесь нечего.
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .background(AppTheme.window)
        .onDisappear {
            copyConfirmationTask?.cancel()
        }
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
            Button("Повторить сохранение") {
                history.retryPersistence()
            }
            Button("ОК", role: .cancel) {}
        } message: {
            Text("Изменения не удалось полностью сохранить. Записи в этом окне не потеряны.")
        }
    }

    private func persistenceError(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textSoft)
                .frame(maxWidth: .infinity, alignment: .leading)

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
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppTheme.raised)
    }

    private var toolbar: some View {
        ScreenHeader(
            title: "История",
            subtitle: "последние \(HistoryStore.maximumEntryCount) обработок"
        ) {
            Button(action: close) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(QuietIconButtonStyle())
            .help("Вернуться к тексту")
            .accessibilityLabel("Вернуться к тексту")
        } trailing: {
            Button {
                clearConfirmationVisible = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(QuietIconButtonStyle())
            .disabled(history.entries.isEmpty)
            .help("Очистить историю")
            .accessibilityLabel("Очистить историю")
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
            VStack(alignment: .leading, spacing: 4) {
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
                    .lineLimit(Self.previewLineLimit)
                    .multilineTextAlignment(.leading)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(height: Self.rowHeight, alignment: .top)
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
        .overlay(alignment: .trailing) {
            copyButton(for: entry)
                .padding(.trailing, TextSurfaceAccessory.inset + 2)
        }
    }

    private func copyButton(for entry: HistoryEntry) -> some View {
        CopyTextButton(
            isConfirming: copiedEntryID == entry.id,
            surface: AppTheme.raised
        ) {
            copy(entry)
        }
        .accessibilityHint("Копирует готовый текст этой обработки")
    }

    private func copy(_ entry: HistoryEntry) {
        SystemClipboardService().copy(entry.result)
        copiedEntryID = entry.id
        copyConfirmationTask?.cancel()
        copyConfirmationTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else {
                return
            }
            copiedEntryID = nil
        }
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
        ScreenHeader(
            title: "Обработка",
            subtitle: Self.dateFormatter.string(from: entry.createdAt),
            leading: {
                Button(action: close) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(QuietIconButtonStyle())
                .help("Вернуться к истории")
                .accessibilityLabel("Вернуться к истории")
            }
        )
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
        AlignedTextView(
            text: .constant(entry.result),
            isEditable: false,
            trailingAccessoryButton: TextAccessoryButton(
                size: CGSize(
                    width: TextSurfaceAccessory.size,
                    height: TextSurfaceAccessory.size
                ),
                inset: TextSurfaceAccessory.inset,
                isEnabled: true
            )
        )
        .overlay(alignment: .topTrailing) {
            CopyTextButton(
                isConfirming: copied,
                surface: AppTheme.surface,
                action: copy
            )
            .padding(TextSurfaceAccessory.inset)
        }
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.line, lineWidth: 1)
        }
    }

    private func copy() {
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
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
