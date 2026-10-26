import Foundation

public struct Friend: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var hypeRateID: String
    public var isFavorite: Bool

    public init(id: UUID = UUID(), name: String, hypeRateID: String, isFavorite: Bool = false) {
        self.id = id
        self.name = name
        self.hypeRateID = hypeRateID
        self.isFavorite = isFavorite
    }

    public var compactName: String {
        let first = name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? name
        return first.count > 9 ? String(first.prefix(8)) + "…" : first
    }

    public static let demoFriends = [
        Friend(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Ana", hypeRateID: "demo-ana", isFavorite: true),
        Friend(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Sam", hypeRateID: "demo-sam", isFavorite: true),
        Friend(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "Mika", hypeRateID: "demo-mika", isFavorite: true)
    ]
}

public struct HeartRateReading: Equatable, Sendable {
    public let bpm: Int
    public let receivedAt: Date

    public init(bpm: Int, receivedAt: Date) {
        self.bpm = bpm
        self.receivedAt = receivedAt
    }

    public func isFresh(at now: Date) -> Bool {
        let age = now.timeIntervalSince(receivedAt)
        return age >= 0 && age < 15
    }

    public func ageDescription(at now: Date) -> String {
        let age = max(0, Int(now.timeIntervalSince(receivedAt)))
        if age < 2 { return "just now" }
        if age < 60 { return "\(age)s ago" }
        if age < 3600 { return "\(age / 60)m ago" }
        return "\(age / 3600)h ago"
    }
}

public enum ConnectionIssue: String, Equatable, Sendable, Error {
    case credentials, subscription, network, timeout, service

    public var message: String {
        switch self {
        case .credentials: "API key rejected. Update it in Connection settings, then retry."
        case .subscription: "Cannot subscribe. Check this HypeRate ID and your API access, then retry."
        case .network: "Connection interrupted. Retrying automatically."
        case .timeout: "HypeRate did not respond. Retrying automatically."
        case .service: "HypeRate is unavailable. Retrying automatically."
        }
    }

    public var isRetryable: Bool { self != .credentials && self != .subscription }
}

public enum ConnectionState: Equatable, Sendable {
    case idle, needsAPIKey, connecting, waitingForReading, connected, sleeping
    case reconnecting(attempt: Int, delay: Int)
    case failed(ConnectionIssue)

    public var label: String {
        switch self {
        case .idle: "Not connected"
        case .needsAPIKey: "API key needed"
        case .connecting: "Connecting"
        case .waitingForReading, .connected: "Waiting for a reading"
        case .sleeping: "Paused while Mac sleeps"
        case .reconnecting(_, let delay): "Reconnecting in \(delay)s"
        case .failed(let issue): issue == .credentials ? "API key rejected" : "Subscription failed"
        }
    }
}

public struct ParticipantStatus: Equatable, Sendable {
    public var connection: ConnectionState = .idle
    public var reading: HeartRateReading?

    public init(connection: ConnectionState = .idle, reading: HeartRateReading? = nil) {
        self.connection = connection
        self.reading = reading
    }

    public func isLive(at now: Date) -> Bool {
        connection == .connected && reading?.isFresh(at: now) == true
    }

    public func label(at now: Date, demo: Bool) -> String {
        if isLive(at: now) { return demo ? "Simulated" : "Live" }
        if connection == .connected, reading != nil { return "Stale · waiting for updates" }
        return connection.label
    }
}

public enum SidebarEdge: String, Codable, CaseIterable, Sendable {
    case left, right
}

public struct DisplayPreferences: Codable, Equatable, Sendable {
    public var edge: SidebarEdge = .right
    public var screenID: UInt32?
    public var topOffset: Double = 24
    public var height: Double = 600
    public var sidebarVisible: Bool = true
    public init() {}
}

public struct Preferences: Codable, Equatable, Sendable {
    public var friends: [Friend] = []
    public var demoMode: Bool = false
    public var demoFavorites: [UUID] = Friend.demoFriends.map(\.id)
    public var display = DisplayPreferences()
    public init() {}

    public mutating func sanitize() {
        var ids = Set<UUID>()
        var deviceIDs = Set<String>()
        var favoriteCount = 0
        friends = friends.filter { friend in
            ids.insert(friend.id).inserted && deviceIDs.insert(friend.hypeRateID.lowercased()).inserted
        }.map { friend in
            var friend = friend
            if friend.isFavorite {
                favoriteCount += 1
                friend.isFavorite = favoriteCount <= 3
            }
            return friend
        }
        demoFavorites = Array(Set(demoFavorites).intersection(Friend.demoFriends.map(\.id))).sorted { $0.uuidString < $1.uuidString }
        display.height = display.height.isFinite ? max(320, min(1200, display.height)) : 600
        display.topOffset = display.topOffset.isFinite ? max(0, display.topOffset) : 24
    }
}

public enum FriendValidationError: LocalizedError, Equatable {
    case nameRequired, invalidID, duplicateID, favoriteLimit

    public var errorDescription: String? {
        switch self {
        case .nameRequired: "Give your friend a name."
        case .invalidID: "Enter a HypeRate ID using letters, numbers, hyphens, or underscores."
        case .duplicateID: "A friend with that HypeRate ID is already saved."
        case .favoriteLimit: "You can show up to three favorites in the menu bar. Unstar someone first."
        }
    }
}
