@MainActor
public protocol ChangeGuarding: AnyObject {}

public extension ChangeGuarding {
    func assign<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<Self, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }
}
