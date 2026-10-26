import Foundation
@testable import HeartBarCore

@MainActor final class MemoryPreferences: PreferencesRepository {
    var value = Preferences()
    func load() -> Preferences { value }
    func save(_ preferences: Preferences) { value = preferences }
}

@MainActor final class MemoryCredentials: CredentialRepository {
    var value: String? = "test-key"
    var rejectWrites = false
    func load() -> String? { value }
    func save(_ apiKey: String?) throws {
        if rejectWrites { throw ConnectionIssue.credentials }
        value = apiKey
    }
}

@MainActor final class RecordingSource: HeartRateSource {
    var onEvent: ((UUID, SourceEvent) -> Void)?
    var started: [Friend] = []
    var stopped: [UUID] = []
    var stopAllCount = 0
    func start(_ friend: Friend) { started.append(friend) }
    func stop(_ friendID: UUID) { stopped.append(friendID) }
    func stopAll() { stopAllCount += 1 }
    func retry(_ friend: Friend) { stop(friend.id); start(friend) }
}

@MainActor final class ManualClock: SourceClock {
    var now = Date(timeIntervalSince1970: 1_000)
    private struct Sleeper {
        let deadline: Date
        let continuation: CheckedContinuation<Void, Error>
    }
    private var sleepers: [UUID: Sleeper] = [:]
    var pendingCount: Int { sleepers.count }
    var pendingDelays: [TimeInterval] { sleepers.values.map { $0.deadline.timeIntervalSince(now) }.sorted() }

    func sleep(seconds: TimeInterval) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { sleepers[id] = Sleeper(deadline: now.addingTimeInterval(seconds), continuation: continuation) }
            }
        } onCancel: {
            Task { @MainActor in self.sleepers.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError()) }
        }
    }

    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
        let ready = sleepers.filter { $0.value.deadline <= now }
        for (id, sleeper) in ready {
            sleepers.removeValue(forKey: id)
            sleeper.continuation.resume()
        }
    }
}

@MainActor final class FakeSocket: WebSocketTransport {
    var failure: ConnectionIssue?
    var sent: [Data] = []
    var canceled = false
    private var buffered: [Data] = []
    private var receiver: CheckedContinuation<Data, Error>?
    var receiving: Bool { receiver != nil }
    func open() {}
    func send(_ data: Data) throws {
        if canceled { throw CancellationError() }
        sent.append(data)
    }
    func receive() async throws -> Data {
        if canceled { throw CancellationError() }
        if !buffered.isEmpty { return buffered.removeFirst() }
        return try await withCheckedThrowingContinuation { receiver = $0 }
    }
    func push(_ json: String) {
        let data = Data(json.utf8)
        if let receiver { self.receiver = nil; receiver.resume(returning: data) }
        else { buffered.append(data) }
    }
    func fail() {
        receiver?.resume(throwing: ConnectionIssue.network)
        receiver = nil
    }
    func cancel() {
        canceled = true
        receiver?.resume(throwing: CancellationError())
        receiver = nil
    }
}

@MainActor func waitUntil(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<1_000 {
        if condition() { return true }
        await Task.yield()
    }
    return condition()
}
