import Foundation
import UIKit

final class SecureStorageService {
    private let defaults = UserDefaults(suiteName: "io.devguard.secure") ?? .standard

    func write(_ key: String, _ value: String) {
        defaults.set(value, forKey: key)
    }

    func read(_ key: String) -> String? {
        defaults.string(forKey: key)
    }

    func delete(_ key: String) {
        defaults.removeObject(forKey: key)
    }

    func deleteAllDeviceUserKeys() {
        [DevGuardConstants.usernameKey, DevGuardConstants.emailKey, DevGuardConstants.phoneKey, DevGuardConstants.customDataKey]
            .forEach { delete($0) }
    }
}

final class CacheService {
    private let storage: SecureStorageService
    private let projectId: String?

    init(storage: SecureStorageService, projectId: String?) {
        self.storage = storage
        self.projectId = projectId
    }

    private func encrypt(_ plain: String) -> String {
        guard let projectId else { return plain }
        let key = Array(projectId.utf8)
        let bytes = Array(plain.utf8)
        let encrypted = NativeBridge.xorTransform(bytes, key: key)
        return Data(encrypted).base64EncodedString()
    }

    private func decrypt(_ encrypted: String) -> String {
        guard let projectId, let data = Data(base64Encoded: encrypted) else { return encrypted }
        let key = Array(projectId.utf8)
        let decrypted = NativeBridge.xorTransform(Array(data), key: key)
        return String(bytes: decrypted, encoding: .utf8) ?? encrypted
    }

    func saveResponse(_ response: GuardResponse) {
        if let json = try? JSONSerialization.data(withJSONObject: response.toDict()) {
            storage.write(DevGuardConstants.cacheKey, encrypt(String(data: json, encoding: .utf8) ?? ""))
        }
    }

    func getResponse() -> GuardResponse? {
        guard let data = storage.read(DevGuardConstants.cacheKey) else { return nil }
        let decrypted = decrypt(data)
        guard let jsonData = decrypted.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return nil }
        return GuardResponse.fromDict(dict)
    }

    func clear() { storage.delete(DevGuardConstants.cacheKey) }

    func getLastWipeNonce() -> Int? {
        guard let val = storage.read(DevGuardConstants.wipeNonceKey) else { return nil }
        return Int(val)
    }

    func setLastWipeNonce(_ nonce: Int) {
        storage.write(DevGuardConstants.wipeNonceKey, String(nonce))
    }
}

final class DeviceTokenService {
    private let storage: SecureStorageService
    init(storage: SecureStorageService) { self.storage = storage }

    func getToken() -> String? {
        guard let scrambled = storage.read(DevGuardConstants.tokenKey) else { return nil }
        return NativeBridge.secureGetToken(scrambled)
    }

    func saveToken(_ token: String) {
        storage.write(DevGuardConstants.tokenKey, NativeBridge.secureSaveToken(token))
    }

    func clearToken() { storage.delete(DevGuardConstants.tokenKey) }

    func generateFingerprint(deviceId: String, model: String?, os: String?) -> String {
        let raw = "\(deviceId)|\(model ?? "unknown")|\(os ?? "unknown")"
        return String(NativeBridge.hashSha256Hex(raw).prefix(16))
    }
}

final class UsageLogger {
    private let storage: SecureStorageService
    private let maxEvents = 100
    init(storage: SecureStorageService) { self.storage = storage }

    func logEvent(_ type: String, data: [String: Any] = [:]) {
        var logs = getLogs()
        logs.append(["type": type, "timestamp": Date().timeIntervalSince1970 * 1000, "data": data])
        while logs.count > maxEvents { logs.removeFirst() }
        if let json = try? JSONSerialization.data(withJSONObject: logs) {
            storage.write(DevGuardConstants.usageLogsKey, String(data: json, encoding: .utf8) ?? "[]")
        }
    }

    func getLogs() -> [[String: Any]] {
        guard let raw = storage.read(DevGuardConstants.usageLogsKey),
              let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr
    }

    func clearLogs() { storage.delete(DevGuardConstants.usageLogsKey) }
}

final class HardwareService {
    private let storage: SecureStorageService
    private let tokenService: DeviceTokenService
    private let usageLogger: UsageLogger
    private let cachedResponse: GuardResponse?

    init(storage: SecureStorageService, tokenService: DeviceTokenService, usageLogger: UsageLogger, cachedResponse: GuardResponse?) {
        self.storage = storage
        self.tokenService = tokenService
        self.usageLogger = usageLogger
        self.cachedResponse = cachedResponse
    }

    var advancedTelemetry: Bool {
        cachedResponse?.betaFeatures["advancedTelemetry"] as? Bool == true
    }

