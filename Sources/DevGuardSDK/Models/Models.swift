import Foundation

public enum LicenseStatus: String {
    case pending = "PENDING"
    case active = "ACTIVE"
    case warning = "WARNING"
    case locked = "LOCKED"
    case expired = "EXPIRED"

    static func fromString(_ value: String?) -> LicenseStatus {
        switch value?.lowercased() {
        case "pending": return .pending
        case "warning": return .warning
        case "locked": return .locked
        case "expired": return .expired
        default: return .active
        }
    }
}

public struct LockScreenBranding: Codable, Equatable {
    public let brandName: String?
    public let logoUrl: String?
    public let primaryColor: String?
    public let accentColor: String?
    public let websiteUrl: String?
    public let hidePoweredBy: Bool

    static func fromDict(_ dict: [String: Any]?) -> LockScreenBranding? {
        guard let dict else { return nil }
        return LockScreenBranding(
            brandName: dict["brandName"] as? String,
            logoUrl: dict["logoUrl"] as? String,
            primaryColor: dict["primaryColor"] as? String,
            accentColor: dict["accentColor"] as? String,
            websiteUrl: dict["websiteUrl"] as? String,
            hidePoweredBy: dict["hidePoweredBy"] as? Bool ?? false
        )
    }
}

public struct GuardResponse {
    public let status: LicenseStatus
    public let title: String?
    public let message: String
    public let contactEmail: String
    public let contactPhone: String
    public let contactWhatsapp: String
    public let allowUnlock: Bool
    public let betaFeatures: [String: Any]
    public let extraData: [String: Any]
    public let lifecycleSync: [String: Any]?
    public let remoteCommand: String?
    public let deviceToken: String?
    public let pingInterval: Int
    public let syncPolicy: String
    public let blockEmulators: Bool
    /// Root/jailbreak policy from heartbeat: `warn` (default) or `block`.
    public let rootPolicy: String
    public let diagnosticPasscodeHash: String?
    public let branding: LockScreenBranding?
    public let wipeNonce: Int?

    public func copyWith(status: LicenseStatus? = nil, title: String? = nil, message: String? = nil) -> GuardResponse {
        GuardResponse(
            status: status ?? self.status,
            title: title ?? self.title,
            message: message ?? self.message,
            contactEmail: contactEmail,
            contactPhone: contactPhone,
            contactWhatsapp: contactWhatsapp,
            allowUnlock: allowUnlock,
            betaFeatures: betaFeatures,
            extraData: extraData,
            lifecycleSync: lifecycleSync,
            remoteCommand: remoteCommand,
            deviceToken: deviceToken,
            pingInterval: pingInterval,
            syncPolicy: syncPolicy,
            blockEmulators: blockEmulators,
            rootPolicy: rootPolicy,
            diagnosticPasscodeHash: diagnosticPasscodeHash,
            branding: branding,
            wipeNonce: wipeNonce
        )
    }

