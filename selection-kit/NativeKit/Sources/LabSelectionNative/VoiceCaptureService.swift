// Adapted from apps/macos/Sources/Chord/AI/VoiceCaptureService.swift.
// Standalone single-selection extraction; see source-provenance.json for changes and hashes.
import AppKit
import AVFoundation
import Speech
import Carbon
import OSLog

/// User-started, microphone-only recognition. No audio files and no network fallback.
@MainActor final class VoiceCaptureService: ObservableObject {
    @Published private(set) var session = VoiceSession()
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var issue: String?
    @Published private(set) var diagnostic: String?
    var onTranscript: ((String) -> Void)?
    var onRecordingStarted: ((UUID) -> Void)?
    var onRecordingEnded: (() -> Void)?
    var onSafetyCancelled: (() -> Void)?
    var onResolved: ((UUID, InteractionTranscript) -> Void)?
    var onDiagnostic: ((InteractionDiagnosticSample) -> Void)?
    var language: AppLanguage = .en
    var localeIdentifierOverride: String?
    var recognitionPurpose: SpeechRecognitionPurpose = .command
    private let audioExecutor: VoiceAudioExecutor
    private var audioLease: VoiceAudioLease?
    private var recognitionContext: VoiceRecognitionContext?
    private var modernRecognition: (any VoiceModernRecognition)?
    private var activePurpose: SpeechRecognitionPurpose = .command
    private var activeChinese = false
    private var activeLocaleIdentifier = "en-US"
    private var recordingStartedToken: UUID?
    private var startup: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var timer: Timer?
    private var startedAt: Date?
    private var diagnosticGeneration: UInt64 = 0
    private let logger = Logger(subsystem: "com.nuphy.chord", category: "LocalSpeech")
    init(audioExecutor: VoiceAudioExecutor = VoiceAudioExecutor()) { self.audioExecutor = audioExecutor }
    #if DEBUG
    /// Substitutes microphone/recognizer effects only. Real VoiceSession, result
    /// handling, finalization timeout and owner callbacks remain in use.
    struct CaptureTestDriver {
        let onStart: (UUID) -> Void
        let onFinishInput: (UUID) -> Void
        var finalizationTimeout: TimeInterval = 0.02
    }
    var captureTestDriver: CaptureTestDriver?
    func receiveTestResult(_ result: VoiceAudioResult, token: UUID) {
        guard captureTestDriver != nil, let lease = audioLease, lease.token == token else { return }
        receive(result, lease: lease)
    }
    #endif
    private func t(_ zh: String, _ en: String) -> String { language == .zh ? zh : en }
    var isRecording: Bool { session.phase == .recording }
    var isActive: Bool { session.isActive }
    var elapsed: TimeInterval { startedAt.map { Date().timeIntervalSince($0) } ?? Double(elapsedSeconds) }
    func bindObjects(_ IDs: [UUID], token: UUID) { session.bindObjects(IDs, generation: token) }
    /// Call only with text from the explicitly selected target. Context is
    /// bounded and belongs to this recording; late OCR cannot bias the next one.
    func updateRecognitionContext(_ phrases: [String], token: UUID) {
        guard session.generation == token, session.isActive, audioLease?.isValid == true else { return }
        recognitionContext?.update(SpeechRecognitionPolicy.contextualStrings(phrases,
            purpose: activePurpose, chinese: activeChinese))
    }
    var statusText: String {
        if let issue { return issue }
        switch session.phase {
        case .idle: return t("仅在使用语音时请求；在本机转录。", "Permission is requested only when using voice. Transcription stays on this Mac.")
        case .authorizing: return t("正在准备本机语音与权限…", "Preparing local speech and permissions…")
        case .recording: return t("正在本机录音 · 最长 60 秒", "Recording on this Mac · 60 second limit")
        case .finishing: return t("正在完成转录…", "Finishing the transcript…")
        case .ready: return t("本机转录已完成。", "Local transcript is ready.")
        case .unavailable: return t("本机语音暂不可用，请键入指令。", "Local speech is unavailable. Type your instructions instead.")
        }
    }