    static func quickResolveDeviceId() -> String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown_ios"
    }

    func collect(forceLogs: Bool = false) -> DeviceMetadata {
        let device = UIDevice.current
        let deviceId = Self.quickResolveDeviceId()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        #if targetEnvironment(simulator)
        let isPhysical = false
        #else
        let isPhysical = true
        #endif

        var customData: [String: Any]?
        if let raw = storage.read(DevGuardConstants.customDataKey),
           let data = raw.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            customData = dict
        }

        let model = device.model
        let os = "iOS \(device.systemVersion)"

        return DeviceMetadata(
            deviceId: deviceId,
            deviceName: device.name,
            model: model,
            brand: "Apple",
            os: os,
            appVersion: "\(version)+\(build)",
            isPhysicalDevice: isPhysical,
            username: storage.read(DevGuardConstants.usernameKey),
            email: storage.read(DevGuardConstants.emailKey),
            phone: storage.read(DevGuardConstants.phoneKey),
            customData: customData,
            battery: advancedTelemetry ? "\(Int(device.batteryLevel * 100))%" : nil,
            ram: advancedTelemetry ? "\(NativeBridge.getTotalRamMb()) MB" : nil,
            storage: nil,
            networkType: nil,
            usageLogs: forceLogs ? usageLogger.getLogs() : nil,
            deviceToken: tokenService.getToken(),
            fingerprint: tokenService.generateFingerprint(deviceId: deviceId, model: model, os: os),
            sdkRuntime: SdkIdentity.sdkRuntime,
            sdkVersion: SdkIdentity.sdkVersion,
            hostPlatform: "ios",
            hostPlatformVersion: device.systemVersion
        )
    }

    func isDeviceCompromised() -> Bool {
        let paths = ["/Applications/Cydia.app", "/Library/MobileSubstrate/MobileSubstrate.dylib", "/bin/bash", "/usr/sbin/sshd"]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }
}

final class SyncPolicyService {
    private let storage: SecureStorageService
    private var lastLifecycleSync: TimeInterval = 0
    init(storage: SecureStorageService) { self.storage = storage }

    func shouldSync(cachedResponse: GuardResponse?, forceLogs: Bool, trigger: String?) -> Bool {
        if forceLogs { return true }
        if trigger == "foreground" || trigger == "background" || trigger == "appLaunch" {
            let lifecycle = cachedResponse?.lifecycleSync
            let enabled: Bool
            if let lifecycle {
                switch trigger {
                case "foreground": enabled = lifecycle["onForeground"] as? Bool == true
                case "background": enabled = lifecycle["onBackground"] as? Bool == true
                default: enabled = lifecycle["onAppLaunch"] as? Bool == true
                }
            } else {
                enabled = trigger != "background"
            }
            if !enabled { return false }
            let now = Date().timeIntervalSince1970
            if now - lastLifecycleSync < 60 { return false }
            lastLifecycleSync = now
            return true
        }
        if trigger == "heartbeat" { return evaluateSyncPolicy(cachedResponse?.syncPolicy ?? "immediate") }
        if cachedResponse?.lifecycleSync != nil { return true }
        return evaluateSyncPolicy(cachedResponse?.syncPolicy ?? "immediate")
    }

    private func evaluateSyncPolicy(_ policy: String) -> Bool {
        if policy == "immediate" { return true }
        if policy == "onDemand" { return false }
        let last = Double(storage.read(DevGuardConstants.lastSyncKey) ?? "0") ?? 0
        let now = Date().timeIntervalSince1970 * 1000
        switch policy {
        case "daily": return now - last > 86_400_000
        case "weekly": return now - last > 604_800_000
        default: return true
        }
    }

    func recordSuccessfulSync() {
        storage.write(DevGuardConstants.lastSyncKey, String(Int(Date().timeIntervalSince1970 * 1000)))
    }
}

enum GuardEnforcement {
    static func apply(_ response: GuardResponse, metadata: DeviceMetadata, isCompromised: Bool = false) -> GuardResponse {
        if isCompromised {
            let code = NativeBridge.evaluatePolicy(blockEmulators: false, isPhysical: metadata.isPhysicalDevice, isCompromised: true)
            if code == PolicyLock.compromised {
                return response.copyWith(status: .locked, title: "Security Alert", message: "This device appears to be compromised. Access is restricted for your protection.")
            }
        }
        let code = NativeBridge.evaluatePolicy(
            blockEmulators: response.blockEmulators,
            isPhysical: metadata.isPhysicalDevice,
            isCompromised: false
        )
        if code == PolicyLock.emulator {
            return response.copyWith(
                status: .locked,
                title: "Simulator Detected",
                message: "This application cannot run on emulators or simulators."
            )
        }
        return response
    }
}

final class RestClient {
    private let baseUrl: String
    private let secret: String?

