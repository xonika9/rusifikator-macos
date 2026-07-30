import SwiftUI

struct AppCommands: Commands {
    let openSettings: () -> Void
    let quit: () -> Void

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Настройки…", action: openSettings)
                .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .appTermination) {
            Button("Выход", action: quit)
                .keyboardShortcut("q", modifiers: .command)
        }
    }
}
