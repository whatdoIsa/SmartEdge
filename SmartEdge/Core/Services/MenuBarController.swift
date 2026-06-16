import AppKit
import Combine

@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private weak var appCoordinator: AppCoordinator?
    private var cancellables = Set<AnyCancellable>()

    func attach(to appCoordinator: AppCoordinator) {
        self.appCoordinator = appCoordinator
        setupStatusItem()
        observeNotchVisibility(appCoordinator)
    }

    func remove() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        cancellables.removeAll()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "rectangle.tophalf.filled",
                accessibilityDescription: "SmartEdge"
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = "SmartEdge"
        }
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let toggle = NSMenuItem(
            title: "Hide Notch",
            action: #selector(toggleNotch),
            keyEquivalent: ""
        )
        toggle.target = self
        toggle.tag = MenuTag.toggleNotch.rawValue
        menu.addItem(toggle)

        let quickActions = NSMenuItem(
            title: "Show Quick Actions",
            action: #selector(showQuickActions),
            keyEquivalent: ""
        )
        quickActions.target = self
        menu.addItem(quickActions)

        menu.addItem(NSMenuItem.separator())

        let pomodoro = NSMenuItem(
            title: "Start Focus Timer",
            action: #selector(togglePomodoro),
            keyEquivalent: ""
        )
        pomodoro.target = self
        pomodoro.tag = MenuTag.togglePomodoro.rawValue
        menu.addItem(pomodoro)

        let pomodoroStats = NSMenuItem(
            title: "Focus Statistics…",
            action: #selector(openPomodoroStatistics),
            keyEquivalent: ""
        )
        pomodoroStats.target = self
        menu.addItem(pomodoroStats)

        // Keyboard shortcut shown next to the title for discoverability.
        // The actual key handling is done by GlobalHotkeyManager so the
        // shortcut works system-wide, not only when SmartEdge is frontmost.
        let clipboardInNotch = NSMenuItem(
            title: "Show Clipboard in Notch  ⇧⌘V",
            action: #selector(showClipboardInNotch),
            keyEquivalent: ""
        )
        clipboardInNotch.target = self
        menu.addItem(clipboardInNotch)

        let clipboard = NSMenuItem(title: "Clipboard History", action: nil, keyEquivalent: "")
        clipboard.tag = MenuTag.clipboardSubmenu.rawValue
        clipboard.submenu = buildClipboardSubmenu()
        menu.addItem(clipboard)

        menu.addItem(NSMenuItem.separator())

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        let permissions = NSMenuItem(
            title: "Permissions…",
            action: #selector(openPermissions),
            keyEquivalent: ""
        )
        permissions.target = self
        menu.addItem(permissions)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(
            title: "Quit SmartEdge",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func observeNotchVisibility(_ coordinator: AppCoordinator) {
        coordinator.$isNotchVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                guard let self = self else { return }
                self.updateToggleTitle(isVisible: visible)
            }
            .store(in: &cancellables)

        coordinator.pomodoroViewModel.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                guard let self = self else { return }
                self.updatePomodoroTitle(isRunning: running)
            }
            .store(in: &cancellables)
    }

    private func updateToggleTitle(isVisible: Bool) {
        guard let item = statusItem?.menu?.item(withTag: MenuTag.toggleNotch.rawValue) else { return }
        item.title = isVisible ? "Hide Notch" : "Show Notch"
    }

    private func updatePomodoroTitle(isRunning: Bool) {
        guard let item = statusItem?.menu?.item(withTag: MenuTag.togglePomodoro.rawValue) else { return }
        item.title = isRunning ? "Pause Focus Timer" : "Start Focus Timer"
    }

    // MARK: - Menu Actions

    @objc private func toggleNotch() {
        guard let coordinator = appCoordinator else { return }
        if coordinator.isNotchVisible {
            coordinator.hideNotch()
        } else {
            coordinator.showNotch()
        }
    }

    @objc private func openSettings() {
        // Route through AppCoordinator → NotchWindowManager, which owns a
        // hand-built NSWindow for settings. We previously tried to call
        // SwiftUI's `Settings { }` scene via `showSettingsWindow:` /
        // `showPreferencesWindow:` selectors, but those selectors aren't
        // resolved on the user's macOS build, so ⌘, and the menu item
        // silently did nothing. The NotchWindowManager path is the same
        // one used by the in-app navigation and has been working.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        appCoordinator?.showSettings()
    }

    @objc private func openPermissions() {
        appCoordinator?.showPermissionGuide()
    }

    @objc private func togglePomodoro() {
        guard let coordinator = appCoordinator else { return }
        coordinator.pomodoroViewModel.toggle()
        coordinator.showPomodoro()
    }

    @objc private func openPomodoroStatistics() {
        appCoordinator?.showPomodoroStatistics()
    }

    private func buildClipboardSubmenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.delegate = self
        return submenu
    }

    private func refreshClipboardSubmenu(_ submenu: NSMenu) {
        submenu.removeAllItems()
        let history = appCoordinator?.clipboardViewModel.history ?? []
        if history.isEmpty {
            let empty = NSMenuItem(title: "No recent items", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
            return
        }
        for (index, item) in history.prefix(15).enumerated() {
            let title = previewLabel(for: item)
            let menuItem = NSMenuItem(
                title: title,
                action: #selector(copyClipboardItem(_:)),
                keyEquivalent: index < 9 ? "\(index + 1)" : ""
            )
            menuItem.target = self
            menuItem.representedObject = item.id
            submenu.addItem(menuItem)
        }
        submenu.addItem(NSMenuItem.separator())
        let clear = NSMenuItem(title: "Clear History", action: #selector(clearClipboard), keyEquivalent: "")
        clear.target = self
        submenu.addItem(clear)
    }

    private func previewLabel(for item: ClipboardItem) -> String {
        switch item.content {
        case .text(let text):
            let trimmed = text.replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "  ", with: " ")
            return trimmed.count > 60 ? String(trimmed.prefix(57)) + "…" : trimmed
        case .url(let url):
            return url.host ?? url.absoluteString
        case .file(let url):
            return url.lastPathComponent
        case .fileURLs(let urls):
            return "\(urls.count) files"
        case .image:
            return "Image"
        case .unknown:
            return "Unknown"
        }
    }

    @objc private func copyClipboardItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let viewModel = appCoordinator?.clipboardViewModel,
              let item = viewModel.history.first(where: { $0.id == id }) else {
            return
        }
        viewModel.copy(item)
    }

    @objc private func showClipboardInNotch() {
        appCoordinator?.showClipboardHistory()
    }

    @objc private func showQuickActions() {
        appCoordinator?.showQuickActions()
    }

    @objc private func clearClipboard() {
        appCoordinator?.clipboardViewModel.clearHistory()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private enum MenuTag: Int {
        case toggleNotch = 1
        case togglePomodoro = 2
        case clipboardSubmenu = 3
    }
}

// Refresh the clipboard submenu lazily when the user opens it.
extension MenuBarController: NSMenuDelegate {
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor [weak self] in
            self?.refreshClipboardSubmenu(menu)
        }
    }
}
