import AppKit
import SwiftUI
import HeartBarCore

@MainActor private final class PreviewPreferences: PreferencesRepository {
    var value = Preferences()
    func load() -> Preferences { value }
    func save(_ preferences: Preferences) { value = preferences }
}
@MainActor private final class PreviewCredentials: CredentialRepository {
    private var value: String?
    init(value: String? = nil) { self.value = value }
    func load() -> String? { value }
    func save(_ apiKey: String?) { value = apiKey }
}

// Screenshot-only sample data source; this script is excluded from app targets.
@MainActor private final class PreviewHeartRateSource: HeartRateSource {
    var onEvent: ((UUID, SourceEvent) -> Void)?
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func start(_ friend: Friend) {
        guard tasks[friend.id] == nil else { return }
        let baseline = ["ana-id": 72, "sam-id": 81, "mika-id": 65][friend.hypeRateID] ?? 70
        tasks[friend.id] = Task { [weak self] in
            var tick = 0.0
            while !Task.isCancelled {
                let bpm = baseline + Int((sin(tick / 4) * 5).rounded())
                self?.onEvent?(friend.id, .reading(HeartRateReading(bpm: bpm, receivedAt: Date())))
                tick += 1
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    func stop(_ friendID: UUID) { tasks.removeValue(forKey: friendID)?.cancel() }
    func stopAll() { Array(tasks.keys).forEach(stop) }
    func retry(_ friend: Friend) { stop(friend.id); start(friend) }
}

// Compiled alongside the real app views. No real preferences or Keychain access.
@main enum VerifyUI {
    @MainActor static func main() async throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let repository = PreviewPreferences()
        let store = AppStore(repository: repository, credentials: PreviewCredentials(value: "preview-only")) { _ in
            PreviewHeartRateSource()
        }
        for (name, id) in [("Ana", "ana-id"), ("Sam", "sam-id"), ("Mika", "mika-id")] {
            try store.saveFriend(name: name, hypeRateID: id)
        }
        store.start()
        defer { store.stop() }
        try await Task.sleep(for: .seconds(1.2))
        precondition(store.liveCount == 3, "Preview source must publish all participants")
        let firstTitle = store.menuBarTitle
        try await Task.sleep(for: .seconds(1.2))
        precondition(store.menuBarTitle != firstTitle, "Readings must change while all windows are hidden")

        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/previews")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            try await render(HeartBarPopoverView(store: store, openSettings: {}),
                             size: NSSize(width: 360, height: 480), appearance: appearance, to: output.appendingPathComponent("popover-\(name).png"))
        }
        try store.setAPIKey(nil)
        try await render(ConnectionSettings(store: store), size: NSSize(width: 580, height: 500),
                         appearance: .aqua, to: output.appendingPathComponent("connection.png"))
        try await render(SettingsView(store: store), size: NSSize(width: 620, height: 580),
                         appearance: .aqua, to: output.appendingPathComponent("settings.png"))
        let emptyStore = AppStore(repository: PreviewPreferences(), credentials: PreviewCredentials())
        try await render(HeartBarPopoverView(store: emptyStore, openSettings: {}),
                         size: NSSize(width: 360, height: 480), appearance: .aqua, to: output.appendingPathComponent("empty.png"))
        try store.saveFriend(name: "Robin", hypeRateID: "robin-id")
        try await render(FriendsSettings(store: store), size: NSSize(width: 580, height: 500),
                         appearance: .aqua, to: output.appendingPathComponent("friends.png"))
        print("PASS: injected preview readings update while the popover is closed.")
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
