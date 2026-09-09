import Foundation
import UIKit

@objc public final class DevGuard: NSObject {
    @objc public enum FailSafe: Int {
        case open, closed
    }

    @objc public static let shared = DevGuard()

    private var projectId: String?
    private var secret: String?
    private var statusUrl = DevGuardConstants.defaultApiURL
    private var failSafe: FailSafe = .open

    private let storage = SecureStorageService()
    private lazy var cacheService = CacheService(storage: storage, projectId: projectId)
    private lazy var tokenService = DeviceTokenService(storage: storage)
    private lazy var usageLogger = UsageLogger(storage: storage)
    private lazy var userLogBuffer = UserLogBuffer(storage: storage)
    private lazy var syncPolicy = SyncPolicyService(storage: storage)
    private var restClient: RestClient?

    private var heartbeatTimer: Timer?
    private var heartbeatPaused = false
    private var previewModeLocked = false
    private var shieldWindow: UIWindow?

    public private(set) var currentResponse: GuardResponse?
    public var status: LicenseStatus { currentResponse?.status ?? .pending }
    public var isLocked: Bool { status == .locked || status == .expired }

    public var onStatusChanged: ((GuardResponse?) -> Void)?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    @objc public func initialize(
        projectId: String,
        secret: String,
        failSafe: FailSafe = .open,
        statusUrl: String? = nil
    ) {
        self.projectId = projectId
        self.secret = secret
        self.failSafe = failSafe
        guard let effectiveUrl = try? StatusUrlResolver.resolve(statusUrl) else { return }
        self.statusUrl = effectiveUrl
        self.restClient = RestClient(baseUrl: effectiveUrl, secret: secret)

        PluginCrashReporter.configure(
            projectId: projectId,
            secret: secret,
            baseUrl: effectiveUrl,
            metadataProvider: { [weak self] in
                guard let self else { return [:] }
                let hardware = HardwareService(
                    storage: self.storage,
                    tokenService: self.tokenService,
                    usageLogger: self.usageLogger,
                    userLogBuffer: self.userLogBuffer,
                    cachedResponse: self.currentResponse
                )
                return hardware.collect().toPayloadMap()
            }
        )

        Task { await backgroundInit() }
    }

    @objc public func attachShield(to window: UIWindow) {
        shieldWindow = window
        LockScreenPresenter.shared.attach(to: window)
        LockScreenPresenter.shared.render(response: currentResponse)
    }

    /// Example/screenshot helper — injects a mock license response without calling the API.
    public func setPreviewResponse(_ response: GuardResponse) {
        updateResponse(response)
    }

    /// Example/screenshot helper — `active`, `warning`, or `locked`.
    public func applyScreenshotPreview(state: String) {
        previewModeLocked = true
        updateResponse(Self.screenshotMockResponse(for: state))
    }

    /// Call before `initialize` when capturing README screenshots so sync does not overwrite mock UI.
    public func lockPreviewMode() {
        previewModeLocked = true
    }

    private static func screenshotMockResponse(for state: String) -> GuardResponse {
        let branding: [String: Any] = [
            "brandName": "Acme Corp",
            "primaryColor": "#D32F2F",
            "accentColor": "#B71C1C",
            "websiteUrl": "https://devguard.uk",
            "hidePoweredBy": false,
        ]
        switch state.lowercased() {
        case "warning":
            return GuardResponse.fromDict([
                "status": "warning",
                "title": "Payment reminder",
                "message": "Your subscription renews in 3 days. Update billing to avoid interruption.",
                "branding": branding,
            ])
        case "locked":
            return GuardResponse.fromDict([
                "status": "locked",
                "title": "Access suspended",
                "message": "Your license has expired. Contact support to restore access.",
                "contactEmail": "support@example.com",
                "contactPhone": "+15551234567",
                "contactWhatsapp": "+15551234567",
                "allowUnlock": true,
                "branding": branding,
            ])
        default:
            return GuardResponse.fromDict([
                "status": "active",
                "title": "Protected",
                "message": "DevGuard is active.",
                "branding": branding,
            ])
        }
    }

    @objc public func setDeviceUser(
        username: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        customData: [String: Any]? = nil
    ) {
        if let username { storage.write(DevGuardConstants.usernameKey, username) } else { storage.delete(DevGuardConstants.usernameKey) }
        if let email { storage.write(DevGuardConstants.emailKey, email) } else { storage.delete(DevGuardConstants.emailKey) }
        if let phone { storage.write(DevGuardConstants.phoneKey, phone) } else { storage.delete(DevGuardConstants.phoneKey) }
        if let customData, let data = try? JSONSerialization.data(withJSONObject: customData) {
            storage.write(DevGuardConstants.customDataKey, String(data: data, encoding: .utf8) ?? "{}")
        } else {
            storage.delete(DevGuardConstants.customDataKey)
        }
        Task { await syncStatus(forceLogs: true) }
    }

