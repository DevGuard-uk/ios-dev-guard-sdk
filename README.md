# Native iOS DevGuard SDK

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

## Install

Add to your `Podfile`:

```ruby
pod 'DevGuardSDK', '~> 1.0'
```

Then run `pod install`.

## Quick start

```swift
DevGuard.shared.configure(
    projectId: "your_project_id",
    secret: "YOUR_MASTER_SECRET"
)
DevGuard.shared.attachShield(to: window)
```

Sign up at [devguard.uk](https://devguard.uk) for a **Project ID** and **Master Secret**.

## Support

- **Issues:** [GitHub Issues](https://github.com/DevGuard-uk/ios-dev-guard-sdk/issues)
- **Docs:** [devguard.uk/docs](https://devguard.uk/docs)
