import Foundation
import Testing
@testable import HeartBarCore

struct ProtocolTests {
    @Test func parsesAndRoutesReading() {
        let message = Data(#"{"event":"hr_update","topic":"hr:abc123","payload":{"hr":75},"ref":null}"#.utf8)
        #expect(HypeRateProtocol.parse(message, expectedDeviceID: "abc123") == .reading(75))
        #expect(HypeRateProtocol.parse(message, expectedDeviceID: "someone-else") == .ignored)
    }

    @Test(arguments: ["0", "-1", "301", "72.5", "true", "null", "\"72\""])
    func rejectsInvalidReadings(value: String) {
        let data = Data("{\"event\":\"hr_update\",\"topic\":\"hr:abc\",\"payload\":{\"hr\":\(value)}}".utf8)
        #expect(HypeRateProtocol.parse(data, expectedDeviceID: "abc") == .ignored)
    }

    @Test func ignoresMalformedMessages() {
        #expect(HypeRateProtocol.parse(Data("not json".utf8), expectedDeviceID: "abc") == .ignored)
    }

    @Test func handlesJoinAndSubscriptionErrors() {
        let joined = Data(#"{"event":"phx_reply","topic":"hr:abc","ref":"1","payload":{"status":"ok"}}"#.utf8)
        let rejected = Data(#"{"event":"phx_reply","topic":"hr:abc","ref":"1","payload":{"status":"error","response":{"reason":"device not found"}}}"#.utf8)
        let unauthorized = Data(#"{"event":"phx_reply","topic":"hr:abc","ref":"1","payload":{"status":"error","response":{"reason":"invalid token"}}}"#.utf8)
        #expect(HypeRateProtocol.parse(joined, expectedDeviceID: "abc") == .joined)
        #expect(HypeRateProtocol.parse(rejected, expectedDeviceID: "abc") == .rejected(.subscription))
        #expect(HypeRateProtocol.parse(unauthorized, expectedDeviceID: "abc") == .rejected(.credentials))
    }

    @Test func heartbeatReplyIsNotAJoin() {
        let data = Data(#"{"event":"phx_reply","topic":"phoenix","ref":"2","payload":{"status":"ok"}}"#.utf8)
        #expect(HypeRateProtocol.parse(data, expectedDeviceID: "abc") == .ignored)
    }

    @Test func endpointEncodesCredentials() throws {
        let url = HypeRateProtocol.endpoint(deviceID: "abc-123", apiKey: "test&value=?+")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "wss")
        #expect(components.host == "app.hyperate.io")
        #expect(components.path == "/ws/abc-123")
        #expect(components.queryItems == [URLQueryItem(name: "token", value: "test&value=?+")])
    }

    @Test func outboundProtocolMatchesReference() throws {
        let join = try #require(JSONSerialization.jsonObject(with: HypeRateProtocol.join(deviceID: "abc")) as? [String: Any])
        let ping = try #require(JSONSerialization.jsonObject(with: HypeRateProtocol.heartbeat(at: Date(timeIntervalSince1970: 123))) as? [String: Any])
        #expect(join["topic"] as? String == "hr:abc")
        #expect(join["event"] as? String == "phx_join")
        #expect(ping["event"] as? String == "ping")
        #expect((ping["payload"] as? [String: Int])?["timestamp"] == 123_000)
    }
}

struct FreshnessTests {
    private let date = Date(timeIntervalSince1970: 100)
    @Test func expiresAtFifteenSeconds() {
        let status = ParticipantStatus(connection: .connected, reading: HeartRateReading(bpm: 72, receivedAt: date))
        #expect(status.isLive(at: date.addingTimeInterval(14.99)))
        #expect(!status.isLive(at: date.addingTimeInterval(15)))
    }

    @Test func disconnectImmediatelyInvalidatesFreshReading() {
        let status = ParticipantStatus(connection: .reconnecting(attempt: 1, delay: 1), reading: HeartRateReading(bpm: 72, receivedAt: date))
        #expect(!status.isLive(at: date))
    }

    @Test func joinWithoutNewReadingIsNotLive() {
        let status = ParticipantStatus(connection: .waitingForReading, reading: HeartRateReading(bpm: 72, receivedAt: date))
        #expect(!status.isLive(at: date))
    }
}
