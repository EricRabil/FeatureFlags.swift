//
//  FlagDomain.swift
//  
//
//  Created by Eric Rabil on 1/28/22.
//

import Foundation

private let FeatureFlagsLock = DispatchSemaphore(value: 1)
internal func FeatureFlagsPerformProtected<P>(_ callback: () -> P) -> P {
    FeatureFlagsLock.wait()
    defer {
        FeatureFlagsLock.signal()
    }
    return callback()
}

private func checkArguments(_ name: String, descriptor: FlagDomainDescriptor, priorityDefault: Bool? = nil, defaultValue: Bool) -> Bool {
    #if !DEBUG
    // Non-debug builds must always evaluate debugging flags to false.
    if case .debugging = descriptor {
        return false
    }
    #endif
    
    if ProcessInfo.processInfo.arguments.contains("--disable-" + name) {
        return false
    } else if ProcessInfo.processInfo.arguments.contains("--enable-" + name) {
        return true
    } else {
        return priorityDefault ?? defaultValue
    }
}

private func boolean(forFlag flag: FeatureFlag, priorityDefault: @autoclosure () -> Bool?) -> Bool {
    return checkArguments(
        flag.key,
        descriptor: flag.domainDescriptor,
        priorityDefault: priorityDefault(),
        defaultValue: flag.defaultValue()
    )
}

private extension FlagDomainDescriptor {
    var key: String {
        switch self {
        case .debugging:
            return "debug-flags"
        case .feature:
            return "feature-flags"
        }
    }
}

@_spi(featureFlagInternals) public class FlagDomain {
    private class NSKVOObserver: NSObject {
        typealias Callback = (NSKVOObserver, String?, Any?, [NSKeyValueChangeKey: Any]?) -> ()
        var callback: Callback?
        
        init(_ callback: @escaping Callback) {
            self.callback = callback
        }
        
        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            callback?(self, keyPath, object, change)
        }
    }
    
    let descriptor: FlagDomainDescriptor
    let suiteName: String
    let suite: UserDefaults
    private var observer: NSKVOObserver?
    
    private init(descriptor: FlagDomainDescriptor, suiteName: String) {
        self.descriptor = descriptor
        self.suiteName = suiteName
        self.suite = UserDefaults(suiteName: suiteName)!
        
        let observer = NSKVOObserver { [weak self] observer, keyPath, object, change in
            guard let self = self else {
                return
            }
            
            guard let newValue = change?[.newKey] as? [String: Any] else {
                return
            }
            
            guard let keyPath = keyPath, keyPath == self.key else {
                return
            }
            
            self.applyKVOUpdate(newValue)
        }
        suite.addObserver(observer, forKeyPath: key, options: [.new], context: nil)
        self.observer = observer
    }
    
    deinit {
        if let observer = observer {
            suite.removeObserver(observer, forKeyPath: key)
        }
    }
    
    @_spi(featureFlagInternals) public var cache: NSMapTable<NSNumber, NSNumber> = .strongToStrongObjects()
    @_spi(featureFlagInternals) public var flags: [String: FeatureFlag] = [:]
    @_spi(featureFlagInternals) public var seenFlags: NSHashTable<NSString> = .init(options: .copyIn)
    
    private func applyKVOUpdate(_ dict: [String: Any]) {
        FeatureFlagsPerformProtected {
            let changedKeys = dict.keys
            let undefinedFlags = flags.filter {
                !changedKeys.contains($0.key)
            }
            
            cache = .strongToStrongObjects()
            
            for (key, value) in dict {
                guard let flag = flags[key] else {
                    continue
                }
                
                if let value = value as? Bool {
                    self[cache: flag] = value
                } else if let flag = flags[key] {
                    self[cache: flag] = boolean(forFlag: flag, priorityDefault: nil)
                }
            }
            
            for flag in undefinedFlags.lazy.map(\.value) {
                self[cache: flag] = boolean(forFlag: flag, priorityDefault: nil)
            }
        }
    }
    
    private var container: [String: Any] {
        get {
            suite.dictionary(forKey: key) ?? [:]
        }
        set {
            FeatureFlagsPerformProtected {
                suite.set(newValue, forKey: key)
            }
        }
    }
    
    subscript (flag: FeatureFlag) -> Bool {
        get {
            let cached = self[cache: flag]
            if _fastPath(cached != nil) {
                return cached!
            }
            return FeatureFlagsPerformProtected {
                if let value = self[cache: flag] {
                    return value
                }
                let boolean = boolean(forFlag: flag, priorityDefault: container[flag.key] as? Bool)
                self[cache: flag] = boolean
                return boolean
            }
        }
        set {
            FeatureFlagsPerformProtected {
                container[flag.key] = newValue
                self[cache: flag] = newValue
            }
        }
    }
}

