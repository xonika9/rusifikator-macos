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
    var body: some Scene {
        MenuBarExtra("Русификатор", systemImage: "character.cursor.ibeam") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Русификатор")
                    .font(.headline)

                Text(FixedSystemPrompt.text.isEmpty ? "Ресурс не загружен" : "Готов к работе")
                    .foregroundStyle(.secondary)

                SettingsLink {
                    Label("Настройки…", systemImage: "gearshape")
                }

                Divider()

                Button("Выйти") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding()
            .frame(width: 260)
        }
        .menuBarExtraStyle(.window)

        Settings {
            Form {
                Text("Настройки будут доступны в следующем этапе.")
            }
            .padding()
            .frame(width: 420, height: 140)
        }
    }
}
