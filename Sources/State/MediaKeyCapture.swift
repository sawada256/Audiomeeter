import AppKit

/// The synchronous WindowServer event tap must never depend on the UI run loop.
/// Only volume media-key events are consumed; mouse events are always forwarded.
final class MediaKeyCapture: @unchecked Sendable {
    enum Status { case starting, ready, unavailable, stopped }
    private let lock = NSLock()
    private var active = true
    private var currentStatus = Status.starting
    private var loop: CFRunLoop?
    private let action: (MixerHotkeyAction) -> Void
    // Owned exclusively by the capture thread.
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var status: Status { lock.lock(); defer { lock.unlock() }; return currentStatus }
    private var isActive: Bool { lock.lock(); defer { lock.unlock() }; return active }
    init(action: @escaping (MixerHotkeyAction) -> Void) {
        self.action = action
        let thread = Thread { [self] in run() }
        thread.name = "Audiomeeter volume keys"
        thread.qualityOfService = .userInteractive
        thread.start()
    }
    func stop() {
        lock.lock(); active = false; currentStatus = .stopped; let runningLoop = loop; lock.unlock()
        if let runningLoop {
            CFRunLoopPerformBlock(runningLoop, CFRunLoopMode.defaultMode.rawValue) { CFRunLoopStop(runningLoop) }
            CFRunLoopWakeUp(runningLoop)
        }
    }
    private func setStatus(_ value: Status) {
        lock.lock(); if active { currentStatus = value }; lock.unlock()
    }
    private func run() {
        autoreleasepool {
            let runningLoop = CFRunLoopGetCurrent()!
            lock.lock(); loop = runningLoop; let shouldRun = active; lock.unlock()
            guard shouldRun else { return }
            connect()
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.checkCapture() }
            RunLoop.current.add(timer, forMode: .default)
            // A stop may arrive between startup and entering the run loop.
            if isActive { CFRunLoopRun() }
            timer.invalidate()
            disconnect()
            lock.lock(); loop = nil; currentStatus = .stopped; lock.unlock()
        }
    }
    private func disconnect() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode) }
        source = nil; tap = nil
    }
    private func connect() {
        guard isActive else { return }
        disconnect()
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(1 << 14), callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return Unmanaged<MediaKeyCapture>.fromOpaque(context).takeUnretainedValue().receive(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { setStatus(.unavailable); return }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        guard let source else { disconnect(); setStatus(.unavailable); return }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        CGEvent.tapEnable(tap: tap, enable: true)
        setStatus(CGEvent.tapIsEnabled(tap: tap) ? .ready : .unavailable)
    }
    private func checkCapture() {
        guard isActive else { CFRunLoopStop(CFRunLoopGetCurrent()); return }
        if let tap, CFMachPortIsValid(tap) {
            if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            setStatus(CGEvent.tapIsEnabled(tap: tap) ? .ready : .unavailable)
        } else { connect() }
    }
    private func receive(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isActive else { return Unmanaged.passUnretained(event) }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == 14, let ns = NSEvent(cgEvent: event),
              MixerMediaKey.shouldConsume(eventType: type.rawValue, subtype: ns.subtype.rawValue, data: ns.data1) else { return Unmanaged.passUnretained(event) }
        if let keyAction = MixerMediaKey.action(ns.data1) { action(keyAction) }
        return nil
    }
}
