import AppKit
import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            SettingsLink {
                Text("Настройки…")
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .appTermination) {
            Button("Выйти из Русификатора") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
