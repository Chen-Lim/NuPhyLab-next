// Adapted from apps/macos/Sources/Chord/Input/IntentTapRunLoop.swift.
// Standalone single-selection extraction; see source-provenance.json for changes and hashes.
import CoreGraphics
import Foundation

/// Owns one tap lifetime. No callback waits for Main; stopping wakes this loop
/// and retains the receiver/userInfo until the worker has removed its source.
final class IntentTapRunLoop: @unchecked Sendable {
    private let lock = NSLock()
    private var loop: CFRunLoop?
    private var tap: CFMachPort?
    private var stopping = false
    private var running = false
    private var startupFailure: IntentMonitorFailure?
    private let receiver: IntentBindingReceiver
    private let context: IntentTapCallbackContext
    private let preview: Bool
    init(receiver: IntentBindingReceiver, preview: Bool = false) { self.receiver = receiver; self.context = IntentTapCallbackContext(receiver: receiver); self.preview = preview }

    func start() throws {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            autoreleasepool {
                let current = CFRunLoopGetCurrent()!
                let port: CFMachPort?
                let source: CFRunLoopSource?
                if preview {
                    port = nil
                    var context = CFRunLoopSourceContext()
                    context.perform = { _ in }
                    source = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context)
                } else {
                    let types: [CGEventType] = [CGEventType(rawValue: 14)!, .flagsChanged, .keyDown, .keyUp, .otherMouseDown, .otherMouseDragged, .otherMouseUp, .mouseMoved]
                    let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
                    port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                            eventsOfInterest: mask, callback: intentThreadedBindingCallback,
                                            userInfo: Unmanaged.passUnretained(context).toOpaque())
                    source = port.flatMap { CFMachPortCreateRunLoopSource(kCFAllocatorDefault, $0, 0) }
                }
                guard let source else {
                    if let port { CFMachPortInvalidate(port) }
                    lock.lock(); startupFailure = port == nil ? .createFailed : .sourceFailed; lock.unlock()
                    ready.signal(); return
                }
                CFRunLoopAddSource(current, source, .commonModes)
                if let port { CGEvent.tapEnable(tap: port, enable: true) }
                lock.lock(); loop = current; tap = port; running = true; lock.unlock()
                ready.signal()
                CFRunLoopRun()
                if let port { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
                CFRunLoopRemoveSource(current, source, .commonModes)
                CFRunLoopSourceInvalidate(source)
                lock.lock(); loop = nil; tap = nil; running = false; lock.unlock()
            }
        }
        thread.name = "LabSelection.IntentEventTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        // Only initial OS setup is joined. Stop never waits for Main or joins a
        // worker callback, and callback delivery is always asynchronous to Main.
        ready.wait()
        lock.lock(); let failure = startupFailure; lock.unlock()
        if let failure { throw failure }
    }
    var isHealthy: Bool {
        lock.lock(); defer { lock.unlock() }
        guard running, !stopping else { return false }
        return preview || tap.map { CGEvent.tapIsEnabled(tap: $0) } == true
    }
    func stop() {
        context.invalidate()
        lock.lock()
        guard !stopping, let loop else { lock.unlock(); return }
        stopping = true
        lock.unlock()
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { CFRunLoopStop(loop) }
        CFRunLoopWakeUp(loop)
    }
    #if DEBUG
    @discardableResult func receivePreview(_ type: CGEventType, event: CGEvent, completed: @escaping (Bool) -> Void) -> Bool {
        performPreview { [context] in
            let result = intentThreadedBindingCallback(OpaquePointer(bitPattern: 1)!, type, event, Unmanaged.passUnretained(context).toOpaque())
            if let result, result.takeUnretainedValue() !== event { result.release() }
            completed(result == nil)
        }
    }
    @discardableResult func performPreview(_ action: @escaping () -> Void) -> Bool {
        lock.lock()
        guard preview, running, !stopping, let loop else { lock.unlock(); return false }
        lock.unlock()
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { [self] in
            lock.lock(); let permitted = running && !stopping; lock.unlock()
            if permitted { autoreleasepool(invoking: action) }
        }
        CFRunLoopWakeUp(loop)
        return true
    }
    #endif
}

/// Lifetime gate is checked in the same lock as receiver mutation. Stopping an
/// old worker synchronously revokes its callback authority before a new worker
/// can share the receiver, without waiting for Main or joining the thread.
final class IntentTapCallbackContext {
    let receiver: IntentBindingReceiver
    private var active = true
    init(receiver: IntentBindingReceiver) { self.receiver = receiver }
    func invalidate() { receiver.withLock { _ in active = false } }
    func receive(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        receiver.withLock { receiver in
            guard active else { return Unmanaged.passUnretained(event) }
            return intentBindingCallback(OpaquePointer(bitPattern: 1)!, type, event, Unmanaged.passUnretained(receiver).toOpaque())
        }
    }
}
let intentThreadedBindingCallback: CGEventTapCallBack = { _, type, event, pointer in
    guard let pointer else { return Unmanaged.passUnretained(event) }
    return Unmanaged<IntentTapCallbackContext>.fromOpaque(pointer).takeUnretainedValue().receive(type, event: event)
}
