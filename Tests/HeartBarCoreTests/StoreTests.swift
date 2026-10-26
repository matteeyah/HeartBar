import Foundation
import Testing
@testable import HeartBarCore

@MainActor struct StoreTests {
    private func makeStore(repository: MemoryPreferences = MemoryPreferences(), credentials: MemoryCredentials = MemoryCredentials(), clock: ManualClock = ManualClock(), source: RecordingSource = RecordingSource()) -> AppStore {
        AppStore(repository: repository, credentials: credentials, clock: clock, sourceFactory: { _, _ in source })
    }

    @Test func firstThreeFriendsAreFavorites() throws {
        let store = makeStore()
        for index in 1...4 { try store.saveFriend(name: "Friend \(index)", hypeRateID: "id-\(index)") }
        #expect(store.favorites.map(\.hypeRateID) == ["id-1", "id-2", "id-3"])
        #expect(throws: FriendValidationError.favoriteLimit) { try store.toggleFavorite(store.friends[3]) }
    }

    @Test func validatesDuplicateIDsAndAllowsNameEdits() throws {
        let store = makeStore()
        let friend = try store.saveFriend(name: " Ana ", hypeRateID: "ABC")
        #expect(throws: FriendValidationError.duplicateID) { try store.saveFriend(name: "Sam", hypeRateID: " abc ") }
        try store.saveFriend(id: friend.id, name: "Anabelle", hypeRateID: "ABC")
        #expect(store.friends.first?.name == "Anabelle")
    }

    @Test func editIDRestartsOnlyThatFriend() throws {
        let source = RecordingSource()
        let store = makeStore(source: source)
        let ana = try store.saveFriend(name: "Ana", hypeRateID: "ana")
        let sam = try store.saveFriend(name: "Sam", hypeRateID: "sam")
        store.start()
        defer { store.stop() }
        try store.saveFriend(id: ana.id, name: "Ana", hypeRateID: "ana-new")
        #expect(source.stopped == [ana.id])
        #expect(source.started.last?.hypeRateID == "ana-new")
        #expect(source.started.filter { $0.id == sam.id }.count == 1)
    }

    @Test func removalStopsConnectionAndRejectsLateUpdates() throws {
        let source = RecordingSource()
        let store = makeStore(source: source)
        let friend = try store.saveFriend(name: "Ana", hypeRateID: "abc")
        store.start()
        defer { store.stop() }
        store.removeFriend(friend)
        source.onEvent?(friend.id, .reading(HeartRateReading(bpm: 72, receivedAt: Date())))
        #expect(source.stopped == [friend.id])
        #expect(store.statuses[friend.id] == nil)
    }

    @Test func routesParticipantsAndUpdatesMenuWhenHidden() throws {
        let source = RecordingSource()
        let clock = ManualClock()
        let store = makeStore(clock: clock, source: source)
        let ana = try store.saveFriend(name: "Ana", hypeRateID: "ana")
        let sam = try store.saveFriend(name: "Sam", hypeRateID: "sam")
        store.start()
        defer { store.stop() }
        store.updateDisplay { $0.sidebarVisible = false }
        source.onEvent?(sam.id, .reading(HeartRateReading(bpm: 81, receivedAt: clock.now)))
        #expect(store.menuBarTitle == "♥ Ana — · Sam 81")
        #expect(store.status(for: ana).reading == nil)
        clock.advance(15)
        store.tick()
        #expect(store.menuBarTitle == "♥ Ana — · Sam —")
    }

    @Test func credentialsReplaceSourceAndDiscardOldCallbacks() throws {
        let repository = MemoryPreferences()
        let credentials = MemoryCredentials()
        var sources: [RecordingSource] = []
        var keys: [String?] = []
        let store = AppStore(repository: repository, credentials: credentials, clock: ManualClock()) { _, key in
            let source = RecordingSource(); sources.append(source); keys.append(key); return source
        }
        let friend = try store.saveFriend(name: "Ana", hypeRateID: "ana")
        store.start()
        defer { store.stop() }
        let oldCallback = sources[0].onEvent
        try store.setAPIKey("new-key")
        oldCallback?(friend.id, .reading(HeartRateReading(bpm: 99, receivedAt: Date())))
        #expect(sources[0].stopAllCount == 1)
        #expect(keys == ["test-key", "new-key"])
        #expect(store.status(for: friend).reading == nil)
        #expect(credentials.value == "new-key")
    }

    @Test func failedCredentialWriteKeepsCurrentConnection() throws {
        let credentials = MemoryCredentials()
        let source = RecordingSource()
        let store = makeStore(credentials: credentials, source: source)
        store.start()
        defer { store.stop() }
        credentials.rejectWrites = true
        #expect(throws: ConnectionIssue.credentials) { try store.setAPIKey("new-key") }
        #expect(source.stopAllCount == 0)
    }

    @Test func removingKeyDisconnectsImmediately() throws {
        let source = RecordingSource()
        let store = makeStore(source: source)
        let friend = try store.saveFriend(name: "Ana", hypeRateID: "ana")
        store.start()
        defer { store.stop() }
        try store.setAPIKey(nil)
        #expect(source.stopAllCount == 1)
        #expect(store.status(for: friend).connection == .needsAPIKey)
    }

    @Test func demoPreservesRealFriends() throws {
        let store = makeStore()
        let friend = try store.saveFriend(name: "Real friend", hypeRateID: "real")
        store.setDemoMode(true)
        #expect(store.friends == Friend.demoFriends)
        #expect(store.menuBarTitle.hasPrefix("♥ Demo"))
        store.setDemoMode(false)
        #expect(store.friends == [friend])
    }

    @Test func sleepStopsAndWakeResumes() throws {
        var sources: [RecordingSource] = []
        let store = AppStore(repository: MemoryPreferences(), credentials: MemoryCredentials(), clock: ManualClock()) { _, _ in
            let source = RecordingSource(); sources.append(source); return source
        }
        let friend = try store.saveFriend(name: "Ana", hypeRateID: "abc")
        store.start()
        defer { store.stop() }
        store.sleep()
        #expect(sources[0].stopAllCount == 1)
        #expect(store.status(for: friend).connection == .sleeping)
        store.wake()
        #expect(sources.count == 2)
        #expect(sources[1].started == [friend])
    }

    @Test func persistsReorderingAndDisplayPreferences() throws {
        let repository = MemoryPreferences()
        let store = makeStore(repository: repository)
        let first = try store.saveFriend(name: "Ana", hypeRateID: "ana")
        let second = try store.saveFriend(name: "Sam", hypeRateID: "sam")
        store.moveFriend(second, by: -1)
        store.updateDisplay { $0.edge = .left; $0.screenID = 42; $0.topOffset = 100; $0.sidebarVisible = false }
        let restored = makeStore(repository: repository)
        #expect(restored.friends == [second, first])
        #expect(restored.preferences.display == store.preferences.display)
        #expect(restored.statuses.isEmpty)
    }

    @Test func userDefaultsRoundTripStoresOnlyPreferences() throws {
        let suite = "com.heartbar.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = UserDefaultsPreferences(defaults: defaults)
        var preferences = Preferences()
        preferences.friends = [Friend(name: "Ana", hypeRateID: "abc", isFavorite: true)]
        preferences.demoMode = true
        preferences.display.edge = .left
        try repository.save(preferences)
        #expect(try repository.load() == preferences)
        let encoded = String(decoding: try #require(defaults.data(forKey: "HeartBar.preferences.v1")), as: UTF8.self)
        #expect(!encoded.contains("apiKey"))
        #expect(!encoded.contains("reading"))
    }
}