    init(baseUrl: String, secret: String?) {
        self.baseUrl = (try? StatusUrlResolver.resolve(baseUrl)) ?? baseUrl
        self.secret = secret
    }

    private func authHeaders(signature: String, timestamp: Int64, includeTunnel: Bool = false) -> [String: String] {
        guard StatusUrlResolver.isAllowed(baseUrl) else {
            return ["Content-Type": "application/json"]
        }
        var headers: [String: String] = [
            "Content-Type": "application/json",
            DevGuardConstants.hdrSig: signature,
            DevGuardConstants.hdrTs: String(timestamp),
            DevGuardConstants.hdrApiKey: secret ?? "",
        ]
        if includeTunnel {
            headers[DevGuardConstants.hdrTunnel] = DevGuardConstants.tunnelV1
        }
        return headers
    }

    func fetchStatus(projectId: String, metadata: DeviceMetadata?) async -> StatusFetchResult {
        guard StatusUrlResolver.isAllowed(baseUrl) else {
            return StatusFetchResult(response: nil, failure: .networkError)
        }
        guard let url = URL(string: baseUrl) else {
            return StatusFetchResult(response: nil, failure: .networkError)
        }
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let signature = NativeBridge.generateSignature(projectId: projectId, timestamp: timestamp)

        let metadataMap = metadata?.toPayloadMap() ?? [:]
        guard let metadataJson = try? JSONSerialization.data(withJSONObject: metadataMap),
              let compressed = GzipHelper.compress(metadataJson) else {
            return StatusFetchResult(response: nil, failure: .networkError)
        }
        let encodedPayload = compressed.base64EncodedString()

        var body: [String: Any] = [
            "projectId": projectId,
            "p": encodedPayload,
        ]
        if let metadata {
            body["deviceId"] = metadata.deviceId
            body["version"] = metadata.appVersion
            body["isPhysicalDevice"] = metadata.isPhysicalDevice
        }

        var request = URLRequest(url: url, timeoutInterval: 50)
        request.httpMethod = "POST"
        authHeaders(signature: signature, timestamp: timestamp, includeTunnel: true).forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return StatusFetchResult(response: nil, failure: .networkError)
            }
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            guard let serverSig = http.value(forHTTPHeaderField: DevGuardConstants.respSig) else {
                return StatusFetchResult(response: nil, failure: .signatureMismatch)
            }
            if !NativeBridge.verifyResponse(responseBody: responseBody, signature: serverSig) {
                if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let beta = dict["betaFeatures"] as? [String: Any],
                   beta["bypassSignature"] as? Bool == true {
                    // dev bypass
                } else {
                    return StatusFetchResult(response: nil, failure: .signatureMismatch)
                }
            }
            guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return StatusFetchResult(response: nil, failure: .networkError)
            }
            return StatusFetchResult(response: GuardResponse.fromDict(dict), failure: .none)
        } catch {
            if (error as? URLError)?.code == .timedOut {
                return StatusFetchResult(response: nil, failure: .timeout)
            }
            return StatusFetchResult(response: nil, failure: .networkError)
        }
    }

    func verifyAndUnlock(projectId: String, hashedKey: String) async -> Bool {
        guard StatusUrlResolver.isAllowed(baseUrl) else { return false }
        guard var components = URLComponents(string: baseUrl) else { return false }
        let path = components.path.hasSuffix("/") ? "\(components.path)unlock" : "\(components.path)/unlock"
        components.path = path
        guard let url = components.url else { return false }

        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let signature = NativeBridge.generateSignature(projectId: projectId, timestamp: timestamp)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        authHeaders(signature: signature, timestamp: timestamp).forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["projectId": projectId, "providedKey": hashedKey])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
            let body = String(data: data, encoding: .utf8) ?? ""
            guard let serverSig = http.value(forHTTPHeaderField: DevGuardConstants.respSig),
                  NativeBridge.verifyResponse(responseBody: body, signature: serverSig) else { return false }
            return body.trimmingCharacters(in: .whitespacesAndNewlines) == "unlocked"
        } catch {
            return false
        }
    }

}

final class RemoteWipeService {
    private let cache: CacheService
    private let usageLogger: UsageLogger
    private let storage: SecureStorageService
    private let tokenService: DeviceTokenService

    init(cache: CacheService, usageLogger: UsageLogger, storage: SecureStorageService, tokenService: DeviceTokenService) {
        self.cache = cache
        self.usageLogger = usageLogger
        self.storage = storage
        self.tokenService = tokenService
    }

    func execute(revokeToken: Bool = false) {
        cache.clear()
        usageLogger.clearLogs()
        storage.deleteAllDeviceUserKeys()
        if revokeToken { tokenService.clearToken() }
    }
}
