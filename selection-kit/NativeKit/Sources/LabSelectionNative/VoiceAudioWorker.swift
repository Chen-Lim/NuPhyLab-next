// Adapted from apps/macos/Sources/Chord/AI/VoiceAudioWorker.swift.
// Standalone single-selection extraction; see source-provenance.json for changes and hashes.
import AVFoundation
import Speech
import Carbon
import ChordAudioBoundary

/// Only immutable, memory-only values cross back to the UI. The engine/tap and
/// legacy recognizer stay on the serial worker; modern analysis owns its async
/// stream and receives copied PCM through its isolated bridge.
struct VoiceAudioResult: Sendable {
    let text: String?
    let isFinal: Bool
    let failureDomain: String?
    let failureCode: Int?
}

enum VoiceAudioWorkerError: Error {
    case unsupportedLanguage, unavailable, unsafeInput, invalidInputFormat
}

/// Constructed, used and released by VoiceAudioExecutor's serial worker. No
/// lifecycle method is called by MainActor, including failure cleanup.
final class VoiceAudioWorker: VoiceAudioBackend {
    private let lease: VoiceAudioLease
    private weak var executor: VoiceAudioExecutor?
    private let workerQueue: DispatchQueue
    private let localeIdentifier: String
    private let purpose: SpeechRecognitionPurpose
    private let context: VoiceRecognitionContext
    private let modernRecognition: (any VoiceModernRecognition)?
    private let diagnosticGeneration: UInt64
    private let onResult: @Sendable (VoiceAudioResult) -> Void
    private let onDiagnostic: @Sendable (InteractionDiagnosticSample) -> Void
    private let onSafetyCancelled: @Sendable () -> Void
    private var recognizer: SFSpeechRecognizer?
    private var recognitionQueue: OperationQueue?
    private var engine: AVAudioEngine?
    private var input: AVAudioInputNode?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var bufferGate: VoiceAudioBufferGate?
    private var modernInput: (any VoiceModernAudioInput)?
    private var inputLifecycle = VoiceInputLifecycle()
    private var engineNeedsStop = false
    private var inputStopped = false
    private var cleanedUp = false

    init(lease: VoiceAudioLease, executor: VoiceAudioExecutor, localeIdentifier: String,
         purpose: SpeechRecognitionPurpose = .command,
         context: VoiceRecognitionContext = VoiceRecognitionContext([]),
         modernRecognition: (any VoiceModernRecognition)? = nil,
         diagnosticGeneration: UInt64,
         onResult: @escaping @Sendable (VoiceAudioResult) -> Void,
         onDiagnostic: @escaping @Sendable (InteractionDiagnosticSample) -> Void,
         onSafetyCancelled: @escaping @Sendable () -> Void) {
        self.lease = lease; self.executor = executor; workerQueue = executor.queue; self.localeIdentifier = localeIdentifier
        self.purpose = purpose; self.context = context; self.modernRecognition = modernRecognition
        self.diagnosticGeneration = diagnosticGeneration
        self.onResult = onResult; self.onDiagnostic = onDiagnostic
        self.onSafetyCancelled = onSafetyCancelled
    }

