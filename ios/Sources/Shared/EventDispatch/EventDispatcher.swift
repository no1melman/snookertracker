import Foundation

/// A published (Stage 2) event. `version` is part of the contract (spec 002).
public protocol PublishedEvent: Sendable {
    static var eventType: String { get }
    static var version: Int { get }
}

/// In-process dispatcher: use cases call `dispatch` after a successful save.
public final class EventDispatcher: @unchecked Sendable {
    private var handlers: [ObjectIdentifier: [(any PublishedEvent) -> Void]] = [:]
    private let lock = NSLock()

    public init() {}

    public func subscribe<E: PublishedEvent>(_ type: E.Type, _ handler: @escaping (E) -> Void) {
        lock.withLock {
            handlers[ObjectIdentifier(type), default: []].append { event in
                if let e = event as? E { handler(e) }
            }
        }
    }

    public func dispatch(_ events: [any PublishedEvent]) {
        for event in events {
            let subs = lock.withLock { handlers[ObjectIdentifier(Swift.type(of: event))] ?? [] }
            subs.forEach { $0(event) }
        }
    }
}
