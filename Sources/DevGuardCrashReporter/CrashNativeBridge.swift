import Foundation

enum CrashReporterConstants {
    static let defaultApiURL = "https://api.devguard.uk/devguard"
    static let hdrSig = "X-DevGuard-Signature"
    static let hdrTs = "X-DevGuard-Timestamp"
    static let hdrApiKey = "X-DevGuard-Api-Key"
}

enum CrashNativeBridge {
    static func generateSignature(projectId: String, timestamp: Int64) -> String {
        var output = [CChar](repeating: 0, count: 65)
        projectId.withCString { ptr in
            dg_x9(ptr, timestamp, &output)
        }
        return String(cString: output)
    }
}

public enum SdkIdentity {
    public static let sdkRuntime = "native_ios"
    public static let sdkVersion = "1.0.0"
}