extension FlagDomain {
    @_spi(featureFlagInternals) public static var cache: NSMapTable<NSNumber, FlagDomain> = .strongToStrongObjects()
    
    static subscript (cache descriptor: Pair<FlagDomainDescriptor, String>) -> FlagDomain? {
        @_transparent get {
            cache.object(forKey: descriptor.hashValue as NSNumber)
        }
        @_transparent set {
            cache.setObject(newValue, forKey: descriptor.hashValue as NSNumber)
        }
    }
}

extension FlagDomain {
    subscript (cache flag: FeatureFlag) -> Bool? {
        @_transparent get {
            cache.object(forKey: flag.hashValue as NSNumber)?.boolValue
        }
        @_transparent set {
            cache.setObject(newValue.map(NSNumber.init(booleanLiteral:)), forKey: flag.hashValue as NSNumber)
        }
    }
}

internal extension FlagDomain {
    static var allDomains: [FlagDomain] {
        cache.objectEnumerator().map { Array($0).compactMap { $0 as? FlagDomain } } ?? []
    }
    
    /// Returns the appropriate domain instance for the given descriptor/suiteName
    static func domain(forDescriptor descriptor: FlagDomainDescriptor, suiteName: String) -> FlagDomain {
        let tuple = Pair.some(descriptor, suiteName)
        let domain = self[cache: tuple]
        if _slowPath(domain == nil) {
            return FeatureFlagsPerformProtected { () -> FlagDomain in
                if let domain = self[cache: tuple] {
                    return domain
                }
                let domain = FlagDomain(descriptor: descriptor, suiteName: suiteName)
                self[cache: tuple] = domain
                return domain
            }
        }
        return domain!
    }
}

internal extension FlagDomain {
    /// An array of all flags this domain has seen
    var discoveredFlags: [FeatureFlag] {
        Array(flags.values)
    }
    
    /// Remove a flag from NSUserDefaults and refreshes the underlying flag value
    func unsetBoolean(forFlag flag: FeatureFlag) {
        FeatureFlagsPerformProtected {
            container.removeValue(forKey: flag.key)
            // reclculate flag without userdefaults
            self[cache: flag] = boolean(forFlag: flag, priorityDefault: nil)
        }
    }
    
    /// Whether a flag has a value in NSUserDefaults
    func flagExistsInDefaults(_ flag: FeatureFlag) -> Bool {
        container.keys.contains(flag.key)
    }
    
    /// Establish a relationship between a flag and domain
    func notice(flag: FeatureFlag) {
        if _slowPath(!seenFlags.contains(flag.key as NSString)) {
            FeatureFlagsPerformProtected {
                if flags[flag.key] != nil {
                    return
                }
                flags[flag.key] = flag
                seenFlags.add(flag.key as NSString)
            }
        }
    }
}

private extension FlagDomain {
    @_transparent var key: String {
        descriptor.key
    }
}

// MARK: - Conformances

extension FlagDomain: Hashable {
    @_spi(featureFlagInternals) public static func == (lhs: FlagDomain, rhs: FlagDomain) -> Bool {
        lhs === rhs
    }
    
    @_spi(featureFlagInternals) public func hash(into hasher: inout Hasher) {
        descriptor.hash(into: &hasher)
        suiteName.hash(into: &hasher)
        key.hash(into: &hasher)
    }
}