    func start(objectIDs: [UUID], onPrepared: ((UUID) -> Void)? = nil) {
        guard !isActive else { return }
        cleanUp(); diagnosticGeneration &+= 1; issue = nil; diagnostic = nil; elapsedSeconds = 0
        let token = session.begin(objectIDs: objectIDs)
        let lease = VoiceAudioLease(token: token)
        audioLease = lease
        activePurpose = recognitionPurpose; activeChinese = language == .zh
        activeLocaleIdentifier = localeIdentifierOverride ?? SpeechRecognitionPolicy.localeIdentifier(chinese: activeChinese)
        activeChinese = Locale(identifier: activeLocaleIdentifier).language.languageCode?.identifier == "zh"
        recognitionContext = VoiceRecognitionContext(SpeechRecognitionPolicy.contextualStrings([],
            purpose: activePurpose, chinese: activeChinese))
        // Register the owner before any authorization or recognition can finish.
        onPrepared?(token)
        #if DEBUG
        if let captureTestDriver {
            audioStarted(lease: lease)
            captureTestDriver.onStart(token)
            return
        }
        #endif
        startup = Task { [weak self] in
            guard let self, !Task.isCancelled, self.session.generation == token, self.session.phase == .authorizing else { return }
            guard !IsSecureEventInputEnabled() else { self.fail(self.t("安全输入期间不开始录音。", "Recording cannot start during secure input."), token: token); return }
            // Calling permission APIs from a bare SwiftPM executable would terminate it.
            guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") is String,
                  Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") is String else {
                self.fail(self.t("此构建缺少语音权限说明，请使用完整的宿主应用。", "This build lacks speech permission descriptions. Use the complete host app."), token: token); return
            }
            let microphone = await AVCaptureDevice.requestAccess(for: .audio)
            guard self.session.generation == token, self.session.phase == .authorizing, lease.isValid, !Task.isCancelled else { return }
            guard microphone else { self.fail(self.t("麦克风未获许可。可在系统设置中允许，或直接键入。", "Microphone access was not granted. Allow it in System Settings or type instead."), token: token); return }
            // Permission UI can outlive the original secure-input state. Do not
            // open a second authorization prompt after safety conditions change.
            guard !IsSecureEventInputEnabled(), AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
                self.safetyCancel(); return
            }
            let speech = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            guard self.session.generation == token, self.session.phase == .authorizing, lease.isValid, !Task.isCancelled else { return }
            guard speech == .authorized else {
                self.fail(self.t("本机语音服务未获许可或尚未就绪。请检查系统语音设置，或键入指令。", "Local speech is not authorized or ready. Check system speech settings, or type your instructions."), token: token); return
            }
            guard self.permissionsRemainSafe else { self.safetyCancel(); return }
            let modern = await VoiceModernRecognitionFactory.prepare(localeIdentifier: self.activeLocaleIdentifier, lease: lease)
            guard self.session.generation == token, self.session.phase == .authorizing, lease.isValid, !Task.isCancelled else {
                modern?.cancel(); return
            }
            guard self.permissionsRemainSafe else { modern?.cancel(); self.safetyCancel(); return }
            self.modernRecognition = modern
            self.beginAudio(lease: lease)
        }
    }

    private func beginAudio(lease: VoiceAudioLease) {
        let token = lease.token
        guard session.generation == token, session.phase == .authorizing, lease.isValid else { return }
        let executor = audioExecutor
        let localeIdentifier = activeLocaleIdentifier
        let purpose = activePurpose
        let context = recognitionContext ?? VoiceRecognitionContext([])
        let modern = modernRecognition
        let generation = diagnosticGeneration
        let onResult: @Sendable (VoiceAudioResult) -> Void = { [weak self] result in
            MainActor.assumeIsolated { self?.receive(result, lease: lease) }
        }
        let onDiagnostic: @Sendable (InteractionDiagnosticSample) -> Void = { [weak self] sample in
            // Timing metadata may describe a cancelled startup. Keep its original
            // generation, without changing or reviving any user-facing session.
            DispatchQueue.main.async { [weak self] in
                guard !IsSecureEventInputEnabled() else { return }
                self?.onDiagnostic?(sample)
            }
        }
        let onSafetyCancelled: @Sendable () -> Void = { [weak self] in
            // The producer has already invalidated this lease. Do not filter on
            // its validity or recheck a transient safety condition here.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.audioLease === lease, self.session.generation == token,
                      self.session.isActive else { return }
                self.safetyCancel()
            }
        }
        executor.begin(lease: lease, factory: {
            VoiceAudioWorker(lease: lease, executor: executor, localeIdentifier: localeIdentifier,
                purpose: purpose, context: context, modernRecognition: modern,
                diagnosticGeneration: generation, onResult: onResult, onDiagnostic: onDiagnostic,
                onSafetyCancelled: onSafetyCancelled)
        }, onStarted: { [weak self] in
            MainActor.assumeIsolated { self?.audioStarted(lease: lease) }
        }, onFailure: { [weak self] error in
            MainActor.assumeIsolated { self?.audioFailed(error, token: token) }
        })
    }

    private func audioStarted(lease: VoiceAudioLease) {
        let token = lease.token
        guard audioLease === lease, lease.isValid, session.generation == token, session.phase == .authorizing else { return }
        guard permissionsRemainSafe else { safetyCancel(); return }
        guard session.authorized(generation: token) else { return }
        startup = nil
        recordingStartedToken = token
        startedAt = Date()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.session.generation == token, self.session.phase == .recording else { return }
                guard self.permissionsRemainSafe else { self.safetyCancel(); return }
                self.elapsedSeconds = Int(Date().timeIntervalSince(self.startedAt ?? Date()))
                if self.elapsedSeconds >= 60 { self.stop() }
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard let self, !Task.isCancelled, self.session.generation == token else { return }
            self.stop()
        }
        onRecordingStarted?(token)
    }

    private func receive(_ result: VoiceAudioResult, lease: VoiceAudioLease) {
        let token = lease.token
        guard audioLease === lease, lease.isValid, session.generation == token,
              [.recording, .finishing].contains(session.phase) else { return }
        guard permissionsRemainSafe else { safetyCancel(); return }
        // A failure accompanying a final payload is still an audio failure.
        // The host must never auto-submit an interim text after failure.
        if let domain = result.failureDomain, let code = result.failureCode {
            recordDiagnostic(NSError(domain: domain, code: code), stage: "recognition")
            fail(t("本机转录已停止。已识别文字可继续编辑；不会改用网络识别。", "Local transcription stopped. You can edit the text already recognized; network recognition will not be used."), token: token)
            return
        }
        if let text = result.text, session.update(text, generation: token, final: result.isFinal) {
            onTranscript?(session.transcript)
        }
        // An observer may synchronously cancel or replace the session.
        guard audioLease === lease, lease.isValid, session.generation == token else { return }
        if result.isFinal {
            // A final result with no text must still leave the active phase.
            if session.phase == .finishing { session.finish(generation: token) }
            else if session.phase == .recording { session.stop(); session.finish(generation: token) }
            let transcript = session.transcript
            cleanUp(); notifyRecordingEnded(token: token)
            onResolved?(token, .final(transcript))
        }
    }

    private func audioFailed(_ error: Error, token: UUID) {
        // Core deliberately invalidates a failed lease before cleanup/delivery.
        // Match the session token here rather than accepting a live lease again.
        guard session.generation == token, session.phase == .authorizing else { return }
        if case .some(.unsafeInput) = error as? VoiceAudioWorkerError {
            safetyCancel(); return
        }
        guard permissionsRemainSafe else { safetyCancel(); return }
        recordDiagnostic(error as NSError, stage: "start")
        let message: String
        switch error as? VoiceAudioWorkerError {
        case .unsupportedLanguage:
            message = t("此 Mac 或语言尚不支持本机语音识别。不会上传录音，请键入指令。", "On-device recognition is unavailable for this Mac or language. Audio will not be uploaded; type instead.")
        case .unavailable:
            message = t("本机语音服务尚未就绪。请检查系统语音设置，或键入指令。", "Local speech is not ready. Check system speech settings, or type your instructions.")
        default:
            message = t("无法启动麦克风。请检查输入设备与系统权限后重试。", "The microphone could not start. Check the input device and system permissions.")
        }
        fail(message, token: token)
    }

    private var permissionsRemainSafe: Bool {
        #if DEBUG
        if captureTestDriver != nil { return true }
        #endif
        return !IsSecureEventInputEnabled() && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized &&
            SFSpeechRecognizer.authorizationStatus() == .authorized
    }
    private func safetyCancel() {
        cancel(); onSafetyCancelled?()
        issue = t("录音已安全停止，请重新开始。", "Recording stopped safely. Start again when ready.")
    }

    func stop() {
        if session.phase == .authorizing {
            let token = session.generation
            session.cancel(); cleanUp()
            issue = t("已停止准备语音。再次按住即可开始。", "Stopped preparing speech. Hold again to start.")
            onResolved?(token, .unavailable)
            return
        }
        guard session.phase == .recording else { return }
        let token = session.generation
        var finalizationTimeout = SpeechRecognitionPolicy.finalizationTimeout(recordedSeconds: elapsed)
        #if DEBUG
        if let captureTestDriver { finalizationTimeout = captureTestDriver.finalizationTimeout }
        #endif
        session.stop(); stopUITiming()
        #if DEBUG
        if let captureTestDriver { captureTestDriver.onFinishInput(token) }
        else if let audioLease { audioExecutor.finishInput(lease: audioLease) }
        #else
        if let audioLease { audioExecutor.finishInput(lease: audioLease) }
        #endif
        notifyRecordingEnded(token: token)
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(finalizationTimeout))
            guard let self, !Task.isCancelled, self.session.generation == token else { return }
            guard self.session.phase == .finishing else { return }
            self.session.finish(generation: token); self.cleanUp()
            self.issue = self.t("转录收尾已结束，已保留识别到的文字。", "Transcription finalization ended. The recognized words are preserved.")
            self.onResolved?(token, .partial(self.session.transcript))
        }
    }
    func cancel() {
        let token = session.generation
        session.cancel(); cleanUp(); notifyRecordingEnded(token: token)
        issue = nil; elapsedSeconds = 0
    }
    private func fail(_ message: String, token: UUID) {
        guard session.generation == token else { return }
        let transcript = session.transcript
        session.unavailable(generation: token); issue = message; cleanUp(); notifyRecordingEnded(token: token)
        onResolved?(token, transcript.isEmpty ? .unavailable : .partial(transcript))
    }
    private func recordDiagnostic(_ error: NSError, stage: String) {
        let domain = String(String.UnicodeScalarView(error.domain.unicodeScalars.filter { CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-")).contains($0) }.prefix(100)))
        let value = "\(stage): \(domain) (\(error.code))"
        diagnostic = value
        logger.error("Local speech error: \(value, privacy: .public)")
    }
    private func notifyRecordingEnded(token: UUID) {
        guard recordingStartedToken == token else { return }
        recordingStartedToken = nil
        onRecordingEnded?()
    }
    private func stopUITiming() {
        deadlineTask?.cancel(); deadlineTask = nil
        timer?.invalidate(); timer = nil
        if let startedAt { elapsedSeconds = Int(Date().timeIntervalSince(startedAt)) }
        startedAt = nil
    }
    private func cleanUp() {
        startup?.cancel(); startup = nil
        finishTask?.cancel(); finishTask = nil
        stopUITiming()
        recognitionContext = nil
        modernRecognition?.cancel(); modernRecognition = nil
        if let lease = audioLease {
            // Revocation is immediate even if the worker is blocked in an OS
            // startup call. Core cleans only this lease on its own serial queue.
            audioLease = nil
            audioExecutor.cancel(lease: lease)
        }
    }
}
