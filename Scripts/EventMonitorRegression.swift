// Compile with the four production EventMonitors. Events stay in this test process.
import Cocoa
import Combine

private final class EventSubscriber: Subscriber {
    typealias Input = NSEvent
    typealias Failure = Never
    var subscription: (any Subscription)?
    func receive(subscription: any Subscription) {
        self.subscription = subscription
        subscription.request(.unlimited)
    }
    func receive(_ input: NSEvent) -> Subscribers.Demand { .none }
    func receive(completion: Subscribers.Completion<Never>) { }
}

@main
struct EventMonitorRegression {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        while NSApp.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true) != nil { }
        let mode = CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString)
        var context = CFRunLoopSourceContext(version: 0, info: nil, retain: nil, release: nil,
                                            copyDescription: nil, equal: nil, hash: nil,
                                            schedule: nil, cancel: nil, perform: { _ in })
        let source = CFRunLoopSourceCreate(nil, 0, &context)!
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, mode)
        defer { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, mode) }
        func pumpTrackingLoop() {
            CFRunLoopSourceSignal(source)
            CFRunLoopRunInMode(mode, 0.01, true)
        }
        var received = [NSEvent]()
        let monitor = RunLoopLocalEventMonitor(mask: .mouseMoved, mode: .eventTracking) { event in
            received.append(event)
        }
        monitor.start()
        let ignored = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
                                         timestamp: 1, windowNumber: 0, context: nil, eventNumber: 41, clickCount: 1, pressure: 0)!
        let watched = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [],
                                         timestamp: 2, windowNumber: 0, context: nil, eventNumber: 42, clickCount: 0, pressure: 0)!
        NSApp.postEvent(ignored, atStart: false)
        NSApp.postEvent(watched, atStart: false)
        for _ in 0..<5 { pumpTrackingLoop() }
        assert(received.count == 1 && received[0].timestamp == watched.timestamp,
               "A tracking observer must not repeatedly deliver a pending event (received \(received.count))")
        let first = NSApp.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true)
        assert(first?.type == .rightMouseDown && first?.eventNumber == ignored.eventNumber,
               "An unrelated event must remain first in the queue (got type \(String(describing: first?.type)))")
        let second = NSApp.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true)
        assert(second?.type == .mouseMoved && second?.timestamp == watched.timestamp && second?.eventNumber == watched.eventNumber,
               "Observation must leave the original event available to the tracking control")
        let next = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [],
                                      timestamp: 3, windowNumber: 0, context: nil, eventNumber: 43, clickCount: 0, pressure: 0)!
        NSApp.postEvent(next, atStart: false)
        for _ in 0..<5 { pumpTrackingLoop() }
        assert(received.count == 2 && received.last?.timestamp == next.timestamp,
               "Distinct events must still be delivered after the first queue entry is consumed")
        monitor.stop()
        _ = NSApp.nextEvent(matching: .mouseMoved, until: .distantPast, inMode: .default, dequeue: true)
        NSApp.postEvent(watched, atStart: false)
        pumpTrackingLoop()
        assert(received.count == 2, "A stopped observer must not deliver more events")
        _ = NSApp.nextEvent(matching: .mouseMoved, until: .distantPast, inMode: .default, dequeue: true)
        print("Tracking monitor: one delivery per pending event, untouched queue order and stopped observation passed")

        var observations = 0
        let watcher = UniversalEventMonitor.publisher(for: .mouseMoved).sink { _ in observations += 1 }
        NSApp.sendEvent(watched)
        assert(observations == 1, "A universal publisher must start its monitors when subscribed")
        watcher.cancel()
        NSApp.sendEvent(watched)
        assert(observations == 1, "Cancellation must stop event delivery")

        func checkRelease<P: Publisher>(_ publisher: P, name: String) where P.Output == NSEvent, P.Failure == Never {
            var subscriber: EventSubscriber? = EventSubscriber()
            weak let reference = subscriber
            publisher.receive(subscriber: subscriber!)
            subscriber!.subscription!.cancel()
            subscriber = nil
            assert(reference == nil, "\(name) must release a cancelled subscriber even if it retains its subscription")
        }
        checkRelease(LocalEventMonitor.publisher(for: .mouseMoved), name: "Local event publisher")
        checkRelease(GlobalEventMonitor.publisher(for: .mouseMoved), name: "Global event publisher")
        checkRelease(UniversalEventMonitor.publisher(for: .mouseMoved), name: "Universal event publisher")
        checkRelease(RunLoopLocalEventMonitor.publisher(for: .mouseMoved, mode: .eventTracking), name: "Tracking event publisher")
        print("Monitor lifetimes: local, global, universal and tracking subscriptions release cancelled subscribers")
    }
}
