# Changelog

## [1.0.1] - 2026-11-26

### Added
- **Root / jailbreak policy** (`rootPolicy`): heartbeat-driven `warn` (default banner) or `block` (lock) when the device is compromised. Emulator blocking via project settings is unchanged.
- **User Journey** (`DevGuard.shared.setUserLog`): optional compact UI-step trail for Developer Portal and Console. Uploaded on heartbeat only when the project plan includes User Journey.

## [1.0.0] - 2026-06-26

### Added

- Initial public release of the native iOS licensing SDK (`DevGuardSDK` CocoaPod).
- HMAC-signed verify, gzip secure tunnel, premium lock screen, heartbeat sync, and remote wipe.
- Built-in plugin crash telemetry and `statusUrl` domain validation for API overrides.
- Vendored `devguard_core` xcframework with native security hardening.
