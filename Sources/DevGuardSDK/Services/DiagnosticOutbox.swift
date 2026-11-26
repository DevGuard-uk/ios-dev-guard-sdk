import Foundation

/// Single record in the durable diagnostic outbox.
public struct DiagnosticRecord {
    public let clientRecordId: String
    public let kind: String
    public let payload: [String: Any]
    public let createdAt: String
    public let ackedAt: String?
    public let batchId: String?
    public let schemaVersion: Int

    public var isAcked: Bool {
        !(ackedAt?.isEmpty ?? true)
    }

    public init(
        clientRecordId: String,
        kind: String,
        payload: [String: Any],
        createdAt: String,
        ackedAt: String? = nil,
        batchId: String? = nil,
        schemaVersion: Int = 1
    ) {
        self.clientRecordId = clientRecordId
        self.kind = kind
        self.payload = payload
        self.createdAt = createdAt
        self.ackedAt = ackedAt
        self.batchId = batchId
        self.schemaVersion = schemaVersion
    }

    public func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "clientRecordId": clientRecordId,
            "kind": kind,
            "payload": payload,
            "createdAt": createdAt,
            "schemaVersion": schemaVersion,
        ]
        if let ackedAt { dict["ackedAt"] = ackedAt }
        if let batchId { dict["batchId"] = batchId }
        return dict
    }

    public static func fromDict(_ dict: [String: Any]) -> DiagnosticRecord? {
        guard let clientRecordId = dict["clientRecordId"] as? String else { return nil }
        let kind = (dict["kind"] as? String) ?? "usage"
        let payload = (dict["payload"] as? [String: Any]) ?? [:]
        let createdAt = (dict["createdAt"] as? String) ?? isoNow()
        let ackedAt = dict["ackedAt"] as? String
        let batchId = dict["batchId"] as? String
        let schemaVersion = (dict["schemaVersion"] as? Int) ?? 1
        return DiagnosticRecord(
            clientRecordId: clientRecordId,
            kind: kind,
            payload: payload,
            createdAt: createdAt,
            ackedAt: ackedAt,
            batchId: batchId,
            schemaVersion: schemaVersion
        )
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public static func isoNow(_ date: Date = Date()) -> String {
        isoFormatter.string(from: date)
    }

    public static func parseIsoDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        if let d = isoFormatter.date(from: string) { return d }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: string)
    }
}

/// Persistent device outbox for telemetry, crashes, and usage logs.
///
/// Ensures records are buffered locally before upload and are NEVER purged
/// until confirmed accepted by the server (ACK) + 48-hour cooling window.
public final class DiagnosticOutbox {
    public static let shared = DiagnosticOutbox()

    private let storage: SecureStorageService
    private let lock = NSLock()

    public static let storageKey = "dev_guard_diagnostic_outbox"
    public static let maxCapacity = 500

    public convenience init() {
        self.init(storage: SecureStorageService())
    }

    init(storage: SecureStorageService) {
        self.storage = storage
    }

    /// Pure RFC4122 v4 UUID generator.
    public static func generateRecordId() -> String {
        UUID().uuidString.lowercased()
    }

    /// Appends a new unacked record to the outbox.
    @discardableResult
    public func enqueue(
        kind: String,
        payload: [String: Any],
        clientRecordId: String? = nil
    ) -> DiagnosticRecord {
        lock.lock()
        defer { lock.unlock() }

        let record = DiagnosticRecord(
            clientRecordId: clientRecordId ?? Self.generateRecordId(),
            kind: kind,
            payload: payload,
            createdAt: DiagnosticRecord.isoNow()
        )

        var records = getRecordsLocked()
        records.append(record)
        enforceCap(&records)
        persistLocked(records)
        return record
    }

    /// Loads all records currently stored in the outbox.
    public func getRecords() -> [DiagnosticRecord] {
        lock.lock()
        defer { lock.unlock() }
        return getRecordsLocked()
    }

    private func getRecordsLocked() -> [DiagnosticRecord] {
        guard let raw = storage.read(Self.storageKey),
              let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return arr.compactMap { DiagnosticRecord.fromDict($0) }
    }

