import Foundation

public protocol FlagProvider {
    var suiteName: String { get }
}

public extension FlagProvider {
    var allFlags: [FeatureFlag] {
        FeatureFlag.allFlags(inSuiteName: suiteName)
    }
    
    @inlinable @inline(__always) func `if`(_ keyPath: KeyPath<Self, Bool>, _ expr: @autoclosure () -> ()) {
        guard self[keyPath: keyPath] else {
            return
        }
        expr()
    }
    
    @inlinable @inline(__always) func `if`<P>(_ keyPath: KeyPath<Self, Bool>, _ expr: @autoclosure () -> P, or: @autoclosure () -> P) -> P {
        guard self[keyPath: keyPath] else {
            return or()
        }
        return expr()
    }
    
    @inlinable @inline(__always) func ifNot<P>(_ keyPath: KeyPath<Self, Bool>, _ expr: @autoclosure () -> P, else: @autoclosure () -> P) -> P {
        guard !self[keyPath: keyPath] else {
            return `else`()
        }
        return expr()
    }
}

public enum FlagDomainDescriptor: CaseIterable {
    case feature, debugging
}

@propertyWrapper
public struct FeatureFlag: Hashable {
    public static func == (lhs: FeatureFlag, rhs: FeatureFlag) -> Bool {
        lhs.key == rhs.key
        && lhs.domainDescriptor == rhs.domainDescriptor
        && lhs.defaultValue() == rhs.defaultValue()
    }
    
    public func hash(into hasher: inout Hasher) {
        key.hash(into: &hasher)
        domainDescriptor.hash(into: &hasher)
        defaultValue().hash(into: &hasher)
    }
    
    @_transparent private static func domain(forFlag flag: FeatureFlag, suiteName: String) -> FlagDomain {
        let domain = FlagDomain.domain(forDescriptor: flag.domainDescriptor, suiteName: suiteName)
        domain.notice(flag: flag)
        return domain
    }
    
    /// Returns all discovered flags for a given suite name. This will not return flags that have never been read yet, as flags are evaluated lazily.
    public static func allFlags(inSuiteName suiteName: String) -> [FeatureFlag] {
        return FlagDomainDescriptor.allCases.flatMap { descriptor in
            FlagDomain.domain(forDescriptor: descriptor, suiteName: suiteName).discoveredFlags
        }
    }
    
    public static subscript<T: FlagProvider>(
        _enclosingInstance instance: T,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, Bool>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
    ) -> Bool {
        get {
            let flag = instance[keyPath: storageKeyPath]
            let domain = domain(forFlag: flag, suiteName: instance.suiteName)
            return domain[flag]
        }
        set {
            let flag = instance[keyPath: storageKeyPath]
            let domain = domain(forFlag: flag, suiteName: instance.suiteName)
            domain[flag] = newValue
        }
    }
        
    @available(*, unavailable,
        message: "This property wrapper can only be applied to classes"
    )
    public var wrappedValue: Bool {
        get { fatalError() }
        set { fatalError() }
    }
    
    /// The identifier for this feature flag
    public let key: String
    /// The descriptor for this flag - using the debugging domain will always evaluate to false in non-debug builds.
    public let domainDescriptor: FlagDomainDescriptor
    /// The value of the flag when it is not defined as an argument or in defaults
    public let defaultValue: () -> Bool
    
    public init(_ key: String, domain: FlagDomainDescriptor = .feature, defaultValue: @autoclosure @escaping () -> Bool) {
        self.key = key
        self.domainDescriptor = domain
        self.defaultValue = defaultValue
    }
    
    private func domain(forSuite suiteName: String) -> FlagDomain {
        Self.domain(forFlag: self, suiteName: suiteName)
    }
    
    public func value(inSuite suiteName: String) -> Bool {
        domain(forSuite: suiteName)[self]
    }
    
    public func setValue(_ boolean: Bool, inSuite suiteName: String) {
        domain(forSuite: suiteName)[self] = boolean
    }
    
    public func unset(inSuite suiteName: String) {
        domain(forSuite: suiteName).unsetBoolean(forFlag: self)
    }
    
    public func isDefined(inSuiteName suiteName: String) -> Bool {
        domain(forSuite: suiteName).flagExistsInDefaults(self)
    }
}
