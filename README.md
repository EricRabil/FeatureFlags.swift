# FeatureFlags.swift
Tools for easily defining feature flags for your projects

- Integrates with NSUserDefaults and automatically refreshes when defaults are changed, no need to restart your program
- Override flags by passing `--(enable|disable)-${flagName}`
- Create flags that are only used in debugging, and know that they will always be false in production builds

```swift
import FeatureFlags

// to enable something off by default, --enable-
// to disable, --disable-
public class _CBFeatureFlags: FlagProvider {
    public let suiteName = "com.ericrabil.barcelona"
    
    @FeatureFlag("matrix-audio", defaultValue: false)
    public var permitAudioOverMautrix: Bool
    
    @FeatureFlag("internal-diagnostics", defaultValue: isDebugBuild)
    public var internalDiagnostics: Bool
    
    @FeatureFlag("xcode", domain: .debugging, defaultValue: false)
    public var runningFromXcode: Bool
    
    @FeatureFlag("any-country", defaultValue: false)
    public var ignoresSameCountryCodeAssertion: Bool
    
    @FeatureFlag("scratchbox", domain: .debugging, defaultValue: false)
    public var scratchbox: Bool
    
    @FeatureFlag("exit-after-scratchbox", domain: .debugging, defaultValue: true)
    public var exitAfterScratchbox: Bool
    
    @FeatureFlag("contact-fuzz-enumerator", defaultValue: true)
    public var contactFuzzEnumerator: Bool
    
    @FeatureFlag("sms-read-buffer", defaultValue: true)
    public var useSMSReadBuffer: Bool
    
    @FeatureFlag("drop-spam-messages", defaultValue: true)
    public var dropSpamMessages: Bool
    
    @FeatureFlag("log-sensitive-payloads", defaultValue: isDebugBuild)
    public var logSensitivePayloads: Bool
}
```