    func initialize() throws {
        dispatchPrecondition(condition: .onQueue(workerQueue))
        try checkSafety()
        if modernRecognition == nil {
            let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
            self.recognizer = recognizer
            try checkSafety()
            guard let recognizer, recognizer.supportsOnDeviceRecognition else { throw VoiceAudioWorkerError.unsupportedLanguage }
            try checkSafety()
            guard recognizer.isAvailable else { throw VoiceAudioWorkerError.unavailable }
            try checkSafety()
            let callbacks = OperationQueue()
            callbacks.name = "com.nuphy.chord.local-speech.callbacks"
            callbacks.maxConcurrentOperationCount = 1
            callbacks.underlyingQueue = workerQueue
            recognizer.queue = callbacks
            recognitionQueue = callbacks
            try checkSafety()
        }

        let engine = measure(.audioEngineCreated) { AVAudioEngine() }
        self.engine = engine
        try checkSafety()
        let (input, format) = try measure(.audioInputFormat) {
            guard let input = ChordAudioTryInputNode(engine) else { throw VoiceAudioWorkerError.unavailable }
            try checkSafety()
            return (input, input.outputFormat(forBus: 0))
        }
        self.input = input
        try checkSafety()
        guard format.sampleRate.isFinite, format.sampleRate > 0, format.channelCount > 0 else { throw VoiceAudioWorkerError.invalidInputFormat }

        let append: (AVAudioPCMBuffer) -> Void
        let lease = self.lease
        if let modernRecognition {
            let gate = try modernRecognition.makeInput(format: format)
            modernInput = gate
            append = { gate.append($0, lease: lease) }
        } else {
            let request = SFSpeechAudioBufferRecognitionRequest()
            self.request = request
            SpeechRecognitionPolicy.configure(request, purpose: purpose, context: context.strings)
            let gate = VoiceAudioBufferGate(request: request)
            bufferGate = gate
            append = { gate.append($0, lease: lease) }
            let queue = workerQueue
            context.observe { [weak self] phrases in
                queue.async { [weak self] in
                    guard let self, self.lease.isValid, !self.inputStopped else { return }
                    self.request?.contextualStrings = phrases
                }
            }
        }
        try checkSafety()
        try inputLifecycle.install(sampleRate: format.sampleRate, channelCount: format.channelCount, install: {
            self.measure(.audioTapInstalled) {
                ChordAudioTryInstallTap(input, 0, 1024, format) { buffer, _ in
                    // This is borrowed PCM memory: consume synchronously. The
                    // modern bridge queues only its own converted PCM storage.
                    append(buffer)
                }
            }
        }, remove: {
            self.measure(.audioTapRemoved) { _ = ChordAudioTryRemoveTap(input, 0) }
        })
        try checkSafety()
    }

    func prepare() throws {
        dispatchPrecondition(condition: .onQueue(workerQueue))
        try checkSafety()
        guard let engine else { throw VoiceAudioWorkerError.unavailable }
        let executor = self.executor, lease = self.lease, onResult = self.onResult
        let onSafetyCancelled = self.onSafetyCancelled
        if let modernRecognition {
            measure(.audioRecognitionStarted) {
                modernRecognition.start { [weak executor] result in
                    guard VoiceAudioWorker.admitRecognition(lease: lease, executor: executor,
                        onSafetyCancelled: onSafetyCancelled) else { return }
                    executor?.deliver(lease: lease) { onResult(result) }
                }
            }
        } else {
            guard let recognizer, let request else { throw VoiceAudioWorkerError.unavailable }
            recognition = measure(.audioRecognitionStarted) {
                recognizer.recognitionTask(with: request) { [weak executor] result, error in
                    guard VoiceAudioWorker.admitRecognition(lease: lease, executor: executor,
                        onSafetyCancelled: onSafetyCancelled) else { return }
                    let payload = VoiceAudioResult(
                        text: result.map { String($0.bestTranscription.formattedString.prefix(16_000)) },
                        isFinal: result?.isFinal ?? false,
                        failureDomain: (error as NSError?)?.domain,
                        failureCode: (error as NSError?)?.code)
                    guard VoiceAudioWorker.admitRecognition(lease: lease, executor: executor,
                        onSafetyCancelled: onSafetyCancelled) else { return }
                    // Always enqueue, even if a framework calls back synchronously
                    // inside prepare/start. Core publishes started before results,
                    // and rechecks the lease again on the callback queue.
                    executor?.deliver(lease: lease) { onResult(payload) }
                }
            }
        }
        try checkSafety()
        engineNeedsStop = true
        measure(.audioEnginePrepared) { engine.prepare() }
        try checkSafety()
    }

    func start() throws {
        dispatchPrecondition(condition: .onQueue(workerQueue))
        try checkSafety()
        guard let engine else { throw VoiceAudioWorkerError.unavailable }
        // A system call already entered cannot be forcibly interrupted. A
        // cancelled lease is checked immediately on return, before UI delivery.
        try measure(.audioEngineStarted) { try engine.start() }
        try checkSafety()
    }

