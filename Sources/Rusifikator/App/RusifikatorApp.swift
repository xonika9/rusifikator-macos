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

struct RusifikatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            AppCommands(
                openSettings: appDelegate.openSettings,
                quit: appDelegate.quit
            )
        }
    }
}
