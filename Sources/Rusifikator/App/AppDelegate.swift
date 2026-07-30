import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let editor = EditorViewModel()
    let settings = SettingsViewModel()
    let coordinator = PopoverCoordinator()

    private let popover = NSPopover()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurePopover()
        configureStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusItem = nil
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
        popover.contentSize = NSSize(width: 420, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: PopoverRootView(
                coordinator: coordinator,
                editor: editor,
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