    func stopInput() {
        dispatchPrecondition(condition: .onQueue(workerQueue))
        guard !inputStopped else { return }
        inputStopped = true
        // Close admission and wait for any one already-admitted synchronous
        // append. MainActor only invalidates the lease, never takes this lock.
        bufferGate?.close()
        modernInput?.close()
        // AV may wait for its tap callback. Never hold the gate while stopping
        // the engine or removing the tap, or that wait could deadlock.
        if engineNeedsStop, let engine {
            engineNeedsStop = false
            measure(.audioEngineStopped) { engine.stop() }
        }
        if let input {
            inputLifecycle.stop { self.measure(.audioTapRemoved) { _ = ChordAudioTryRemoveTap(input, 0) } }
        }
        bufferGate?.endAudio()
        modernInput?.endAudio()
    }

    func cleanup() {
        dispatchPrecondition(condition: .onQueue(workerQueue))
        guard !cleanedUp else { return }
        cleanedUp = true
        stopInput()
        if let recognition { measure(.audioRecognitionCancelled) { recognition.cancel() } }
        modernRecognition?.cancel()
        context.observe(nil)
        recognition = nil; request = nil; bufferGate = nil
        modernInput = nil
        input = nil; engine = nil; recognizer = nil; recognitionQueue = nil
    }

    private func checkSafety() throws {
        try lease.checkCancellation()
        guard Self.permissionsRemainSafe else { throw VoiceAudioWorkerError.unsafeInput }
        try lease.checkCancellation()
    }

    private static var permissionsRemainSafe: Bool {
        !IsSecureEventInputEnabled() && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized &&
            SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    /// A transient unsafe state must be remembered at the producer. Ordinary
    /// delivery intentionally drops cancelled leases, so its safety notification
    /// uses a separate, token-bound Main queue path supplied by the service.
    private static func admitRecognition(lease: VoiceAudioLease, executor: VoiceAudioExecutor?,
        onSafetyCancelled: @Sendable () -> Void) -> Bool {
        guard lease.isValid else { return false }
        guard permissionsRemainSafe else {
            lease.cancel()
            executor?.cancel(lease: lease)
            onSafetyCancelled()
            return false
        }
        return lease.isValid
    }

    private func measure<Value>(_ event: InteractionDiagnosticEvent, _ operation: () throws -> Value) rethrows -> Value {
        let start = ProcessInfo.processInfo.systemUptime
        let mayDiagnose = !IsSecureEventInputEnabled()
        defer {
            if mayDiagnose && !IsSecureEventInputEnabled() {
                onDiagnostic(.init(event: event, uptime: start,
                    duration: ProcessInfo.processInfo.systemUptime - start, generation: diagnosticGeneration))
            }
        }
        return try operation()
    }
}

/// Independent of the lease's short state lock. The tap never waits for MainActor
/// or synchronously dispatches to another queue. One already-admitted append may
/// finish after cancellation; new buffers are rejected immediately by the lease.
private final class VoiceAudioBufferGate: @unchecked Sendable {
    private let lock = NSLock()
    private var accepting = true
    private var request: SFSpeechAudioBufferRecognitionRequest?
    init(request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }

    func append(_ buffer: AVAudioPCMBuffer, lease: VoiceAudioLease) {
        guard lease.permitsBuffers, !IsSecureEventInputEnabled(), lock.try() else { return }
        defer { lock.unlock() }
        guard accepting, lease.permitsBuffers, !IsSecureEventInputEnabled(), let request else { return }
        request.append(buffer)
    }
    func close() {
        lock.lock(); accepting = false; lock.unlock()
    }
    func endAudio() {
        lock.lock()
        accepting = false
        let finishedRequest = request
        request = nil
        lock.unlock()
        // close() has drained any admitted append; no later append can use this
        // request. endAudio and releasing the final reference stay on the worker.
        finishedRequest?.endAudio()
    }
}
