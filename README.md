# Native iOS DevGuard SDK

<p align="center">
  <a href="https://devguard.uk">
    <img src="assets/logo.png" alt="DevGuard" width="120" height="120" />
  </a>
</p>

<p align="center">
  <a href="https://devguard.uk"><img src="https://img.shields.io/badge/website-devguard.uk-6C47FF?style=flat-square" alt="Website" /></a>
  <a href="https://github.com/DevGuard-uk/ios-dev-guard-sdk"><img src="https://img.shields.io/badge/github-DevGuard--uk-181717?style=flat-square" alt="GitHub" /></a>
  <img src="https://img.shields.io/badge/platform-iOS-000000?style=flat-square" alt="iOS" />
  <img src="https://img.shields.io/badge/pod-DevGuardSDK-2D7DD2?style=flat-square" alt="CocoaPods" />
  <img src="https://img.shields.io/badge/license-MIT-3CB371?style=flat-square" alt="License" />
</p>

Swift CocoaPod for native iOS applications: **`DevGuardSDK`**.

Public repository: [github.com/DevGuard-uk/ios-dev-guard-sdk](https://github.com/DevGuard-uk/ios-dev-guard-sdk)

## Features

- Same DevGuard protocol as Flutter and React Native plugins
- Native `devguard_core` cryptography (vendored xcframework)
- Premium lock screen via `attachShield(to:)`
- Heartbeat + lifecycle sync (pauses in background)
- Remote wipe, compromised-device policy, branding footer
- Objective-C compatible `DevGuard.shared` API
- Built-in plugin crash telemetry
- `setUserLog` for Developer Portal → User Journey (plan-gated upload)

## Install

Add to your `Podfile`:

```ruby
pod 'DevGuardSDK', '~> 1.0'
```

Then run `pod install`.

## Quick start

```swift
DevGuard.shared.initialize(
    projectId: "your_project_id",
    secret: "YOUR_MASTER_SECRET"
)
DevGuard.shared.attachShield(to: window)
```

Optional User Journey step:

```swift
DevGuard.shared.setUserLog(
    screen: "cart-page",
    widget: "CheckoutCTA",
    className: "CartViewController",
    action: "view"
)
```

Sign up at [devguard.uk](https://devguard.uk) for a **Project ID** and **Master Secret**.

## Support

- **Issues:** [GitHub Issues](https://github.com/DevGuard-uk/ios-dev-guard-sdk/issues)
- **Docs:** [devguard.uk/docs](https://devguard.uk/docs)
