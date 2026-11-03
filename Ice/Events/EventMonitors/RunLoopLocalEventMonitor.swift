//
//  RunLoopLocalEventMonitor.swift
//  Ice
//

import Cocoa
import Combine

/// Observes native tracking events without removing them from AppKit's queue.
final class RunLoopLocalEventMonitor {
    private let runLoop = CFRunLoopGetCurrent()
    private let mode: RunLoop.Mode
    private let observer: CFRunLoopObserver

    /// Creates an event monitor with the given event type mask and handler.
    ///
    /// - Parameters:
    ///   - mask: An event type mask specifying which events to monitor.
    ///   - handler: A handler to execute when the event monitor receives
    ///     an event corresponding to the event types in `mask`.
    init(
        mask: NSEvent.EventTypeMask,
        mode: RunLoop.Mode,
        handler: @escaping (_ event: NSEvent) -> Void
    ) {
        self.mode = mode
        var lastEvent: (NSEvent.EventType, TimeInterval, Int, NSEvent.ModifierFlags)?
        self.observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity.beforeSources.rawValue,
            true,
            0
        ) { _, _ in
            // Reposting wakes nested tracking loops before the control can consume its event.
            guard let event = NSApp.nextEvent(matching: mask, until: .distantPast, inMode: mode, dequeue: false) else {
                lastEvent = nil
                return
            }
            // Peeking can return a new NSEvent wrapper for the same queued event.
            let identity = (event.type, event.timestamp, event.windowNumber, event.modifierFlags)
            if let lastEvent, lastEvent == identity { return }
            lastEvent = identity
            handler(event)
        }
    }

    deinit {
        stop()
    }

    func start() {
        CFRunLoopAddObserver(
            runLoop,
            observer,
            CFRunLoopMode(mode.rawValue as CFString)
        )
    }

    func stop() {
        CFRunLoopRemoveObserver(
            runLoop,
            observer,
            CFRunLoopMode(mode.rawValue as CFString)
        )
    }
}

extension RunLoopLocalEventMonitor {
    /// A publisher that emits local events for an event type mask.
    struct RunLoopLocalEventPublisher: Publisher {
        typealias Output = NSEvent
        typealias Failure = Never

        let mask: NSEvent.EventTypeMask
        let mode: RunLoop.Mode

        func receive<S: Subscriber<Output, Failure>>(subscriber: S) {
            let subscription = RunLoopLocalEventSubscription(mask: mask, mode: mode, subscriber: subscriber)
            subscriber.receive(subscription: subscription)
        }
    }

    /// Returns a publisher that emits local events for the given event type mask.
    ///
    /// - Parameter mask: An event type mask specifying which events to publish.
    static func publisher(for mask: NSEvent.EventTypeMask, mode: RunLoop.Mode) -> RunLoopLocalEventPublisher {
        RunLoopLocalEventPublisher(mask: mask, mode: mode)
    }
}

extension RunLoopLocalEventMonitor.RunLoopLocalEventPublisher {
    private final class RunLoopLocalEventSubscription<S: Subscriber<Output, Failure>>: Subscription {
        private let mask: NSEvent.EventTypeMask
        private let mode: RunLoop.Mode
        private var subscriber: S?
        private lazy var monitor = RunLoopLocalEventMonitor(mask: mask, mode: mode) { [weak self] event in
            _ = self?.subscriber?.receive(event)
        }

        init(mask: NSEvent.EventTypeMask, mode: RunLoop.Mode, subscriber: S) {
            self.mask = mask
            self.mode = mode
            self.subscriber = subscriber
            monitor.start()
        }

        func request(_ demand: Subscribers.Demand) { }

        func cancel() {
            monitor.stop()
            subscriber = nil
        }
    }
}