    /// Records a User Journey UI step. Never throws; empty `screen` is ignored.
    /// Uploaded on heartbeat/verify only when `betaFeatures.userJourney` is true.
    @objc public func setUserLog(
        screen: String,
        widget: String? = nil,
        className: String? = nil,
        action: String = "view",
        extras: [String: Any]? = nil
    ) {
        userLogBuffer.log(screen: screen, widget: widget, className: className, action: action, extras: extras)
    }

    @objc public func verify() {
        Task { await syncStatus(force: true) }
    }

    @objc public func unlock(key: String, completion: @escaping (Bool) -> Void) {
        Task {
            let ok = await unlock(key: key)
            completion(ok)
        }
    }

    public func unlock(key: String) async -> Bool {
        guard let projectId else { return false }
        let hashed = NativeBridge.hashSha256Hex(key)
        let ok = await restClient?.verifyAndUnlock(projectId: projectId, hashedKey: hashed) == true
        if ok { await syncStatus(force: true) }
        return ok
    }

    @objc private func appDidBecomeActive() {
        setHeartbeatPaused(false)
        Task { await syncStatus(trigger: "foreground") }
    }

    @objc private func appDidEnterBackground() {
        setHeartbeatPaused(true)
        Task { await syncStatus(trigger: "background") }
    }

    private func backgroundInit() async {
        if previewModeLocked { return }
        let cache = CacheService(storage: storage, projectId: projectId)
        let hardware = HardwareService(storage: storage, tokenService: tokenService, usageLogger: usageLogger, userLogBuffer: userLogBuffer, cachedResponse: currentResponse)

        if hardware.isDeviceCompromised() {
            let code = NativeBridge.evaluatePolicy(blockEmulators: false, isPhysical: true, isCompromised: true)
            if code == PolicyLock.compromised {
                updateResponse(GuardResponse(
                    status: .locked,
                    title: "Security Alert",
                    message: "This device appears to be compromised. Access is restricted.",
                    contactEmail: "", contactPhone: "", contactWhatsapp: "",
                    allowUnlock: false, betaFeatures: [:], extraData: [:], lifecycleSync: nil,
                    remoteCommand: nil, deviceToken: nil, pingInterval: 5,
                    syncPolicy: "immediate", blockEmulators: false, diagnosticPasscodeHash: nil, branding: nil, wipeNonce: nil
                ))
                return
            }
        }

        if let cached = cache.getResponse() {
            updateResponse(cached)
        } else if failSafe == .closed {
            updateResponse(GuardResponse(
                status: .pending, title: nil, message: "Connecting to security server...",
                contactEmail: "", contactPhone: "", contactWhatsapp: "",
                allowUnlock: false, betaFeatures: [:], extraData: [:], lifecycleSync: nil,
                remoteCommand: nil, deviceToken: nil, pingInterval: 5,
                syncPolicy: "immediate", blockEmulators: false, diagnosticPasscodeHash: nil, branding: nil, wipeNonce: nil
            ))
        } else {
            updateResponse(GuardResponse(
                status: .active, title: nil, message: "",
                contactEmail: "", contactPhone: "", contactWhatsapp: "",
                allowUnlock: false, betaFeatures: [:], extraData: [:], lifecycleSync: nil,
                remoteCommand: nil, deviceToken: nil, pingInterval: 5,
                syncPolicy: "immediate", blockEmulators: false, diagnosticPasscodeHash: nil, branding: nil, wipeNonce: nil
            ))
        }

        usageLogger.logEvent("app_open")
        await syncStatus(trigger: "appLaunch")
        startHeartbeat()
    }