    /// Returns unacked records, optionally filtered by `kind` and capped by `limit`.
    public func getUnackedRecords(kind: String? = nil, limit: Int? = nil) -> [DiagnosticRecord] {
        lock.lock()
        defer { lock.unlock() }

        var unacked = getRecordsLocked().filter { !$0.isAcked }
        if let kind {
            unacked = unacked.filter { $0.kind == kind }
        }
        if let limit, limit > 0, unacked.count > limit {
            return Array(unacked.prefix(limit))
        }
        return unacked
    }

    /// Marks matching `clientRecordIds` as accepted by the server.
    public func markAcked(
        _ clientRecordIds: [String],
        batchId: String? = nil,
        ackedAt: String? = nil
    ) {
        guard !clientRecordIds.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        let idSet = Set(clientRecordIds)
        let ackIso = ackedAt ?? DiagnosticRecord.isoNow()
        var records = getRecordsLocked()
        var changed = false

        for i in 0..<records.count {
            if idSet.contains(records[i].clientRecordId) {
                let current = records[i]
                records[i] = DiagnosticRecord(
                    clientRecordId: current.clientRecordId,
                    kind: current.kind,
                    payload: current.payload,
                    createdAt: current.createdAt,
                    ackedAt: ackIso,
                    batchId: batchId ?? current.batchId,
                    schemaVersion: current.schemaVersion
                )
                changed = true
            }
        }

        if changed {
            persistLocked(records)
        }
    }

    /// Purges ONLY records where ackedAt is older than `retentionHours`.
    ///
    /// CRITICAL CONTRACT: Records where ackedAt is nil are NEVER deleted,
    /// preserving telemetry even if the device was offline for days.
    @discardableResult
    public func purgeExpiredAcked(retentionHours: Int = 48) -> Int {
        lock.lock()
        defer { lock.unlock() }

        var records = getRecordsLocked()
        let cutoff = Date().addingTimeInterval(-Double(retentionHours * 3600))
        let initialCount = records.count

        records.removeAll { record in
            guard record.isAcked, let ackDate = DiagnosticRecord.parseIsoDate(record.ackedAt) else {
                return false // Unacked NEVER expires
            }
            return ackDate < cutoff
        }

        let purgedCount = initialCount - records.count
        if purgedCount > 0 {
            persistLocked(records)
        }
        return purgedCount
    }

    /// Used by `clearLogs` command: wipes acked records while leaving unacked records intact.
    public func clearAckedOnly() {
        lock.lock()
        defer { lock.unlock() }

        var records = getRecordsLocked()
        let before = records.count
        records.removeAll { $0.isAcked }
        if records.count != before {
            persistLocked(records)
        }
    }

    /// Used by emergency remote wipe: wipes all records without upload.
    public func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        storage.delete(Self.storageKey)
    }

    private func enforceCap(_ records: inout [DiagnosticRecord]) {
        if records.count <= Self.maxCapacity { return }

        // 1. Remove expired acked (>48h)
        let cutoff = Date().addingTimeInterval(-Double(48 * 3600))
        records.removeAll { record in
            guard record.isAcked, let ackDate = DiagnosticRecord.parseIsoDate(record.ackedAt) else {
                return false
            }
            return ackDate < cutoff
        }

        // 2. If still over cap, remove oldest acked
        if records.count > Self.maxCapacity {
            var i = 0
            while i < records.count && records.count > Self.maxCapacity {
                if records[i].isAcked {
                    records.remove(at: i)
                } else {
                    i += 1
                }
            }
        }

        // 3. If STILL over cap (unacked overflow), drop oldest non-fatal unacked
        if records.count > Self.maxCapacity {
            var i = 0
            while i < records.count && records.count > Self.maxCapacity {
                let isFatal = records[i].kind == "crash" && (records[i].payload["isFatal"] as? Bool == true)
                if !isFatal {
                    records.remove(at: i)
                } else {
                    i += 1
                }
            }
        }
    }

    private func persistLocked(_ records: [DiagnosticRecord]) {
        let dicts = records.map { $0.toDict() }
        guard let data = try? JSONSerialization.data(withJSONObject: dicts),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        storage.write(Self.storageKey, json)
    }
}
