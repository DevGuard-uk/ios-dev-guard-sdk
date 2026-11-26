import Foundation

/// Parse HTTP `Retry-After` (delta-seconds) and clamp to the SDK honor window (1–60).
/// Invalid / empty / HTTP-date → nil (no multi-minute sleep on bad headers).
enum RetryAfter {
    static func parseSeconds(_ raw: String?) -> Int? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        guard let secs = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)), secs >= 1 else {
            return nil
        }
        return secs > 60 ? 60 : secs
    }
}
