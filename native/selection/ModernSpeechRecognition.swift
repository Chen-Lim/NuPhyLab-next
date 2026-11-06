// Adapted from apps/macos/Sources/Chord/AI/ModernSpeechRecognition.swift.
// Standalone single-selection extraction; see source-provenance.json for changes and hashes.
import AVFoundation
import Speech
import Carbon

/// The engine/tap still belong to VoiceAudioExecutor. This interface only owns
/// the new async recognizer and copies of admitted audio in a bounded stream.
protocol VoiceModernRecognition: AnyObject, Sendable {
    func makeInput(format: AVAudioFormat) throws -> any VoiceModernAudioInput
    func start(onResult: @escaping @Sendable (VoiceAudioResult) -> Void)
    func cancel()
}

protocol VoiceModernAudioInput: AnyObject {
    func append(_ buffer: AVAudioPCMBuffer, lease: VoiceAudioLease)
    func close()
    func endAudio()
}

enum VoiceModernRecognitionFactory {
    static func prepare(localeIdentifier: String, lease: VoiceAudioLease) async -> (any VoiceModernRecognition)? {
        guard #available(macOS 26, *) else { return nil }
        let gate = SpeechPreparationGate()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                gate.install(continuation)
                let preparation = Task.detached(priority: .userInitiated) {
                    let result = await ModernSpeechRecognition.prepare(localeIdentifier: localeIdentifier, lease: lease)
                    gate.resolve(result)
                }
                let deadline = Task.detached {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    gate.resolve(nil)
                }
                gate.installTasks([preparation, deadline])
            }
        } onCancel: { gate.resolve(nil) }
    }
}

/// An OS preparation call can take longer than a held gesture. Resolve once,
/// cancel the losing work, and dispose any recognizer that arrives too late.
private final class SpeechPreparationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resolved = false
    private var continuation: CheckedContinuation<(any VoiceModernRecognition)?, Never>?
    private var tasks: [Task<Void, Never>] = []
    func install(_ continuation: CheckedContinuation<(any VoiceModernRecognition)?, Never>) {
        lock.lock()
        if resolved { lock.unlock(); continuation.resume(returning: nil); return }
        self.continuation = continuation; lock.unlock()
    }
    func installTasks(_ tasks: [Task<Void, Never>]) {
        lock.lock()
        if resolved { lock.unlock(); tasks.forEach { $0.cancel() }; return }
        self.tasks = tasks; lock.unlock()
    }
    func resolve(_ value: (any VoiceModernRecognition)?) {
        lock.lock()
        guard !resolved else { lock.unlock(); value?.cancel(); return }
        resolved = true
        let continuation = continuation, tasks = tasks
        self.continuation = nil; self.tasks = []; lock.unlock()
        tasks.forEach { $0.cancel() }
        continuation?.resume(returning: value)
    }
}

@available(macOS 26, *)
final class ModernSpeechRecognition: VoiceModernRecognition, @unchecked Sendable {
    private let analyzer: SpeechAnalyzer
    private let transcriber: SpeechTranscriber
    private let format: AVAudioFormat
    private let stream: AsyncThrowingStream<AnalyzerInput, Error>
    private let continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation
    private let lease: VoiceAudioLease
    private let chinese: Bool
    private let lock = NSLock()
    private var cancelled = false
    private var tasks: [Task<Void, Never>] = []
    private var resultTask: Task<String?, Never>?

    private init(analyzer: SpeechAnalyzer, transcriber: SpeechTranscriber, format: AVAudioFormat, lease: VoiceAudioLease, chinese: Bool) {
        self.analyzer = analyzer; self.transcriber = transcriber; self.format = format; self.lease = lease
        self.chinese = chinese
        // 128 tap buffers is a bounded backlog, normally about 2.7s at 48kHz.
        // Overflow fails the recording; it never silently omits spoken words.
        (stream, continuation) = AsyncThrowingStream.makeStream(bufferingPolicy: .bufferingOldest(128))
    }

