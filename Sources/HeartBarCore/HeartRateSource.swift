import Foundation

public enum SourceEvent: Equatable, Sendable {
    case state(ConnectionState)
    case reading(HeartRateReading)
}

@MainActor public protocol HeartRateSource: AnyObject {
    var onEvent: ((UUID, SourceEvent) -> Void)? { get set }
    func start(_ friend: Friend)
    func stop(_ friendID: UUID)
    func stopAll()
    func retry(_ friend: Friend)
}

@MainActor public protocol SourceClock: AnyObject {
    var now: Date { get }
    func sleep(seconds: TimeInterval) async throws
}

@MainActor public final class SystemSourceClock: SourceClock {
    public init() {}
    public var now: Date { Date() }
    public func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}

@MainActor public protocol WebSocketTransport: AnyObject {
    var failure: ConnectionIssue? { get }
    func open()
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func cancel()
}

@MainActor public final class URLSessionSocket: WebSocketTransport {
    private let session: URLSession
    private let task: URLSessionWebSocketTask

    public init(url: URL) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration)
        task = session.webSocketTask(with: url)
    }

    public var failure: ConnectionIssue? {
        switch (task.response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 401, 403: return .credentials
        case 404: return .subscription
        case 429, 500...599: return .service
        default: break
        }
        switch task.closeCode.rawValue {
        case 4401, 4403: return .credentials
        case 1008, 4404: return .subscription
        default: return nil
        }
    }

    public func open() { task.resume() }
    public func send(_ data: Data) async throws {
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }
    public func receive() async throws -> Data {
        switch try await task.receive() {
        case .data(let data): data
        case .string(let string): Data(string.utf8)
        @unknown default: Data()
        }
    }
    public func cancel() {
        task.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }
}

@MainActor public final class HypeRateSource: HeartRateSource {
    public var onEvent: ((UUID, SourceEvent) -> Void)?
    private let apiKey: String
    private let clock: any SourceClock
    private let makeSocket: (URL) -> any WebSocketTransport
    private var connections: [UUID: Connection] = [:]

    private final class Connection {
        let friend: Friend
        var worker: Task<Void, Never>?
        var heartbeat: Task<Void, Never>?
        var joinTimeout: Task<Void, Never>?
        var socket: (any WebSocketTransport)?
        var interruption: ConnectionIssue?
        var attempts = 0
        init(friend: Friend) { self.friend = friend }
    }

    public init(apiKey: String, clock: any SourceClock = SystemSourceClock(),
                makeSocket: @escaping (URL) -> any WebSocketTransport = { URLSessionSocket(url: $0) }) {
        self.apiKey = apiKey
        self.clock = clock
        self.makeSocket = makeSocket
    }

    public static func backoff(attempt: Int) -> Int { min(30, 1 << min(5, max(0, attempt - 1))) }

    public func start(_ friend: Friend) {
        guard connections[friend.id] == nil else { return }
        let connection = Connection(friend: friend)
        connections[friend.id] = connection
        connection.worker = Task { [weak self, weak connection] in
            guard let self, let connection else { return }
            await self.run(connection)
        }
    }

    public func stop(_ friendID: UUID) {
        guard let connection = connections.removeValue(forKey: friendID) else { return }
        connection.worker?.cancel()
        clearTransport(connection)
    }

    public func stopAll() { Array(connections.keys).forEach(stop) }
    public func retry(_ friend: Friend) { stop(friend.id); start(friend) }

    private func isCurrent(_ connection: Connection) -> Bool {
        connections[connection.friend.id] === connection && !Task.isCancelled
    }

    private func clearTransport(_ connection: Connection) {
        connection.heartbeat?.cancel()
        connection.joinTimeout?.cancel()
        connection.socket?.cancel()
        connection.heartbeat = nil
        connection.joinTimeout = nil
        connection.socket = nil
    }

    private func run(_ connection: Connection) async {
        let friend = connection.friend
        while isCurrent(connection) {
            onEvent?(friend.id, .state(.connecting))
            let socket = makeSocket(HypeRateProtocol.endpoint(deviceID: friend.hypeRateID, apiKey: apiKey))
            connection.socket = socket
            connection.interruption = nil
            socket.open()
            connection.joinTimeout = Task { [weak self, weak connection] in
                guard let self, let connection else { return }
                do { try await clock.sleep(seconds: 12) } catch { return }
                guard isCurrent(connection) else { return }
                connection.interruption = .timeout
                connection.socket?.cancel()
            }
            do {
                try await socket.send(HypeRateProtocol.join(deviceID: friend.hypeRateID))
                guard isCurrent(connection) else { return }
                connection.heartbeat = Task { [weak self, weak connection] in
                    guard let self, let connection else { return }
                    do {
                        while isCurrent(connection) {
                            try await clock.sleep(seconds: 15)
                            try Task.checkCancellation()
                            try await socket.send(HypeRateProtocol.heartbeat(at: clock.now))
                        }
                    } catch {
                        guard isCurrent(connection) else { return }
                        connection.interruption = .network
                        socket.cancel()
                    }
                }
                while isCurrent(connection) {
                    let data = try await socket.receive()
                    guard isCurrent(connection) else { return }
                    switch HypeRateProtocol.parse(data, expectedDeviceID: friend.hypeRateID) {
                    case .joined:
                        connection.joinTimeout?.cancel()
                        onEvent?(friend.id, .state(.waitingForReading))
                    case .reading(let bpm):
                        connection.joinTimeout?.cancel()
                        connection.attempts = 0
                        onEvent?(friend.id, .reading(HeartRateReading(bpm: bpm, receivedAt: clock.now)))
                    case .rejected(let issue): throw issue
                    case .ignored: break
                    }
                }
            } catch {
                guard isCurrent(connection) else { return }
                // Never expose an NSError description: it can contain the authenticated URL.
                let issue = connection.interruption ?? (error as? ConnectionIssue) ?? socket.failure ?? .network
                clearTransport(connection)
                if !issue.isRetryable {
                    onEvent?(friend.id, .state(.failed(issue)))
                    return
                }
                connection.attempts += 1
                let delay = Self.backoff(attempt: connection.attempts)
                onEvent?(friend.id, .state(.reconnecting(attempt: connection.attempts, delay: delay)))
                do { try await clock.sleep(seconds: TimeInterval(delay)) } catch { return }
            }
        }
    }
}

@MainActor public final class DemoHeartRateSource: HeartRateSource {
    public var onEvent: ((UUID, SourceEvent) -> Void)?
    private let clock: any SourceClock
    private var tasks: [UUID: Task<Void, Never>] = [:]

    public init(clock: any SourceClock = SystemSourceClock()) { self.clock = clock }

    public func start(_ friend: Friend) {
        guard tasks[friend.id] == nil else { return }
        let index = Friend.demoFriends.firstIndex(where: { $0.id == friend.id }) ?? 0
        tasks[friend.id] = Task { [weak self] in
            guard let self else { return }
            var tick = 0.0
            while !Task.isCancelled {
                let bpm = [72, 81, 65][index % 3] + Int((sin(tick / 4 + Double(index)) * 5).rounded())
                onEvent?(friend.id, .reading(HeartRateReading(bpm: bpm, receivedAt: clock.now)))
                tick += 1
                do { try await clock.sleep(seconds: 1) } catch { return }
            }
        }
    }

    public func stop(_ friendID: UUID) { tasks.removeValue(forKey: friendID)?.cancel() }
    public func stopAll() { Array(tasks.keys).forEach(stop) }
    public func retry(_ friend: Friend) { stop(friend.id); start(friend) }
}