    private func syncStatus(force: Bool = false, forceLogs: Bool = false, trigger: String? = nil) async {
        if previewModeLocked { return }
        guard let projectId, let restClient else { return }
        if !force && !syncPolicy.shouldSync(cachedResponse: currentResponse, forceLogs: forceLogs, trigger: trigger) {
            return
        }

        let hardware = HardwareService(storage: storage, tokenService: tokenService, usageLogger: usageLogger, userLogBuffer: userLogBuffer, cachedResponse: currentResponse)
        let metadata = hardware.collect(forceLogs: forceLogs, trigger: trigger)
        let compromised = hardware.isDeviceCompromised()
        let result = await restClient.fetchStatus(projectId: projectId, metadata: metadata)

        if result.isSignatureMismatch {
            PluginCrashReporter.report(
                error: NSError(domain: "DevGuard", code: 1, userInfo: [NSLocalizedDescriptionKey: "Server response signature mismatch"]),
                context: "syncStatus",
                crashType: "sdk_internal"
            )
            updateResponse(GuardResponse(
                status: .locked, title: "Security Alert",
                message: "Server response could not be verified. Access restricted.",
                contactEmail: "", contactPhone: "", contactWhatsapp: "",
                allowUnlock: false, betaFeatures: [:], extraData: [:], lifecycleSync: nil,
                remoteCommand: nil, deviceToken: nil, pingInterval: 5,
                syncPolicy: "immediate", blockEmulators: false, diagnosticPasscodeHash: nil, branding: nil, wipeNonce: nil
            ))
            return
        }

        guard let fresh = result.response else { return }
        await handleRemoteCommand(fresh.remoteCommand)
        if let token = fresh.deviceToken { tokenService.saveToken(token) }

        let enforced = GuardEnforcement.apply(fresh, metadata: metadata, isCompromised: compromised)
        updateResponse(enforced)
        CacheService(storage: storage, projectId: projectId).saveResponse(enforced)
        syncPolicy.recordSuccessfulSync()

        if metadata.usageLogs?.isEmpty == false { usageLogger.clearLogs() }
        if metadata.userLogs?.isEmpty == false { userLogBuffer.clearLogs() }
    }

    private func handleRemoteCommand(_ command: String?) async {
        guard let command, command != "none" else { return }
        switch command {
        case "syncLogs": await syncStatus(force: true, forceLogs: true)
        case "clearLogs":
            usageLogger.clearLogs()
            userLogBuffer.clearLogs()
        case "wipeCache": CacheService(storage: storage, projectId: projectId).clear()
        case "revokeToken": tokenService.clearToken()
        default: break
        }
    }

    private func startHeartbeat() {
        if heartbeatPaused { return }
        heartbeatTimer?.invalidate()
        let response = currentResponse
        let fallbackMinutes: Int = {
            if let hours = response?.lifecycleSync?["fallbackIntervalHours"] as? NSNumber {
                return hours.intValue * 60
            }
            return response?.pingInterval ?? 5
        }()
        let jitter = response?.lifecycleSync.flatMap { ($0["jitterMaxMinutes"] as? NSNumber)?.intValue } ?? 0
        let jitterOffset = jitter > 0 ? Int(Date().timeIntervalSince1970) % jitter : 0
        let interval = max(Double(fallbackMinutes + jitterOffset), 1) * 60

        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self, !self.heartbeatPaused else { return }
            Task { await self.syncStatus(trigger: "heartbeat") }
        }
    }

    private func setHeartbeatPaused(_ paused: Bool) {
        heartbeatPaused = paused
        if paused {
            heartbeatTimer?.invalidate()
            heartbeatTimer = nil
        } else if heartbeatTimer == nil {
            startHeartbeat()
        }
    }

    private func updateResponse(_ response: GuardResponse?) {
        let previous = currentResponse
        currentResponse = response
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.handleBetaFeatures(previous: previous, response: response)
            self.onStatusChanged?(response)
            LockScreenPresenter.shared.render(response: response)
        }
    }

    private func handleBetaFeatures(previous: GuardResponse?, response: GuardResponse?) {
        guard let response else { return }
        if response.status == .warning,
           response.betaFeatures["vibrateOnWarning"] as? Bool == true,
           previous?.status != .warning {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        let wipeVal = response.betaFeatures["wipeNonce"]
        let nonce: Int? = {
            if let n = wipeVal as? NSNumber { return n.intValue }
            if let s = wipeVal as? String { return Int(s) }
            return response.wipeNonce
        }()
        if let nonce, nonce > 0 {
            Task { await executeRemoteWipe(nonce: nonce) }
        }
    }

    private func executeRemoteWipe(nonce: Int) async {
        let cache = CacheService(storage: storage, projectId: projectId)
        let last = cache.getLastWipeNonce()
        if let last, nonce <= last { return }
        RemoteWipeService(cache: cache, usageLogger: usageLogger, userLogBuffer: userLogBuffer, storage: storage, tokenService: tokenService).execute()
        cache.setLastWipeNonce(nonce)
    }

    private func sha256(_ input: String) -> String {
        NativeBridge.hashSha256Hex(input)
    }
}