    static func prepare(localeIdentifier: String, lease: VoiceAudioLease) async -> ModernSpeechRecognition? {
        guard SpeechTranscriber.isAvailable, lease.isValid, !Task.isCancelled else { return nil }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeIdentifier)),
              lease.isValid, !Task.isCancelled else { return nil }
        let installed = await SpeechTranscriber.installedLocales
        guard installed.contains(where: { $0.identifier == locale.identifier }), lease.isValid, !Task.isCancelled else { return nil }
        // Avoid .fastResults (included in Apple's progressive preset): Apple
        // documents its smaller context window as faster but less accurate.
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
            reportingOptions: [.volatileResults], attributeOptions: [])
        let analyzer = SpeechAnalyzer(modules: [transcriber], options: .init(priority: .userInitiated, modelRetention: .lingering))
        // No asset download request and no network recognizer fallback.
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]),
              lease.isValid, !Task.isCancelled else { await analyzer.cancelAndFinishNow(); return nil }
        do {
            try await analyzer.prepareToAnalyze(in: format)
            try Task.checkCancellation(); try lease.checkCancellation()
            return ModernSpeechRecognition(analyzer: analyzer, transcriber: transcriber, format: format, lease: lease,
                chinese: locale.language.languageCode?.identifier == "zh")
        } catch { await analyzer.cancelAndFinishNow(); return nil }
    }

    func makeInput(format source: AVAudioFormat) throws -> any VoiceModernAudioInput {
        try ModernSpeechAudioInput(source: source, target: format, continuation: continuation)
    }

    func start(onResult: @escaping @Sendable (VoiceAudioResult) -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled, tasks.isEmpty else { return }
        let analyzer = analyzer, transcriber = transcriber, stream = stream, lease = lease, chinese = chinese
        let results = Task.detached(priority: .userInitiated) { () -> String? in
            var transcript = SpeechTranscriptAccumulator()
            do {
                for try await result in transcriber.results {
                    guard lease.isValid, !Task.isCancelled else { return nil }
                    let rawText = transcript.receive(String(result.text.characters), final: result.isFinal)
                    let text = SpeechRecognitionPolicy.formattedTranscript(rawText, chinese: chinese)
                    // A segment final must not stop the microphone mid-hold.
                    onResult(.init(text: text, isFinal: false, failureDomain: nil, failureCode: nil))
                }
                guard lease.isValid, !Task.isCancelled else { return nil }
                return SpeechRecognitionPolicy.formattedTranscript(transcript.completeText, chinese: chinese)
            } catch {
                guard lease.isValid, !Task.isCancelled else { return nil }
                let error = error as NSError
                onResult(.init(text: nil, isFinal: false, failureDomain: error.domain, failureCode: error.code))
                return nil
            }
        }
        let analysis = Task.detached(priority: .userInitiated) {
            do {
                try await analyzer.start(inputSequence: stream)
                // Waits for explicit release, then consumes and finalizes ALL
                // queued samples before the result sequence can report final.
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                if let text = await results.value, lease.isValid, !Task.isCancelled {
                    onResult(.init(text: text, isFinal: true, failureDomain: nil, failureCode: nil))
                }
            } catch {
                guard lease.isValid, !Task.isCancelled else { return }
                let error = error as NSError
                onResult(.init(text: nil, isFinal: false, failureDomain: error.domain, failureCode: error.code))
            }
        }
        resultTask = results; tasks = [analysis]
    }

    func cancel() {
        lock.lock()
        guard !cancelled else { lock.unlock(); return }
        cancelled = true; let tasks = tasks, resultTask = resultTask
        self.tasks = []; self.resultTask = nil; lock.unlock()
        continuation.finish(throwing: CancellationError())
        tasks.forEach { $0.cancel() }
        resultTask?.cancel()
        let analyzer = analyzer
        Task { await analyzer.cancelAndFinishNow() }
    }
}

@available(macOS 26, *)
final class ModernSpeechAudioInput: VoiceModernAudioInput, @unchecked Sendable {
    enum Failure: Error { case invalidFormat, conversion, overrun }
    private let lock = NSLock()
    private let target: AVAudioFormat
    private let converter: AVAudioConverter
    private let continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation
    private var accepting = true
    private var ended = false
    private var hadInput = false

    init(source: AVAudioFormat, target: AVAudioFormat, continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation) throws {
        guard source.sampleRate.isFinite, source.sampleRate >= 8_000, source.sampleRate <= 192_000,
              source.channelCount > 0, source.channelCount <= 32,
              target.sampleRate.isFinite, target.sampleRate > 0,
              let converter = AVAudioConverter(from: source, to: target) else { throw Failure.invalidFormat }
        self.target = target; self.converter = converter; self.continuation = continuation
        converter.primeMethod = .none
    }

    func append(_ buffer: AVAudioPCMBuffer, lease: VoiceAudioLease) {
        guard lease.permitsBuffers, !IsSecureEventInputEnabled(), lock.try() else { return }
        defer { lock.unlock() }
        guard accepting, lease.permitsBuffers, !IsSecureEventInputEnabled() else { return }
        guard buffer.frameLength > 0, buffer.frameLength <= 32_768 else { fail(.invalidFormat); return }
        let count = ceil(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 64
        guard count.isFinite, count > 0, count <= 65_536,
              let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(count)) else { fail(.invalidFormat); return }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            guard !supplied else { inputStatus.pointee = .noDataNow; return nil }
            supplied = true; inputStatus.pointee = .haveData; return buffer
        }
        guard error == nil, status != .error else { fail(.conversion); return }
        hadInput = true
        // output owns its storage. Borrowed engine PCM never crosses this call.
        if output.frameLength > 0 { enqueue(output) }
    }

    func close() { lock.lock(); accepting = false; lock.unlock() }

    func endAudio() {
        lock.lock(); defer { lock.unlock() }
        accepting = false
        guard !ended else { return }
        // Drain any converter tail so release does not trim the last phoneme.
        if hadInput, let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 4096) {
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, status in status.pointee = .endOfStream; return nil }
            if error != nil || status == .error { fail(.conversion); return }
            if output.frameLength > 0 { enqueue(output) }
        }
        ended = true; continuation.finish()
    }

    private func enqueue(_ buffer: AVAudioPCMBuffer) {
        guard !ended else { return }
        switch continuation.yield(AnalyzerInput(buffer: buffer)) {
        case .dropped: fail(.overrun)
        case .terminated: accepting = false; ended = true
        case .enqueued: break
        @unknown default: fail(.overrun)
        }
    }
    private func fail(_ failure: Failure) {
        accepting = false; ended = true; continuation.finish(throwing: failure)
    }
}
