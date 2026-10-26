import Foundation
import CoreFoundation

public enum HypeRateMessage: Equatable, Sendable {
    case reading(Int), joined, rejected(ConnectionIssue), ignored
}

public enum HypeRateProtocol {
    public static func endpoint(deviceID: String, apiKey: String) -> URL {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = "app.hyperate.io"
        components.path = "/ws/\(deviceID)"
        components.queryItems = [URLQueryItem(name: "token", value: apiKey)]
        return components.url!
    }

    public static func join(deviceID: String) -> Data {
        encode(["topic": "hr:\(deviceID)", "event": "phx_join", "payload": [:], "ref": "1"])
    }

    public static func heartbeat(at date: Date) -> Data {
        encode(["event": "ping", "payload": ["timestamp": Int64(date.timeIntervalSince1970 * 1000)]])
    }

    public static func parse(_ data: Data, expectedDeviceID: String) -> HypeRateMessage {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["event"] as? String,
              let topic = object["topic"] as? String,
              topic == "hr:\(expectedDeviceID)" else { return .ignored }
        let payload = object["payload"] as? [String: Any] ?? [:]
        switch event {
        case "hr_update":
            guard let number = payload["hr"] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite,
                  number.doubleValue.rounded() == number.doubleValue,
                  (1...300).contains(number.intValue) else { return .ignored }
            return .reading(number.intValue)
        case "phx_reply":
            // A heartbeat or leave acknowledgment must not be treated as a join.
            guard String(describing: object["ref"] ?? "") == "1" else { return .ignored }
            if payload["status"] as? String == "ok" { return .joined }
            if payload["status"] as? String == "error" {
                let response = payload["response"] as? [String: Any]
                let reason = (response?["reason"] as? String ?? payload["reason"] as? String ?? "").lowercased()
                let credentialTerms = ["token", "api key", "unauthorized", "authentication", "credential"]
                return .rejected(credentialTerms.contains(where: reason.contains) ? .credentials : .subscription)
            }
            return .ignored
        case "phx_error", "phx_close": return .rejected(.service)
        default: return .ignored
        }
    }

    private static func encode(_ object: [String: Any]) -> Data {
        // All outbound values are known JSON primitives, never raw user JSON.
        try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
