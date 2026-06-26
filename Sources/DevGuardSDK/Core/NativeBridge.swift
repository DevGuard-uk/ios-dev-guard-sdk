import Foundation
import Compression
import UIKit

enum PolicyLock {
    static let allow = 0
    static let emulator = 1
    static let compromised = 2
}

enum DevGuardConstants {
    static var defaultApiURL: String { StatusUrlResolver.defaultApiURL }
    static let cacheKey = "dev_guard_cache_response"
    static let wipeNonceKey = "dev_guard_wipe_nonce"
    static let tokenKey = "dev_guard_device_token"
    static let fingerprintKey = "dev_guard_fingerprint"
    static let lastSyncKey = "dev_guard_last_sync"
    static let usageLogsKey = "dev_guard_usage_logs"
    static let usernameKey = "dev_guard_username"
    static let emailKey = "dev_guard_email"
    static let phoneKey = "dev_guard_phone"
    static let customDataKey = "dev_guard_custom_data"
    static let tunnelV1 = "v1-gzip"
    static let hdrSig = "X-DevGuard-Signature"
    static let hdrTs = "X-DevGuard-Timestamp"
    static let hdrTunnel = "X-DevGuard-Tunnel"
    static let hdrApiKey = "X-DevGuard-Api-Key"
    static let respSig = "X-DevGuard-Response-Signature"
}

enum NativeBridge {
    static func generateSignature(projectId: String, timestamp: Int64) -> String {
        var output = [CChar](repeating: 0, count: 65)
        projectId.withCString { ptr in
            dg_x9(ptr, timestamp, &output)
        }
        return String(cString: output)
    }

    static func verifyResponse(responseBody: String, signature: String) -> Bool {
        let result = responseBody.withCString { bodyPtr in
            signature.withCString { sigPtr in
                dg_v2(bodyPtr, sigPtr)
            }
        }
        return result == 1
    }

    static func secureSaveToken(_ token: String) -> String {
        var output = [CChar](repeating: 0, count: 512)
        token.withCString { dg_s3($0, &output) }
        return String(cString: output)
    }

    static func secureGetToken(_ scrambled: String) -> String {
        var output = [CChar](repeating: 0, count: 512)
        scrambled.withCString { dg_g4($0, &output) }
        return String(cString: output)
    }

    static func hashSha256Hex(_ input: String) -> String {
        var output = [CChar](repeating: 0, count: 65)
        input.withCString { dg_h5($0, &output) }
        return String(cString: output)
    }

    static func xorTransform(_ bytes: [UInt8], key: [UInt8]) -> [UInt8] {
        var output = [CChar](repeating: 0, count: bytes.count + 1)
        bytes.withUnsafeBufferPointer { inputPtr in
            key.withUnsafeBufferPointer { keyPtr in
                inputPtr.baseAddress?.withMemoryRebound(to: CChar.self, capacity: bytes.count) { inputChar in
                    keyPtr.baseAddress?.withMemoryRebound(to: CChar.self, capacity: key.count) { keyChar in
                        dg_x6(inputChar, bytes.count, keyChar, key.count, &output)
                    }
                }
            }
        }
        return Array(UnsafeBufferPointer(start: output, count: bytes.count)).map { UInt8(bitPattern: $0) }
    }

    static func evaluatePolicy(blockEmulators: Bool, isPhysical: Bool, isCompromised: Bool) -> Int {
        Int(dg_e1(blockEmulators ? 1 : 0, isPhysical ? 1 : 0, isCompromised ? 1 : 0))
    }

    static func getTotalRamMb() -> Int {
        Int(dg_r8())
    }

    static func defaultStatusUrl() -> String {
        var output = [CChar](repeating: 0, count: 128)
        dg_u1(&output)
        return String(cString: output)
    }

    static func isAllowedStatusUrl(_ url: String) -> Bool {
        url.withCString { dg_u2($0) == 1 }
    }
}
