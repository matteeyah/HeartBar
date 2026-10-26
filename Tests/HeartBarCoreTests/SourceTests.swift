import Foundation
import Testing
@testable import HeartBarCore

@MainActor struct SourceTests {
    @Test func routesEachSocketAndSendsKeepalive() async {
        let clock = ManualClock()
        var sockets: [FakeSocket] = []
        var events: [(UUID, SourceEvent)] = []
        let source = HypeRateSource(apiKey: "test", clock: clock) { _ in
            let socket = FakeSocket(); sockets.append(socket); return socket
        }
        let friend = Friend(name: "Ana", hypeRateID: "abc")
        source.onEvent = { events.append(($0, $1)) }
        source.start(friend)
        defer { source.stopAll() }
        #expect(await waitUntil { sockets.count == 1 && sockets[0].receiving })
        sockets[0].push(#"{"event":"hr_update","topic":"hr:someone-else","payload":{"hr":99}}"#)
        sockets[0].push(#"{"event":"hr_update","topic":"hr:abc","payload":{"hr":72}}"#)
        #expect(await waitUntil { events.contains { $0.1 == .reading(HeartRateReading(bpm: 72, receivedAt: clock.now)) } })
        #expect(events.filter { if case .reading = $0.1 { return true }; return false }.map(\.0) == [friend.id])
        #expect(await waitUntil { clock.pendingDelays == [15] })
        clock.advance(15)
        #expect(await waitUntil { sockets[0].sent.count == 2 })
        #expect(sockets[0].sent.last == HypeRateProtocol.heartbeat(at: clock.now))
    }

    @Test func stopCancelsPendingReconnect() async {
        let clock = ManualClock()
        var sockets: [FakeSocket] = []
        var states: [ConnectionState] = []
        let source = HypeRateSource(apiKey: "test", clock: clock) { _ in
            let socket = FakeSocket(); sockets.append(socket); return socket
        }
        let friend = Friend(name: "Ana", hypeRateID: "abc")
        source.onEvent = { _, event in if case .state(let state) = event { states.append(state) } }
        source.start(friend)
        #expect(await waitUntil { sockets.count == 1 && sockets[0].receiving })
        sockets[0].fail()
        #expect(await waitUntil { states.contains(.reconnecting(attempt: 1, delay: 1)) })
        source.stop(friend.id)
        #expect(await waitUntil { clock.pendingCount == 0 })
        clock.advance(60)
        for _ in 0..<20 { await Task.yield() }
        #expect(sockets.count == 1)
        #expect(sockets[0].canceled)
    }

    @Test func transientFailureReconnectsAfterBackoff() async {
        let clock = ManualClock()
        var sockets: [FakeSocket] = []
        let source = HypeRateSource(apiKey: "test", clock: clock) { _ in
            let socket = FakeSocket(); sockets.append(socket); return socket
        }
        let friend = Friend(name: "Ana", hypeRateID: "abc")
        source.start(friend)
        defer { source.stopAll() }
        #expect(await waitUntil { sockets.count == 1 && sockets[0].receiving })
        sockets[0].fail()
        #expect(await waitUntil { clock.pendingDelays == [1] })
        clock.advance(1)
        #expect(await waitUntil { sockets.count == 2 && sockets[1].receiving })
        #expect(sockets[0].canceled)
    }

    @Test func deniedSubscriptionRequiresExplicitRetry() async {
        let clock = ManualClock()
        var sockets: [FakeSocket] = []
        var lastState: ConnectionState?
        let source = HypeRateSource(apiKey: "test", clock: clock) { _ in
            let socket = FakeSocket(); sockets.append(socket); return socket
        }
        let friend = Friend(name: "Ana", hypeRateID: "abc")
        source.onEvent = { _, event in if case .state(let state) = event { lastState = state } }
        source.start(friend)
        defer { source.stopAll() }
        #expect(await waitUntil { sockets.count == 1 && sockets[0].receiving })
        sockets[0].push(#"{"event":"phx_reply","topic":"hr:abc","ref":"1","payload":{"status":"error","response":{"reason":"denied"}}}"#)
        #expect(await waitUntil { lastState == .failed(.subscription) && clock.pendingCount == 0 })
        clock.advance(60)
        #expect(sockets.count == 1)
        source.retry(friend)
        #expect(await waitUntil { sockets.count == 2 })
    }

    @Test func joinTimeoutClosesHungSocket() async {
        let clock = ManualClock()
        let socket = FakeSocket()
        var lastState: ConnectionState?
        let source = HypeRateSource(apiKey: "test", clock: clock, makeSocket: { _ in socket })
        source.onEvent = { _, event in if case .state(let state) = event { lastState = state } }
        source.start(Friend(name: "Ana", hypeRateID: "abc"))
        defer { source.stopAll() }
        #expect(await waitUntil { clock.pendingDelays == [12, 15] })
        clock.advance(12)
        #expect(await waitUntil { lastState == .reconnecting(attempt: 1, delay: 1) })
        #expect(socket.canceled)
    }

    @Test func backoffIsExponentialAndCapped() {
        #expect((1...8).map(HypeRateSource.backoff) == [1, 2, 4, 8, 16, 30, 30, 30])
    }
}
