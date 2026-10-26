import AppKit
import SwiftUI
import HeartBarCore

@MainActor private final class PreviewPreferences: PreferencesRepository {
    var value = Preferences()
    func load() -> Preferences { value }
    func save(_ preferences: Preferences) { value = preferences }
}
@MainActor private final class PreviewCredentials: CredentialRepository {
    func load() -> String? { nil }
    func save(_ apiKey: String?) {}
}

// Compiled alongside the real app views. No real preferences or Keychain access.
@main enum VerifyUI {
    @MainActor static func main() async throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let repository = PreviewPreferences()
        repository.value.demoMode = true
        let store = AppStore(repository: repository, credentials: PreviewCredentials())
        store.start()
        defer { store.stop() }
        try await Task.sleep(for: .seconds(1.2))
        precondition(store.liveCount == 3, "Demo source must publish all participants")
        let firstTitle = store.menuBarTitle
        try await Task.sleep(for: .seconds(1.2))
        precondition(store.menuBarTitle != firstTitle, "Readings must change while all windows are hidden")

        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/previews")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            try await render(HeartBarPopoverView(store: store, openSettings: {}),
                             size: NSSize(width: 360, height: 480), appearance: appearance, to: output.appendingPathComponent("popover-\(name).png"))
        }
        try await render(ConnectionSettings(store: store), size: NSSize(width: 580, height: 500),
                         appearance: .aqua, to: output.appendingPathComponent("connection.png"))
        try await render(SettingsView(store: store), size: NSSize(width: 620, height: 580),
                         appearance: .aqua, to: output.appendingPathComponent("settings.png"))
        store.setDemoMode(false)
        try await render(HeartBarPopoverView(store: store, openSettings: {}),
                         size: NSSize(width: 360, height: 480), appearance: .aqua, to: output.appendingPathComponent("empty.png"))
        for (name, id) in [("Ana", "ana-id"), ("Sam", "sam-id"), ("Mika", "mika-id"), ("Robin", "robin-id")] {
            try store.saveFriend(name: name, hypeRateID: id)
        }
        try await render(FriendsSettings(store: store), size: NSSize(width: 580, height: 500),
                         appearance: .aqua, to: output.appendingPathComponent("friends.png"))
        print("PASS: demo updates while the popover is closed.")
        print("Rendered light/dark popover, empty state, and settings to build/previews.")
    }

    @MainActor private static func render<V: View>(_ view: V, size: NSSize, appearance: NSAppearance.Name, to url: URL) async throws {
        NSApp.appearance = NSAppearance(named: appearance)
        let hosting = NSHostingView(rootView: view
            .environment(\.colorScheme, appearance == .darkAqua ? .dark : .light)
            .background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        hosting.displayIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { fatalError("Cannot render preview") }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        window.orderOut(nil)
    }
}
