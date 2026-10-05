import AppKit
import Carbon
import ServiceManagement
import SwiftUI

/// A panel that can take keyboard input without pulling focus away from the app you're pasting into.
final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    var onHide: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        onHide?()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let store = HistoryStore()
    private lazy var watcher = ClipboardWatcher(store: store)
    private let dock = DockAnimator()
    private var statusItem: NSStatusItem!
    private var panel: HistoryPanel?
    private var hotKey: HotKey?
    private var previousApp: NSRunningApplication?

    private var autoPaste: Bool {
        get { UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoPaste") }
    }

    /// The last app you were using that isn't this one, so "Paste" goes back there
    /// even when the history was opened by clicking the Dock icon.
    private var lastOtherApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        NSApp.applicationIconImage = NSImage(named: "AppIcon")

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.lastOtherApp = app }
        }
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastOtherApp = front
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = MenuBarIcon.image()
        dock.statusButton = statusItem.button
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        watcher.onCapture = { [weak self] in self?.dock.playCopy() }
        watcher.start()

        // ⌘⇧V opens the history from anywhere
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            MainActor.assumeIsolated { self?.togglePanel() }
        }

        // Show the window on first launch so it's clear the app is running
        // (the menu bar icon can be hidden behind the notch on MacBooks).
        let firstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunched")
        UserDefaults.standard.set(true, forKey: "hasLaunched")
        if firstLaunch || CommandLine.arguments.contains("--show") { showPanel() }
    }

    /// Clicking the Dock icon, or opening the app again from Applications or Spotlight, shows the history.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    /// Right-clicking the Dock icon shows the recent items too.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        for item in store.items.prefix(8) {
            var title = item.title
            if title.count > 45 { title = String(title.prefix(45)) + "…" }
            let mi = NSMenuItem(title: title, action: #selector(pickFromMenu(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = item.id
            menu.addItem(mi)
        }
        return menu
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Clipboard History", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let open = NSMenuItem(title: "Open History", action: #selector(openHistory), keyEquivalent: "v")
        open.keyEquivalentModifierMask = [.command, .shift]
        open.target = self
        appMenu.addItem(open)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Clipboard History", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Clipboard History", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        // Standard Edit menu so ⌘C / ⌘V / ⌘A work in the search box
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        return main
    }

    // MARK: History panel

    func togglePanel() {
        if let panel, panel.isVisible { closePanel() } else { showPanel() }
    }

    private func showPanel() {
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? lastOtherApp : front
        let panel = self.panel ?? makePanel()
        self.panel = panel

        // A fresh view each time, so the search is cleared and times ("23 hours ago") are current.
        panel.contentView = NSHostingView(rootView: HistoryView(
            store: store,
            onPaste: { [weak self] in self?.pick($0, paste: true) },
            onCopy: { [weak self] in self?.pick($0, paste: false) },
            onClose: { [weak self] in self?.closePanel() }
        ))

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: vf.midX - panel.frame.width / 2,
                                         y: vf.midY - panel.frame.height / 2 + vf.height * 0.08))
        }
        panel.makeKeyAndOrderFront(nil)
        dock.setFanned(true)
    }

    private func makePanel() -> HistoryPanel {
        let panel = HistoryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 540),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.onHide = { [weak self] in self?.dock.setFanned(false) }
        return panel
    }

    func closePanel() {
        panel?.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        closePanel() // clicking elsewhere closes the history
    }

    /// Puts the item back on the clipboard and, if allowed, pastes it into the app you were using.
    private func pick(_ item: ClipItem, paste: Bool) {
        Paster.copy(item, store: store)
        closePanel()
        guard paste, autoPaste else { return }
        guard Paster.canAutoPaste else {
            if !UserDefaults.standard.bool(forKey: "askedAccessibility") {
                UserDefaults.standard.set(true, forKey: "askedAccessibility")
                Paster.requestAccessibility()
            }
            return // still copied, so ⌘V works
        }
        previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Paster.pressCommandV()
        }
    }

    // MARK: Menu bar menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let open = NSMenuItem(title: "Open History", action: #selector(openHistory), keyEquivalent: "v")
        open.keyEquivalentModifierMask = [.command, .shift]
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())

        let recent = store.items.prefix(10)
        if recent.isEmpty {
            let empty = NSMenuItem(title: "Nothing copied yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for (i, item) in recent.enumerated() {
            var title = item.title
            if title.count > 50 { title = String(title.prefix(50)) + "…" }
            let mi = NSMenuItem(title: title, action: #selector(pickFromMenu(_:)), keyEquivalent: i < 9 ? "\(i + 1)" : "")
            mi.target = self
            mi.representedObject = item.id
            mi.toolTip = item.subtitle
            if item.kind == .image, let thumb = store.thumbnail(for: item)?.copy() as? NSImage {
                thumb.size = NSSize(width: 24, height: 24)
                mi.image = thumb
            }
            menu.addItem(mi)
        }
        menu.addItem(.separator())

        let pause = NSMenuItem(title: watcher.isPaused ? "Resume Recording" : "Pause Recording",
                               action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        let paste = NSMenuItem(title: "Paste Automatically", action: #selector(toggleAutoPaste), keyEquivalent: "")
        paste.target = self
        paste.state = autoPaste ? .on : .off
        menu.addItem(paste)

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let folder = NSMenuItem(title: "Show Saved Files in Finder", action: #selector(showFolder), keyEquivalent: "")
        folder.target = self
        menu.addItem(folder)

        let clear = NSMenuItem(title: "Clear History…", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Clipboard History", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func openHistory() { showPanel() }

    @objc private func pickFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let item = store.items.first(where: { $0.id == id }) else { return }
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? lastOtherApp : front
        pick(item, paste: true)
    }

    @objc private func togglePause() { watcher.isPaused.toggle() }

    @objc private func toggleAutoPaste() {
        autoPaste.toggle()
        if autoPaste && !Paster.canAutoPaste { Paster.requestAccessibility() }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert("Couldn't change Open at Login", error.localizedDescription)
        }
    }

    @objc private func showFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([store.baseURL])
    }

    @objc private func clearHistory() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "Everything except pinned items will be deleted from this Mac. This can't be undone."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn { store.clearUnpinned() }
    }

    private func showAlert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
