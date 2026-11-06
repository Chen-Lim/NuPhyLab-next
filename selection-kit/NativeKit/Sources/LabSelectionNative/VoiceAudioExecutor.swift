import Foundation

/// The lock protects only small state transitions. Framework calls and PCM
/// appends must never execute while holding this lease's lock.
public final class VoiceAudioLease: @unchecked Sendable {
    public let token: UUID
    private enum Phase { case pending, starting, running, finishing, cancelled }
    private let lock = NSLock()
    private var phase: Phase = .pending

    public init(token: UUID = UUID()) { self.token = token }
    public var isValid: Bool { lock.lock(); defer { lock.unlock() }; return phase != .cancelled }
    public var permitsBuffers: Bool {
        lock.lock(); defer { lock.unlock() }
        return phase == .starting || phase == .running
    }
    public func cancel() { lock.lock(); phase = .cancelled; lock.unlock() }
    public func checkCancellation() throws { if !isValid { throw CancellationError() } }

    /// A release during startup abandons that startup. Once running, release
    /// closes PCM input while keeping the lease valid for final recognition.
    public func stopInput() {
        lock.lock(); defer { lock.unlock() }
        switch phase {
        case .pending, .starting: phase = .cancelled
        case .running: phase = .finishing
        case .finishing, .cancelled: break
        }
    }
    fileprivate func willStart() throws {
        lock.lock(); defer { lock.unlock() }
        guard phase == .pending else { throw CancellationError() }
        phase = .starting
    }
    fileprivate func didStart() throws {
        lock.lock(); defer { lock.unlock() }
        guard phase == .starting else { throw CancellationError() }
        phase = .running
    }
}

/// Production AV/Speech objects are constructed by the factory on the worker
/// queue. Implementations also check their lease between framework calls inside
/// each stage. stopInput and cleanup must tolerate partially initialized state.
public protocol VoiceAudioBackend: AnyObject {
    func initialize() throws
    func prepare() throws
    func start() throws
    func stopInput()
    func cleanup()
}

/// Owns framework resource ordering, independent of MainActor responsiveness.
/// The caller can invalidate a lease while a framework startup call is blocked.
public final class VoiceAudioExecutor: @unchecked Sendable {
    public let queue: DispatchQueue
    private let callbackQueue: DispatchQueue
    private let currentLock = NSLock()
    private var currentLease: VoiceAudioLease?
    private let worker = VoiceAudioWorkerState()

    public init(label: String = "com.nuphy.chord.voice-audio", callbackQueue: DispatchQueue = .main) {
        queue = DispatchQueue(label: label, qos: .userInitiated)
        self.callbackQueue = callbackQueue
    }

    /// Callbacks use one FIFO queue (Main by default). A recognition callback
    /// must enter through deliver, including a synchronous callback from start.
    public func begin(lease: VoiceAudioLease,
                      factory: @escaping @Sendable () -> any VoiceAudioBackend,
                      onStarted: @escaping @Sendable () -> Void,
                      onFailure: @escaping @Sendable (Error) -> Void) {
        currentLock.lock()
        if currentLease === lease { currentLock.unlock(); return }
        let previous = currentLease
        currentLease = lease
        previous?.cancel()
        currentLock.unlock()
        queue.async { [self] in
            if let previous { worker.cleanup(matching: previous) }
            guard accepts(lease) else { return }
            // Also close a record whose caller cancelled its lease directly.
            worker.cleanupCurrent()
            guard accepts(lease) else { return }
            let record = VoiceAudioWorkerRecord(lease: lease, backend: factory())
            worker.record = record
            do {
                try lease.checkCancellation()
                try record.backend.initialize()
                try lease.checkCancellation()
                try record.backend.prepare()
                try lease.checkCancellation()
                try lease.willStart()
                try record.backend.start()
                try lease.didStart()
                callbackQueue.async { [weak self] in
                    guard let self, self.accepts(lease), lease.permitsBuffers else { return }
                    onStarted()
                }
            } catch {
                let reportFailure = accepts(lease) && !(error is CancellationError)
                lease.cancel()
                worker.cleanup(matching: lease)
                if reportFailure {
                    callbackQueue.async { [weak self] in
                        // A failed lease is intentionally invalid. Ownership,
                        // not validity, decides whether its failure is current.
                        guard self?.isCurrent(lease) == true else { return }
                        onFailure(error)
                    }
                }
            }
        }
    }

    public func finishInput(lease: VoiceAudioLease) {
        lease.stopInput() // Immediate even when initialize/prepare/start blocks.
        queue.async { [self] in
            guard let record = worker.record, record.lease === lease else { return }
            if lease.isValid { worker.stopInput(record) }
            else { worker.cleanup(matching: lease) }
        }
    }

    public func cancel(lease: VoiceAudioLease) {
        lease.cancel() // Never wait for the worker or a framework append lock.
        currentLock.lock()
        if currentLease === lease { currentLease = nil }
        currentLock.unlock()
        queue.async { [self] in worker.cleanup(matching: lease) }
    }

    /// Always enqueue, even when called on queue. This puts an early result
    /// after the startup operation's onStarted delivery. Both hops recheck the
    /// lease so cancellation or replacement can suppress already-queued work.
    public func deliver(lease: VoiceAudioLease, callback: @escaping @Sendable () -> Void) {
        queue.async { [weak self] in
            guard let self, self.accepts(lease) else { return }
            self.callbackQueue.async { [weak self] in
                guard self?.accepts(lease) == true else { return }
                callback()
            }
        }
    }

    private func isCurrent(_ lease: VoiceAudioLease) -> Bool {
        currentLock.lock(); defer { currentLock.unlock() }
        return currentLease === lease
    }
    private func accepts(_ lease: VoiceAudioLease) -> Bool { isCurrent(lease) && lease.isValid }

    deinit {
        currentLease?.cancel()
        let worker = worker
        // Even releasing the final executor reference on Main must not destroy
        // live framework objects there. Only this queue owns the backend.
        queue.async { worker.cleanupCurrent() }
    }
}

private final class VoiceAudioWorkerRecord {
    let lease: VoiceAudioLease
    let backend: any VoiceAudioBackend
    var inputStopped = false
    var cleaned = false
    init(lease: VoiceAudioLease, backend: any VoiceAudioBackend) { self.lease = lease; self.backend = backend }
}

/// Accessed exclusively on the executor queue, including final destruction.
private final class VoiceAudioWorkerState: @unchecked Sendable {
    var record: VoiceAudioWorkerRecord?
    func stopInput(_ record: VoiceAudioWorkerRecord) {
        guard !record.inputStopped else { return }
        record.inputStopped = true
        record.backend.stopInput()
    }
    func cleanup(matching lease: VoiceAudioLease) {
        guard let record, record.lease === lease else { return }
        cleanupCurrent()
    }
    func cleanupCurrent() {
        guard let record, !record.cleaned else { return }
        record.cleaned = true
        stopInput(record)
        record.backend.cleanup()
        self.record = nil
    }
}
