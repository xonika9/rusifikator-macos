import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let history: HistoryStore
    let editor: EditorViewModel
    let settings: SettingsViewModel
    let coordinator: PopoverCoordinator

    private let popover = NSPopover()
    private var statusItem: NSStatusItem?

    override init() {
        let history = HistoryStore()
        self.history = history
        editor = EditorViewModel(history: history)
        settings = SettingsViewModel()
        coordinator = PopoverCoordinator()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurePopover()
        configureStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusItem = nil
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        Task {
            await history.flushPendingPersistence()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        coordinator.page = .editor
        showPopover()
        return true
    }

    func openSettings() {
        coordinator.page = .settings
        showPopover()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(
            width: PopoverLayout.width,
            height: PopoverLayout.height
        )
        popover.contentViewController = NSHostingController(
            rootView: PopoverRootView(
                coordinator: coordinator,
                editor: editor,
                history: history,
                settings: settings
            )
        )
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else {
            return
        }

        let image = NSImage(
            systemSymbolName: "character.cursor.ibeam",
            accessibilityDescription: "Русификатор"
        )
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = "Русификатор"
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    @objc
    private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApplication.shared.currentEvent else {
            togglePopover()
            return
        }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    @objc
    private func contextSettings() {
        openSettings()
    }

    @objc
    private func contextQuit() {
        quit()
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            coordinator.page = .editor
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button else {
            return
        }

        if popover.isShown {
            popover.contentViewController?.view.window?.makeKey()
            return
        }

        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showContextMenu() {
        popover.performClose(nil)
        guard let statusItem, let button = statusItem.button else {
            return
        }

        let menu = makeContextMenu()
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()

        let header = NSMenuItem(
            title: AppMetadata.menuHeader,
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Настройки…",
            action: #selector(contextSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Выход",
            action: #selector(contextQuit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }
}
