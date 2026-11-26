Pod::Spec.new do |s|
  s.name             = 'DevGuardSDK'
  s.version          = '1.0.0'
  s.summary          = 'DevGuard native iOS SDK for license protection and security telemetry.'
  s.description      = 'Integrate DevGuard directly into Swift and Objective-C iOS applications.'
  s.homepage         = 'https://github.com/DevGuard-uk/ios-dev-guard-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'DevGuard UK' => 'support@devguard.uk' }
  s.source           = { :git => 'https://github.com/DevGuard-uk/ios-dev-guard-sdk.git', :tag => "v#{s.version}" }
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.9'
  s.source_files     = 'Sources/DevGuardSDK/**/*.{swift,h}'
  s.public_header_files = 'Sources/DevGuardSDK/Core/devguard_core.h'
  s.vendored_frameworks = 'Frameworks/devguard_core.xcframework'
  s.frameworks       = 'UIKit', 'Security'
  s.libraries        = 'z'
  s.module_name      = 'DevGuardSDK'
  # Capture-only pod; DevGuardCrashSink owns Admin upload + signing.
  s.dependency 'iOSCrashReporter', '~> 1.0'
end
