import AppKit
import SwiftUI

enum FixedSystemPrompt {
    static let text: String = {
        let url = Bundle.main.url(
            forResource: "SystemPrompt",
            withExtension: "txt"
        ) ?? Bundle.module.url(
            forResource: "SystemPrompt",
            withExtension: "txt"
        )

        guard let url else {
            fatalError("SystemPrompt.txt is missing from the application bundle")
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            fatalError("Unable to read SystemPrompt.txt: \(error)")
        }
    }()
}

@main
struct RusifikatorApp: App {
    @State private var editor = EditorViewModel()
    @State private var settings = SettingsViewModel()

    var body: some Scene {
        MenuBarExtra("Русификатор", systemImage: "character.cursor.ibeam") {
            EditorView(editor: editor, settings: settings)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: settings)
        }
        .commands {
            AppCommands()
        }
    }
}
