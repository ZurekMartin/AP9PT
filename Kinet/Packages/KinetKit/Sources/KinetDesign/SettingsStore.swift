import Foundation

public struct SettingsStore {
    private let defaults: UserDefaults

    public init(_ defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func value<Value>(_ key: String, default fallback: Value) -> Value {
        defaults.object(forKey: key) as? Value ?? fallback
    }

    public func save<Value>(_ value: Value, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
