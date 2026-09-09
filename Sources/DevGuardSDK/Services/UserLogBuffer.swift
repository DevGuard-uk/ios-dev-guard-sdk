import Foundation

/// Local ring buffer for integrator `DevGuard.setUserLog` steps (User Journey).
final class UserLogBuffer {
    private let storage: SecureStorageService
    private let maxEvents = 200
    private let stringMax = 80
    private let extrasJsonMax = 400
    private let dedupMs: TimeInterval = 0.8
    private let secretKeyRe = try! NSRegularExpression(pattern: "pass|token|secret|auth|cookie", options: [.caseInsensitive])
    private let actions: Set<String> = ["view", "tap", "submit", "appear", "disappear", "error", "custom"]
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        if #available(iOS 11.0, *) {
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        } else {
            f.formatOptions = [.withInternetDateTime]
        }
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    init(storage: SecureStorageService) {
        self.storage = storage
    }

    /// Never throws. Empty `screen` is ignored.
    func log(
        screen: String,
        widget: String? = nil,
        className: String? = nil,
        action: String = "view",
        extras: [String: Any]? = nil
    ) {
        guard var sanitized = sanitize(screen: screen, widget: widget, className: className, action: action, extras: extras) else {
            return
        }
        sanitized["timestamp"] = isoFormatter.string(from: Date())

        var logs = getLogs()
        let nowMs = parseMs(sanitized["timestamp"] as? String)
        let key = dedupKey(sanitized)

        if let last = logs.last, dedupKey(last) == key {
            let lastMs = parseMs(last["timestamp"] as? String)
            if nowMs - lastMs <= dedupMs * 1000 {
                logs[logs.count - 1] = sanitized
                persist(logs)
                return
            }
        }

        logs.append(sanitized)
        while logs.count > maxEvents { logs.removeFirst() }
        persist(logs)
    }

    func getLogs() -> [[String: Any]] {
        guard let raw = storage.read(DevGuardConstants.userLogsKey),
              let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return arr
    }

    func clearLogs() {
        storage.delete(DevGuardConstants.userLogsKey)
    }

    private func persist(_ logs: [[String: Any]]) {
        guard JSONSerialization.isValidJSONObject(logs),
              let json = try? JSONSerialization.data(withJSONObject: logs),
              let str = String(data: json, encoding: .utf8) else { return }
        storage.write(DevGuardConstants.userLogsKey, str)
    }

    private func sanitize(
        screen: String,
        widget: String?,
        className: String?,
        action: String,
        extras: [String: Any]?
    ) -> [String: Any]? {
        let s = truncate(screen, max: stringMax)
        if s.isEmpty { return nil }
        var out: [String: Any] = [
            "screen": s,
            "action": normalizeAction(action),
            "timestamp": isoFormatter.string(from: Date()),
        ]
        let w = truncate(widget, max: stringMax)
        if !w.isEmpty { out["widget"] = w }
        let c = truncate(className, max: stringMax)
        if !c.isEmpty { out["className"] = c }
        if let x = sanitizeExtras(extras) { out["extras"] = x }
        return out
    }

    private func normalizeAction(_ raw: String) -> String {
        let a = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return actions.contains(a) ? a : "custom"
    }

    private func truncate(_ value: String?, max: Int) -> String {
        let s = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "" }
        if s.count <= max { return s }
        return String(s.prefix(max))
    }

    private func sanitizeExtras(_ extras: [String: Any]?) -> [String: Any]? {
        guard let extras, !extras.isEmpty else { return nil }
        var out: [String: Any] = [:]
        for key in extras.keys.sorted() {
            if key.isEmpty || matchesSecret(key) { continue }
            switch extras[key] {
            case let value as String:
                out[key] = truncate(value, max: stringMax)
            case let value as Bool:
                out[key] = value
            case let value as Int:
                out[key] = value
            case let value as Double:
                out[key] = value
            case let value as NSNumber:
                if CFGetTypeID(value) == CFBooleanGetTypeID() {
                    out[key] = value.boolValue
                } else {
                    out[key] = value
                }
            default:
                break
            }
        }
        if out.isEmpty { return nil }
        if jsonLength(out) <= extrasJsonMax { return out }
        var trimmed: [String: Any] = [:]
        for key in out.keys.sorted() {
            trimmed[key] = out[key]
            if jsonLength(trimmed) > extrasJsonMax {
                trimmed.removeValue(forKey: key)
                break
            }
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    private func matchesSecret(_ key: String) -> Bool {
        let range = NSRange(location: 0, length: (key as NSString).length)
        return secretKeyRe.firstMatch(in: key, options: [], range: range) != nil
    }

    private func jsonLength(_ obj: [String: Any]) -> Int {
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj) else { return extrasJsonMax + 1 }
        return data.count
    }

    private func dedupKey(_ log: [String: Any]) -> String {
        let screen = log["screen"] as? String ?? ""
        let widget = log["widget"] as? String ?? ""
        let className = log["className"] as? String ?? ""
        let action = log["action"] as? String ?? ""
        return "\(screen)|\(widget)|\(className)|\(action)"
    }

    private func parseMs(_ raw: String?) -> TimeInterval {
        guard let raw, let date = isoFormatter.date(from: raw) else { return 0 }
        return date.timeIntervalSince1970 * 1000
    }
}
