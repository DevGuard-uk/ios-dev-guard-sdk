import Foundation

/// Result of a diagnostic batch flush attempt.
public struct DiagnosticBatchResult {
    public let success: Bool
    public let batchId: String?
    public let flushedCount: Int
    public let ackedCount: Int
    public let retryAfterSeconds: Int?
    public let error: String?

    public init(
        success: Bool,
        batchId: String? = nil,
        flushedCount: Int = 0,
        ackedCount: Int = 0,
        retryAfterSeconds: Int? = nil,
        error: String? = nil
    ) {
        self.success = success
        self.batchId = batchId
        self.flushedCount = flushedCount
        self.ackedCount = ackedCount
        self.retryAfterSeconds = retryAfterSeconds
        self.error = error
    }
}

/// Orchestrates flushing buffered unacked records from [DiagnosticOutbox]
/// to the DevGuard API `/api/v1/telemetry/diagnostic-batch` (begin + commit).
public final class DiagnosticBatchService {
    public static let shared = DiagnosticBatchService()

    private let lock = NSLock()
    private var projectId: String?
    private var secret: String?
    private var baseUrl: String = NativeBridge.defaultStatusUrl()
    private var deviceIdProvider: (() -> String?)?
    private var outbox: DiagnosticOutbox = DiagnosticOutbox.shared

    private static var rateLimitUntilMs: Int64 = 0
    private static let rateLimitLock = NSLock()

    public static var isRateLimited: Bool {
        rateLimitLock.lock()
        defer { rateLimitLock.unlock() }
        return Int64(Date().timeIntervalSince1970 * 1000) < rateLimitUntilMs
    }

    public static var rateLimitRemainingSeconds: Int {
        rateLimitLock.lock()
        defer { rateLimitLock.unlock() }
        let diff = rateLimitUntilMs - Int64(Date().timeIntervalSince1970 * 1000)
        return diff > 0 ? Int(ceil(Double(diff) / 1000.0)) : 0
    }

    public static func resetRateLimitForTesting() {
        rateLimitLock.lock()
        rateLimitUntilMs = 0
        rateLimitLock.unlock()
    }

    public init() {}

    public func configure(
        projectId: String,
        secret: String?,
        baseUrl: String,
        deviceIdProvider: (() -> String?)? = nil,
        outbox: DiagnosticOutbox? = nil
    ) {
        lock.lock()
        self.projectId = projectId
        self.secret = secret
        self.baseUrl = baseUrl
        if let deviceIdProvider { self.deviceIdProvider = deviceIdProvider }
        if let outbox { self.outbox = outbox }
        lock.unlock()
    }

    private func snapshotConfig() -> (pid: String?, sec: String?, base: String, devId: String, box: DiagnosticOutbox) {
        lock.lock()
        defer { lock.unlock() }
        let devId = deviceIdProvider?() ?? "unknown_device"
        return (projectId, secret, baseUrl, devId, outbox)
    }

