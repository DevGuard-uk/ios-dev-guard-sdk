import Foundation
import UIKit
import CrashReporter

/// DevGuard transport for capture-only [CrashReporter]: remaps schema-v2 [CrashReport]
/// → Admin plugin-crash body, injects `projectId`, and HMAC-signs the POST.
final class DevGuardCrashSink: CrashSink {
    private let lock = NSLock()
    private var projectId: String
    private var secret: String
    private var baseUrl: String

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private var outbox: DiagnosticOutbox?

    init(projectId: String, secret: String, baseUrl: String, outbox: DiagnosticOutbox? = nil) {
        self.projectId = projectId
        self.secret = secret
        self.baseUrl = baseUrl
        self.outbox = outbox
    }

    func update(projectId: String, secret: String, baseUrl: String, outbox: DiagnosticOutbox? = nil) {
        lock.lock()
        self.projectId = projectId
        self.secret = secret
        self.baseUrl = baseUrl
        if let outbox { self.outbox = outbox }
        lock.unlock()
    }

    func didCapture(_ report: CrashReport) {
        lock.lock()
        let projectId = self.projectId
        let secret = self.secret
        let baseUrl = self.baseUrl
        let outbox = self.outbox
        lock.unlock()

        Task {
            do {
                let deviceId = report.tags["deviceId"] ?? ""
                let clientRecordId = DiagnosticOutbox.generateRecordId()

                var body: [String: Any] = [
                    "clientRecordId": clientRecordId,
                    "projectId": projectId,
                    "deviceId": deviceId,
                    "errorMessage": report.detail,
                    "errorName": report.title,
                    "crashType": Self.mapCrashType(report),
                    "isFatal": report.severity == CrashReport.sevFatal,
                    "sdkRuntime": report.tags["sdkRuntime"] ?? SdkIdentity.sdkRuntime,
                    "sdkVersion": report.tags["sdkVersion"] ?? SdkIdentity.sdkVersion,
                    "hostPlatform": report.tags["hostPlatform"] ?? (report.env.os.isEmpty ? "ios" : report.env.os),
                    "hostPlatformVersion": report.env.osVer,
                    "occurredAt": Self.iso8601.string(from: report.timestamp),
                ]
                if let stackTrace = report.frames {
                    body["stackTrace"] = stackTrace
                }
                if let version = report.tags["appVersion"] ?? report.tags["version"] {
                    body["appVersion"] = version
                }
                if let clientMeta = Self.buildClientMeta(report) {
                    body["clientMeta"] = clientMeta
                }

                // Buffer crash / ANR into outbox first
                outbox?.enqueue(kind: "crash", payload: body, clientRecordId: clientRecordId)

                guard StatusUrlResolver.isAllowed(baseUrl) else { return }
                guard !deviceId.isEmpty else { return }

                let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
                let signature = NativeBridge.generateSignature(projectId: projectId, timestamp: timestamp)

                guard let url = URL(string: Self.telemetryUrl(baseUrl: baseUrl)) else { return }
                var request = URLRequest(url: url, timeoutInterval: 8)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(signature, forHTTPHeaderField: DevGuardConstants.hdrSig)
                request.setValue(String(timestamp), forHTTPHeaderField: DevGuardConstants.hdrTs)
                request.setValue(secret, forHTTPHeaderField: DevGuardConstants.hdrApiKey)
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode >= 200 && http.statusCode < 300 {
                    outbox?.markAcked([clientRecordId])
                    outbox?.purgeExpiredAcked(retentionHours: 48)
                }
            } catch {
                // Never block app flows on crash telemetry.
            }
        }
    }

    private static func telemetryUrl(baseUrl: String) -> String {
        let base = baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if base.hasSuffix("/devguard") {
            return base.replacingOccurrences(of: "/devguard", with: "/api/v1/telemetry/plugin-crash")
        }
        return "\(base)/api/v1/telemetry/plugin-crash"
    }

    /// Capture `kind` → Admin `crashType` (existing VALID_CRASH_TYPES).
    static func mapCrashType(_ report: CrashReport) -> String {
        switch report.kind {
        case CrashReport.kindManual:
            let legacy = report.tags["legacyType"] ?? ""
            return legacy.isEmpty ? "sdk_internal" : legacy
        case CrashReport.kindUncaught, CrashReport.kindSignal, CrashReport.kindAnr:
            return "native_crash"
        default:
            let legacy = report.tags["legacyType"] ?? ""
            return legacy.isEmpty ? "sdk_internal" : legacy
        }
    }

    static func buildClientMeta(_ report: CrashReport) -> [String: Any]? {
        var meta: [String: Any] = [:]
        if let location = report.location {
            meta["context"] = location
        }
        if !report.crumbs.isEmpty {
            meta["breadcrumbs"] = report.crumbs.map { crumb -> [String: Any] in
                [
                    "ts": iso8601.string(from: crumb.timestamp),
                    "cat": crumb.category,
                    "msg": crumb.message,
                    "data": crumb.data,
                ]
            }
        }
        if let signal = report.signal {
            var sig: [String: Any] = ["num": signal.number, "name": signal.name]
            if let code = signal.code {
                sig["code"] = code
            }
            meta["signal"] = sig
        }
        if let anr = report.anr {
            var anrDict: [String: Any] = [:]
            if let reason = anr.reason { anrDict["reason"] = reason }
            if let importance = anr.importance { anrDict["importance"] = importance }
            if let description = anr.description { anrDict["description"] = description }
            if !anrDict.isEmpty {
                meta["anr"] = anrDict
            }
        }
        return meta.isEmpty ? nil : meta
    }
}
