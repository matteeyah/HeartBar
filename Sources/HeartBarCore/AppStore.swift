import Combine
import Foundation

@MainActor public final class AppStore: ObservableObject {
    @Published public private(set) var preferences: Preferences
    @Published public private(set) var statuses: [UUID: ParticipantStatus] = [:]
    @Published public private(set) var now: Date
    @Published public private(set) var hasAPIKey = false
    @Published public var notice: String?

    private let repository: any PreferencesRepository
    private let credentials: any CredentialRepository
    private let clock: any SourceClock
    private let sourceFactory: (String) -> any HeartRateSource
    private var apiKey: String?
    private var source: (any HeartRateSource)?
    private var sourceGeneration = UUID()
    private var ticker: Task<Void, Never>?
    private var running = false
    private var sleeping = false

    public init(repository: any PreferencesRepository = UserDefaultsPreferences(),
                credentials: any CredentialRepository = KeychainCredentials(),
                clock: any SourceClock = SystemSourceClock(),
                sourceFactory: @escaping (String) -> any HeartRateSource = { HypeRateSource(apiKey: $0) }) {
        self.repository = repository
        self.credentials = credentials
        self.clock = clock
        self.sourceFactory = sourceFactory
        now = clock.now
        do { preferences = try repository.load() }
        catch {
            preferences = Preferences()
            notice = "Saved preferences could not be read. Add your friends again or restore your preferences backup."
        }
        do {
            apiKey = try credentials.load()
            hasAPIKey = !(apiKey ?? "").isEmpty
        } catch {
            notice = "HeartBar could not read its API key from Keychain. Open Connection settings to try again."
        }
    }

    public var friends: [Friend] { preferences.friends }
    public var favorites: [Friend] { friends.filter(\.isFavorite) }
    public var liveCount: Int { friends.filter { status(for: $0).isLive(at: now) }.count }
    public var menuBarTitle: String {
        guard !favorites.isEmpty else { return "♥ HeartBar" }
        return "♥ " + favorites.prefix(3).map { friend in
            let status = status(for: friend)
            let bpm = status.isLive(at: now) ? String(status.reading!.bpm) : "—"
            return "\(friend.compactName) \(bpm)"
        }.joined(separator: " · ")
    }

    public func status(for friend: Friend) -> ParticipantStatus { statuses[friend.id] ?? ParticipantStatus() }

    public func start() {
        guard !running else { return }
        running = true
        rebuildSource()
        startTicker()
    }

    public func stop() {
        running = false
        sourceGeneration = UUID()
        source?.onEvent = nil
        source?.stopAll()
        source = nil
        ticker?.cancel()
        ticker = nil
    }

    public func tick() { now = clock.now }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self, clock] in
            while !Task.isCancelled {
                do { try await clock.sleep(seconds: 1) } catch { return }
                self?.tick()
            }
        }
    }

    public func sleep() {
        sleeping = true
        sourceGeneration = UUID()
        source?.onEvent = nil
        source?.stopAll()
        source = nil
        ticker?.cancel()
        ticker = nil
        for friend in friends { statuses[friend.id, default: ParticipantStatus()].connection = .sleeping }
    }

    public func wake() {
        sleeping = false
        tick()
        if running { rebuildSource(); startTicker() }
    }

    public func setAPIKey(_ key: String?) throws {
        let cleaned = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newKey = cleaned?.isEmpty == false ? cleaned : nil
        // Only replace active credentials after the Keychain write succeeds.
        try credentials.save(newKey)
        apiKey = newKey
        hasAPIKey = newKey != nil
        rebuildSource()
    }

    @discardableResult public func saveFriend(id: UUID? = nil, name: String, hypeRateID: String) throws -> Friend {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let deviceID = hypeRateID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FriendValidationError.nameRequired }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard !deviceID.isEmpty, deviceID.count <= 128,
              deviceID.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { throw FriendValidationError.invalidID }
        guard !preferences.friends.contains(where: { $0.id != id && $0.hypeRateID.lowercased() == deviceID.lowercased() })
        else { throw FriendValidationError.duplicateID }

        let previous = preferences.friends.first { $0.id == id }
        let friend = Friend(id: previous?.id ?? UUID(), name: String(name.prefix(80)), hypeRateID: deviceID,
                            isFavorite: previous?.isFavorite ?? (preferences.friends.count < 3))
        if let index = preferences.friends.firstIndex(where: { $0.id == friend.id }) {
            preferences.friends[index] = friend
        } else { preferences.friends.append(friend) }
        persist()
        if previous?.hypeRateID != friend.hypeRateID {
            source?.stop(friend.id)
            statuses[friend.id] = initialStatus()
            source?.start(friend)
        }
        return friend
    }

    public func removeFriend(_ friend: Friend) {
        preferences.friends.removeAll { $0.id == friend.id }
        source?.stop(friend.id)
        statuses.removeValue(forKey: friend.id)
        persist()
    }

    public func moveFriend(_ friend: Friend, by offset: Int) {
        guard let from = preferences.friends.firstIndex(where: { $0.id == friend.id }) else { return }
        let to = from + offset
        guard preferences.friends.indices.contains(to) else { return }
        preferences.friends.swapAt(from, to)
        persist()
    }

    public func toggleFavorite(_ friend: Friend) throws {
        guard let index = preferences.friends.firstIndex(where: { $0.id == friend.id }) else { return }
        let selected = preferences.friends[index].isFavorite
        let count = preferences.friends.filter(\.isFavorite).count
        guard selected || count < 3 else { throw FriendValidationError.favoriteLimit }
        preferences.friends[index].isFavorite.toggle()
        persist()
    }

    public func retry(_ friend: Friend) {
        guard running, !sleeping else { return }
        guard source != nil else { rebuildSource(); return }
        statuses[friend.id, default: ParticipantStatus()].connection = .connecting
        source?.retry(friend)
    }

    public func retryAll() {
        do {
            apiKey = try credentials.load()
            hasAPIKey = !(apiKey ?? "").isEmpty
        } catch {
            notice = "HeartBar could not read its API key from Keychain. Unlock your login keychain and try again."
            return
        }
        rebuildSource()
    }

    private func initialStatus() -> ParticipantStatus {
        ParticipantStatus(connection: sleeping ? .sleeping : (hasAPIKey ? .connecting : .needsAPIKey))
    }

    private func rebuildSource() {
        sourceGeneration = UUID()
        source?.onEvent = nil
        source?.stopAll()
        source = nil
        statuses = Dictionary(uniqueKeysWithValues: friends.map { ($0.id, initialStatus()) })
        guard running, !sleeping, let apiKey, !apiKey.isEmpty else { return }
        let generation = sourceGeneration
        let source = sourceFactory(apiKey)
        source.onEvent = { [weak self] id, event in
            guard let self, self.sourceGeneration == generation,
                  self.friends.contains(where: { $0.id == id }) else { return }
            switch event {
            case .state(let state): self.statuses[id, default: ParticipantStatus()].connection = state
            case .reading(let reading):
                self.statuses[id] = ParticipantStatus(connection: .connected, reading: reading)
                self.now = self.clock.now
            }
        }
        self.source = source
        friends.forEach(source.start)
    }

    private func persist() {
        do { try repository.save(preferences) }
        catch { notice = "Your changes could not be saved. Please try again." }
    }
}
