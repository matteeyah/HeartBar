import AppKit
import Combine
import SwiftUI
import HeartBarCore

#if !HEARTBAR_VERIFY
@main
enum HeartBarApplication {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
#endif

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: AppStore!
    private var sidebar: SidebarController!
    private var settings: SettingsController!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var observation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        store = AppStore()
        settings = SettingsController(store: store)
        sidebar = SidebarController(store: store, openSettings: { [weak self] in self?.showSettings() })

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 480)
        popover.contentViewController = NSHostingController(rootView: HeartBarPanelView(
            store: store, surface: .popover, openSettings: { [weak self] in self?.showSettings() }
        ))
        observation = store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        store.start()
        refresh()
    }

    private func refresh() {
        statusItem.button?.title = store.menuBarTitle
        statusItem.button?.toolTip = store.preferences.demoMode ? "HeartBar · Demo data" : "HeartBar · \(store.liveCount) of \(store.friends.count) live"
        statusItem.button?.setAccessibilityLabel(store.menuBarTitle.replacingOccurrences(of: "♥", with: "HeartBar"))
        sidebar.apply(store.preferences.display)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }

    private func showSettings() {
        popover.performClose(nil)
        settings.show()
    }

    @objc private func openSettingsFromMenu(_ sender: Any?) { showSettings() }

    private func installMainMenu() {
        // An AppKit-managed app needs an Edit menu for standard text-field shortcuts.
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "HeartBar")
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu(_:)), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit HeartBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApp.mainMenu = menu
    }

    @objc private func willSleep() { store.sleep() }
    @objc private func didWake() { store.wake() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        store.updateDisplay { $0.sidebarVisible = true }
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}

@MainActor final class PassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor final class SidebarController: NSObject, NSWindowDelegate {
    private let store: AppStore
    let panel: PassivePanel
    private var applied: DisplayPreferences?
    private var adjusting = false

    init(store: AppStore, openSettings: @escaping () -> Void) {
        self.store = store
        panel = PassivePanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 600),
                             styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .resizable],
                             backing: .buffered, defer: false)
        super.init()
        panel.title = "HeartBar"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 320, height: 320)
        panel.maxSize = NSSize(width: 320, height: 1200)
        panel.backgroundColor = .windowBackgroundColor
        panel.contentView = FirstMouseHostingView(rootView: HeartBarPanelView(store: store, surface: .sidebar, openSettings: openSettings))
        panel.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func apply(_ display: DisplayPreferences, force: Bool = false) {
        guard force || applied != display else { return }
        applied = display
        guard let screen = ScreenChoice.screen(id: display.screenID) else { return }
        let available = screen.visibleFrame
        let height = min(max(320, display.height), available.height - 16)
        let x = display.edge == .right ? available.maxX - 328 : available.minX + 8
        let y = max(available.minY + 8, available.maxY - height - max(8, display.topOffset))
        adjusting = true
        panel.setFrame(NSRect(x: x, y: y, width: 320, height: height), display: true)
        adjusting = false
        if display.sidebarVisible { panel.orderFrontRegardless() }
        else { panel.orderOut(nil) }
    }

    @objc private func screensChanged() { apply(store.preferences.display, force: true) }

    func windowDidMove(_ notification: Notification) { rememberPosition() }
    func windowDidEndLiveResize(_ notification: Notification) { rememberPosition() }

    private func rememberPosition() {
        guard !adjusting, let screen = panel.screen else { return }
        var next = store.preferences.display
        next.screenID = ScreenChoice.identifier(screen)
        next.edge = panel.frame.midX < screen.visibleFrame.midX ? .left : .right
        next.topOffset = max(8, screen.visibleFrame.maxY - panel.frame.maxY)
        next.height = panel.frame.height
        // Don't reposition while the user drags. Restore the chosen edge next launch.
        applied = next
        store.updateDisplay { $0 = next }
    }
}

enum ScreenChoice {
    @MainActor static func identifier(_ screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
    @MainActor static func screen(id: UInt32?) -> NSScreen? {
        NSScreen.screens.first(where: { identifier($0) == id }) ?? NSScreen.screens.first
    }
}

@MainActor final class SettingsController {
    private let window: NSWindow
    init(store: AppStore) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 580),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "HeartBar Settings"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView(store: store))
        window.center()
    }
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
