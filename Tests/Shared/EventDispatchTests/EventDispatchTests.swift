import Testing
@testable import EventDispatch

private struct Ping: PublishedEvent {
    static let eventType = "Ping"
    static let version = 1
    let n: Int
}

@Test func dispatchReachesSubscribersOfThatTypeOnly() {
    let dispatcher = EventDispatcher()
    var received: [Int] = []
    dispatcher.subscribe(Ping.self) { received.append($0.n) }
    dispatcher.dispatch([Ping(n: 1), Ping(n: 2)])
    #expect(received == [1, 2])
}