    public func flush(
        maxRecords: Int = 100,
        maxBytes: Int = 262144 // 256 KiB
    ) async -> DiagnosticBatchResult {
        let (pid, sec, base, devId, box) = snapshotConfig()

        guard let pid, !pid.isEmpty else {
            return DiagnosticBatchResult(success: false, error: "Not configured (missing projectId)")
        }

        if Self.isRateLimited {
            return DiagnosticBatchResult(
                success: false,
                retryAfterSeconds: Self.rateLimitRemainingSeconds,
                error: "Rate limited (Retry-After active)"
            )
        }

        let unacked = box.getUnackedRecords(limit: maxRecords)
        if unacked.isEmpty {
            return DiagnosticBatchResult(success: true, flushedCount: 0)
        }

        // Pack batch up to maxBytes
        var batchRecords: [DiagnosticRecord] = []
        var currentBytes = 0
        for r in unacked {
            guard let data = try? JSONSerialization.data(withJSONObject: r.toDict()) else { continue }
            let recordBytes = data.count
            if !batchRecords.isEmpty && currentBytes + recordBytes > maxBytes {
                break
            }
            batchRecords.append(r)
            currentBytes += recordBytes
        }

        if batchRecords.isEmpty {
            return DiagnosticBatchResult(success: true, flushedCount: 0)
        }

        let batchDicts = batchRecords.map { $0.toDict() }
        guard let batchData = try? JSONSerialization.data(withJSONObject: batchDicts) else {
            return DiagnosticBatchResult(success: false, error: "Failed to serialize batch payload")
        }
        let batchPayloadStr = String(data: batchData, encoding: .utf8) ?? ""
        let shaDigest = NativeBridge.hashSha256Hex(batchPayloadStr)
        let kinds = Array(Set(batchRecords.map { $0.kind }))

        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let signature = NativeBridge.generateSignature(projectId: pid, timestamp: timestamp)

        do {
            // 1. Begin batch
            guard let beginUrl = URL(string: Self.routeUrl(base: base, endpointPath: "/api/v1/telemetry/diagnostic-batch/begin")) else {
                return DiagnosticBatchResult(success: false, error: "Invalid begin URL")
            }

            var beginReq = URLRequest(url: beginUrl, timeoutInterval: 15)
            beginReq.httpMethod = "POST"
            beginReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            beginReq.setValue(signature, forHTTPHeaderField: DevGuardConstants.hdrSig)
            beginReq.setValue(String(timestamp), forHTTPHeaderField: DevGuardConstants.hdrTs)
            if let sec, !sec.isEmpty {
                beginReq.setValue(sec, forHTTPHeaderField: DevGuardConstants.hdrApiKey)
            }
            beginReq.setValue("1", forHTTPHeaderField: DevGuardConstants.hdrTunnel)

            let beginBody: [String: Any] = [
                "projectId": pid,
                "deviceId": devId,
                "recordCount": batchRecords.count,
                "sha256": shaDigest,
                "kinds": kinds,
                "byteSize": currentBytes,
            ]
            beginReq.httpBody = try JSONSerialization.data(withJSONObject: beginBody)

            let (beginData, beginResp) = try await URLSession.shared.data(for: beginReq)
            guard let beginHttp = beginResp as? HTTPURLResponse else {
                return DiagnosticBatchResult(success: false, error: "Non-HTTP begin response")
            }

            if beginHttp.statusCode == 429 {
                Self.applyRateLimit(response: beginHttp, data: beginData)
                return DiagnosticBatchResult(
                    success: false,
                    retryAfterSeconds: Self.rateLimitRemainingSeconds,
                    error: "Rate limit 429 on begin"
                )
            }

            guard beginHttp.statusCode >= 200 && beginHttp.statusCode < 300 else {
                let errText = String(data: beginData, encoding: .utf8) ?? ""
                return DiagnosticBatchResult(success: false, error: "Begin returned HTTP \(beginHttp.statusCode): \(errText)")
            }

            guard let beginJson = try? JSONSerialization.jsonObject(with: beginData) as? [String: Any],
                  let batchId = beginJson["batchId"] as? String, !batchId.isEmpty else {
                return DiagnosticBatchResult(success: false, error: "Missing batchId in begin response")
            }
            let mode = (beginJson["mode"] as? String) ?? "inline"

            // 2. Commit batch (mode == "inline")
            if mode == "inline" {
                guard let commitUrl = URL(string: Self.routeUrl(base: base, endpointPath: "/api/v1/telemetry/diagnostic-batch/commit")) else {
                    return DiagnosticBatchResult(success: false, batchId: batchId, error: "Invalid commit URL")
                }

                var commitReq = URLRequest(url: commitUrl, timeoutInterval: 20)
                commitReq.httpMethod = "POST"
                commitReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                commitReq.setValue(signature, forHTTPHeaderField: DevGuardConstants.hdrSig)
                commitReq.setValue(String(timestamp), forHTTPHeaderField: DevGuardConstants.hdrTs)
                if let sec, !sec.isEmpty {
                    commitReq.setValue(sec, forHTTPHeaderField: DevGuardConstants.hdrApiKey)
                }
                commitReq.setValue("1", forHTTPHeaderField: DevGuardConstants.hdrTunnel)

                let commitBody: [String: Any] = [
                    "projectId": pid,
                    "deviceId": devId,
                    "batchId": batchId,
                    "clientRecordIds": batchRecords.map { $0.clientRecordId },
                    "records": batchDicts,
                ]
                commitReq.httpBody = try JSONSerialization.data(withJSONObject: commitBody)

                let (commitData, commitResp) = try await URLSession.shared.data(for: commitReq)
                guard let commitHttp = commitResp as? HTTPURLResponse else {
                    return DiagnosticBatchResult(success: false, batchId: batchId, error: "Non-HTTP commit response")
                }

                if commitHttp.statusCode == 429 {
                    Self.applyRateLimit(response: commitHttp, data: commitData)
                    return DiagnosticBatchResult(
                        success: false,
                        batchId: batchId,
                        retryAfterSeconds: Self.rateLimitRemainingSeconds,
                        error: "Rate limit 429 on commit"
                    )
                }

                guard commitHttp.statusCode >= 200 && commitHttp.statusCode < 300 else {
                    let errText = String(data: commitData, encoding: .utf8) ?? ""
                    return DiagnosticBatchResult(success: false, batchId: batchId, error: "Commit returned HTTP \(commitHttp.statusCode): \(errText)")
                }

                guard let commitJson = try? JSONSerialization.jsonObject(with: commitData) as? [String: Any] else {
                    return DiagnosticBatchResult(success: false, batchId: batchId, error: "Invalid commit JSON")
                }

                let acceptedIds = (commitJson["acceptedIds"] as? [String]) ?? []
                if !acceptedIds.isEmpty {
                    box.markAcked(acceptedIds, batchId: batchId)
                    box.purgeExpiredAcked(retentionHours: 48)
                }

                return DiagnosticBatchResult(
                    success: true,
                    batchId: batchId,
                    flushedCount: batchRecords.count,
                    ackedCount: acceptedIds.count
                )
            }

            return DiagnosticBatchResult(
                success: true,
                batchId: batchId,
                flushedCount: batchRecords.count,
                ackedCount: 0
            )
        } catch {
            return DiagnosticBatchResult(success: false, error: error.localizedDescription)
        }
    }

    private static func applyRateLimit(response: HTTPURLResponse, data: Data) {
        var seconds = 60
        if let retryHeader = response.value(forHTTPHeaderField: "Retry-After"),
           let parsed = Int(retryHeader), parsed > 0 {
            seconds = parsed
        } else if let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let parsed = json["retryAfter"] as? Int, parsed > 0 {
            seconds = parsed
        }
        rateLimitLock.lock()
        rateLimitUntilMs = Int64(Date().timeIntervalSince1970 * 1000) + Int64(seconds * 1000)
        rateLimitLock.unlock()
    }

    private static func routeUrl(base: String, endpointPath: String) -> String {
        let trimmed = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.hasSuffix("/devguard") {
            return trimmed.replacingOccurrences(of: "/devguard", with: endpointPath)
        }
        return "\(trimmed)\(endpointPath)"
    }
}
