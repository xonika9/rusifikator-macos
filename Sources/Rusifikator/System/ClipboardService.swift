import AppKit

@MainActor
protocol ClipboardService {
    func copy(_ string: String)
}

@MainActor
struct SystemClipboardService: ClipboardService {
    func copy(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
