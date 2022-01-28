//
//  FlagDomain.swift
//  
//
//  Created by Eric Rabil on 1/28/22.
//

import Foundation

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
        defaultValue: flag.defaultValue
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

internal class FlagDomain {
    private class NSKVOObserver: NSObject {
        typealias Callback = (String?, Any?, [NSKeyValueChangeKey: Any]?) -> ()
        var callback: Callback
        
        init(_ callback: @escaping Callback) {
            self.callback = callback
        }
        
        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            callback(keyPath, object, change)
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
        
        let observer = NSKVOObserver { keyPath, object, change in
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
    
    private var cache: [FeatureFlag: Bool] = [:]
    private var flags: [String: FeatureFlag] = [:]
    
    private func applyKVOUpdate(_ dict: [String: Any]) {
        let changedKeys = dict.keys
        let undefinedFlags = cache.keys.filter {
            !changedKeys.contains($0.key)
        }
        
        cache = [:]
        
        for (key, value) in dict {
            guard let flag = flags[key] else {
                continue
            }
            
            if let value = value as? Bool {
                cache[flag] = value
            } else if let flag = flags[key] {
                cache[flag] = boolean(forFlag: flag, priorityDefault: nil)
            }
        }
        
        for flag in undefinedFlags {
            cache[flag] = boolean(forFlag: flag, priorityDefault: nil)
        }
    }
    
    private var container: [String: Any] {
        get {
            suite.dictionary(forKey: key) ?? [:]
        }
        set {
            suite.set(newValue, forKey: key)
        }
    }
    
    subscript (flag: FeatureFlag) -> Bool {
        get {
            if _slowPath(!cache.keys.contains(flag)) {
                let boolean = boolean(forFlag: flag, priorityDefault: container[flag.key] as? Bool)
                cache[flag] = boolean
                return boolean
            }
            return cache[flag]!
        }
        set {
            container[flag.key] = newValue
            cache[flag] = newValue
        }
    }
}

internal extension FlagDomain {
    private static var cache: [Pair<FlagDomainDescriptor, String>: FlagDomain] = [:]
    
    static var allDomains: [FlagDomain] {
        Array(cache.values)
    }
    
    /// Returns the appropriate domain instance for the given descriptor/suiteName
    static func domain(forDescriptor descriptor: FlagDomainDescriptor, suiteName: String) -> FlagDomain {
        let tuple = Pair.some(descriptor, suiteName)
        if _slowPath(!cache.keys.contains(tuple)) {
            let domain = FlagDomain(descriptor: descriptor, suiteName: suiteName)
            cache[tuple] = domain
            return domain
        }
        return cache[tuple]!
    }
}

internal extension FlagDomain {
    /// An array of all flags this domain has seen
    var discoveredFlags: [FeatureFlag] {
        Array(flags.values)
    }
    
    /// Remove a flag from NSUserDefaults and refreshes the underlying flag value
    func unsetBoolean(forFlag flag: FeatureFlag) {
        container.removeValue(forKey: flag.key)
        // reclculate flag without userdefaults
        cache[flag] = boolean(forFlag: flag, priorityDefault: nil)
    }
    
    /// Whether a flag has a value in NSUserDefaults
    func flagExistsInDefaults(_ flag: FeatureFlag) -> Bool {
        container.keys.contains(flag.key)
    }
    
    /// Establish a relationship between a flag and domain
    func notice(flag: FeatureFlag) {
        if _slowPath(!flags.keys.contains(flag.key)) {
            flags[flag.key] = flag
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
    static func == (lhs: FlagDomain, rhs: FlagDomain) -> Bool {
        lhs === rhs
    }
    
    func hash(into hasher: inout Hasher) {
        descriptor.hash(into: &hasher)
        suiteName.hash(into: &hasher)
        key.hash(into: &hasher)
    }
}

