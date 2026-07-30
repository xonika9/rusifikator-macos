import Observation
import SwiftUI

@Observable
@MainActor
final class PopoverCoordinator {
    enum Page: Equatable {
        case editor
        case settings
    }

    var page: Page = .editor
}

struct PopoverRootView: View {
    @Bindable var coordinator: PopoverCoordinator
    @Bindable var editor: EditorViewModel
    let settings: SettingsViewModel

    var body: some View {
        Group {
            switch coordinator.page {
            case .editor:
                EditorView(
                    editor: editor,
                    settings: settings,
                    openSettings: {
                        coordinator.page = .settings
                    }
                )

            case .settings:
                SettingsView(
                    model: settings,
                    close: {
                        coordinator.page = .editor
                    }
                )
            }
        }
        .frame(width: 420, height: 560)
        .background(AppTheme.window)
    }
}
