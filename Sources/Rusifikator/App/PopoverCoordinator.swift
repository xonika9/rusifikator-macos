import Observation
import SwiftUI

@Observable
@MainActor
final class PopoverCoordinator {
    enum Page {
        case editor
        case history
        case historyDetail(HistoryEntry.ID)
        case settings
    }

    var page: Page = .editor
}

struct PopoverRootView: View {
    let coordinator: PopoverCoordinator
    @Bindable var editor: EditorViewModel
    let history: HistoryStore
    let settings: SettingsViewModel
    let updates: UpdateViewModel

    var body: some View {
        Group {
            switch coordinator.page {
            case .editor:
                EditorView(
                    editor: editor,
                    history: history,
                    settings: settings,
                    openHistory: {
                        coordinator.page = .history
                    },
                    openSettings: {
                        coordinator.page = .settings
                    }
                )

            case .history:
                historyView

            case let .historyDetail(id):
                if let entry = history.entries.first(where: { $0.id == id }) {
                    HistoryDetailView(
                        entry: entry,
                        close: {
                            coordinator.page = .history
                        }
                    )
                } else {
                    historyView
                }

            case .settings:
                SettingsView(
                    model: settings,
                    updates: updates,
                    close: {
                        coordinator.page = .editor
                    }
                )
            }
        }
        // Экраны с содержимым фиксированной высоты не дотягиваются до нижнего
        // края окна. Без верхнего выравнивания SwiftUI центрирует такой экран,
        // и панель уезжает вниз на пару точек — на переходах это читается как
        // прыгающая высота шапки.
        .frame(
            width: PopoverLayout.width,
            height: PopoverLayout.height,
            alignment: .top
        )
        .background(AppTheme.window)
    }

    private var historyView: some View {
        HistoryView(
            history: history,
            close: {
                coordinator.page = .editor
            },
            openEntry: { id in
                coordinator.page = .historyDetail(id)
            }
        )
    }
}