    func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "status": status.rawValue.lowercased(),
            "message": message,
            "contactEmail": contactEmail,
            "contactPhone": contactPhone,
            "contactWhatsapp": contactWhatsapp,
            "allowUnlock": allowUnlock,
            "betaFeatures": betaFeatures,
            "extraData": extraData,
            "pingInterval": pingInterval,
            "syncPolicy": syncPolicy,
            "blockEmulators": blockEmulators,
            "rootPolicy": rootPolicy,
            "diagnosticPasscodeHash": diagnosticPasscodeHash as Any,
        ]
        if let title { dict["title"] = title }
        if let lifecycleSync { dict["lifecycleSync"] = lifecycleSync }
        if let remoteCommand { dict["remoteCommand"] = remoteCommand }
        if let deviceToken { dict["deviceToken"] = deviceToken }
        if let wipeNonce { dict["wipeNonce"] = wipeNonce }
        if let branding {
            dict["branding"] = [
                "brandName": branding.brandName as Any,
                "logoUrl": branding.logoUrl as Any,
                "primaryColor": branding.primaryColor as Any,
                "accentColor": branding.accentColor as Any,
                "websiteUrl": branding.websiteUrl as Any,
                "hidePoweredBy": branding.hidePoweredBy,
            ]
        }
        return dict
    }

    static func fromDict(_ dict: [String: Any]) -> GuardResponse {
        let ping = (dict["pingInterval"] as? NSNumber)?.intValue ?? 5
        return GuardResponse(
            status: LicenseStatus.fromString(dict["status"] as? String),
            title: dict["title"] as? String,
            message: dict["message"] as? String ?? "",
            contactEmail: dict["contactEmail"] as? String ?? "",
            contactPhone: dict["contactPhone"] as? String ?? "",
            contactWhatsapp: dict["contactWhatsapp"] as? String ?? "",
            allowUnlock: dict["allowUnlock"] as? Bool ?? false,
            betaFeatures: dict["betaFeatures"] as? [String: Any] ?? [:],
            extraData: dict["extraData"] as? [String: Any] ?? [:],
            lifecycleSync: dict["lifecycleSync"] as? [String: Any],
            remoteCommand: dict["remoteCommand"] as? String,
            deviceToken: dict["deviceToken"] as? String,
            pingInterval: max(ping, 1),
            syncPolicy: dict["syncPolicy"] as? String ?? "immediate",
            blockEmulators: dict["blockEmulators"] as? Bool ?? false,
            rootPolicy: (dict["rootPolicy"] as? String) == "block" ? "block" : "warn",
            diagnosticPasscodeHash: dict["diagnosticPasscodeHash"] as? String,
            branding: LockScreenBranding.fromDict(dict["branding"] as? [String: Any]),
            wipeNonce: (dict["wipeNonce"] as? NSNumber)?.intValue
        )
    }
}

public struct DeviceMetadata {
    public let deviceId: String
    public let deviceName: String?
    public let model: String?
    public let brand: String?
    public let os: String?
    public let appVersion: String?
    public let isPhysicalDevice: Bool
    public let username: String?
    public let email: String?
    public let phone: String?
    public let customData: [String: Any]?
    public let battery: String?
    public let ram: String?
    public let storage: String?
    public let networkType: String?
    public let usageLogs: [[String: Any]]?
    public let userLogs: [[String: Any]]?
    public let deviceToken: String?
    public let fingerprint: String?
    public let sdkRuntime: String?
    public let sdkVersion: String?
    public let hostPlatform: String?
    public let hostPlatformVersion: String?

    func toPayloadMap() -> [String: Any] {
        var map: [String: Any] = [
            "deviceId": deviceId,
            "isPhysicalDevice": isPhysicalDevice,
        ]
        if let deviceName { map["deviceName"] = deviceName }
        if let model { map["model"] = model }
        if let brand { map["brand"] = brand }
        if let os { map["os"] = os }
        if let appVersion { map["version"] = appVersion }
        if let username { map["username"] = username }
        if let email { map["email"] = email }
        if let phone { map["phone"] = phone }
        if let customData { map["customData"] = customData }
        if let battery { map["battery"] = battery }
        if let ram { map["ram"] = ram }
        if let storage { map["storage"] = storage }
        if let networkType { map["networkType"] = networkType }
        if let usageLogs { map["usageLogs"] = usageLogs }
        if let userLogs { map["userLogs"] = userLogs }
        if let deviceToken { map["deviceToken"] = deviceToken }
        if let fingerprint { map["fingerprint"] = fingerprint }
        if let sdkRuntime { map["sdkRuntime"] = sdkRuntime }
        if let sdkVersion { map["sdkVersion"] = sdkVersion }
        if let hostPlatform { map["hostPlatform"] = hostPlatform }
        if let hostPlatformVersion { map["hostPlatformVersion"] = hostPlatformVersion }
        return map
    }
}

public enum FailSafe {
    case open, closed
}

enum StatusFetchFailure {
    case none, networkError, timeout, signatureMismatch
}

struct StatusFetchResult {
    let response: GuardResponse?
    let failure: StatusFetchFailure
    /// Clamped Retry-After seconds when the server returned 429 (1–60), else nil.
    let retryAfterSeconds: Int?

    init(response: GuardResponse?, failure: StatusFetchFailure, retryAfterSeconds: Int? = nil) {
        self.response = response
        self.failure = failure
        self.retryAfterSeconds = retryAfterSeconds
    }

    var isSignatureMismatch: Bool { failure == .signatureMismatch }
}
