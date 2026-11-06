import AppKit
import LabSelectionAI
import LabSelectionNative
import LabSelectionFlow

/// Selection geometry is supplied by Lab's UI, in Quartz global screen points.
public enum SelectionInput {
    case region(IntentBounds, excludingWindowIDs: Set<CGWindowID>)
    case accessibilityPoint(CGPoint)
    case selectedText
}

public enum SelectionHostError: Error { case voiceUnavailable }

/// Compilable, UI-free host wiring. It owns one transient gesture and request.
/// Lab owns its event routing, overlay, settings, permission UI and Keychain.
@MainActor public final class SingleSelectionFeature {
    public var onChange: (() -> Void)?
    public var onTranscript: ((String) -> Void)?
    public var onRecordingChanged: ((Bool) -> Void)?
    public var preferredOCRLanguages = Locale.preferredLanguages
    public var paused = false { didSet { if paused { cancel() } } }
    public var session: SelectionSession { coordinator.session }
    public var error: Error? { captureError ?? coordinator.lastError }
    public var voiceIssue: String? { voice.issue }
    public var voiceLocaleIdentifier: String? {
        get { voice.localeIdentifier }
        set { voice.localeIdentifier = newValue }
    }

    private let context: () async throws -> SelectionRequestContext
    private let voice: LocalVoiceCapture
    private let awareness = ScreenAwarenessService()
    private var activeGesture: SelectionGesture?
    private var voiceHandle: (token: UUID, gesture: SelectionGesture)?
    private var captureTask: Task<Void, Never>?
    private var captureError: Error?
    private var targetApplication: NSRunningApplication?
    private lazy var coordinator: SelectionCoordinator = {
        let value = SelectionCoordinator(safety: { [weak self] in
            self?.currentSafety() ?? .init(paused: true, secureInput: false, accessibility: false, inputMonitoring: false, screenCapture: false)
        }, context: context, sender: Self.networkSender)
        value.onChange = { [weak self] in
            guard let self else { return }
            if [.cancelled, .failed, .completed].contains(self.coordinator.session.phase) { self.stopNativeEffects() }
            self.onChange?()
        }
        return value
    }()

    public init(voiceLocaleIdentifier: String? = nil, context: @escaping () async throws -> SelectionRequestContext) {
        self.context = context
        self.voice = LocalVoiceCapture(localeIdentifier: voiceLocaleIdentifier)
        voice.onTranscript = { [weak self] in self?.onTranscript?($0) }
        voice.onRecordingStarted = { [weak self] _ in self?.onRecordingChanged?(true) }
        voice.onRecordingEnded = { [weak self] in self?.onRecordingChanged?(false) }
        voice.onSafetyCancelled = { [weak self] in self?.cancel() }
        voice.onResolved = { [weak self] token, result in
            guard let self, let pending = self.voiceHandle, pending.token == token else { return }
            self.voiceHandle = nil
            guard self.voice.phase == .ready else {
                self.captureError = SelectionHostError.voiceUnavailable
                self.coordinator.voiceFailed(for: pending.gesture)
                return
            }
            let text: String?
            switch result {
            case .final(let value), .partial(let value): text = value
            case .unavailable:
                self.captureError = SelectionHostError.voiceUnavailable
                self.coordinator.voiceFailed(for: pending.gesture)
                return
            }
            // 'partial' here is the terminal best text after the recognizer's
            // finalization deadline. Live onTranscript updates never submit.
            self.coordinator.voiceFinished(text, for: pending.gesture)
        }
    }

    deinit { captureTask?.cancel() }

    /// Call only on an explicit new user gesture, before activating Lab's UI.
    /// listen=true starts local speech; its first use can request OS permission.
    @discardableResult public func begin(listen: Bool, defaultAction: SelectionAction? = nil) throws -> SelectionGesture {
        cancel()
        let safety = currentSafety()
        guard !paused else { throw IntentServiceError.inactiveSession }
        guard !safety.secureInput else { throw IntentServiceError.secureInput }
        guard safety.accessibility else { throw IntentServiceError.accessibilityPermission }
        guard safety.inputMonitoring else { throw IntentServiceError.inputPermission }
        targetApplication = NSWorkspace.shared.frontmostApplication
        captureError = nil
        let handle = coordinator.begin(voiceExpected: listen, defaultAction: defaultAction)
        // onChange is synchronous: the host may cancel/reconfigure while
        // observing holding. Never start audio for that invalidated handle.
        guard coordinator.session.gesture == handle, coordinator.session.phase == .holding,
              currentSafety().permits(.init(text: "")) else { throw CancellationError() }
        activeGesture = handle
        if listen {
            voice.start { [weak self] token in
                self?.voiceHandle = (token, handle)
            }
        }
        return handle
    }

    /// Submit exactly one final region/object when the hold key is released.
    /// The host's overlay can change freely before this call; it never captures
    /// or sends intermediate rectangles through this API.
    public func release(selection: SelectionInput) {
        guard let handle = activeGesture, coordinator.session.phase == .holding else { return }
        let languages = preferredOCRLanguages, target = targetApplication
        let awareness = awareness
        captureTask = Task { [weak self] in
            do {
                let content: SelectedContent
                switch selection {
                case .region(let bounds, let excluded):
                    let result = try await RegionCaptureService.capture(bounds, excludingWindowIDs: excluded, preferredLanguages: languages)
                    content = .init(text: result.text, imagePNG: result.imagePNG, requiresScreenPermission: true)
                case .accessibilityPoint(let point):
                    let result = try await awareness.snapshot(at: point)
                    content = .init(text: result.text.isEmpty ? result.name : result.text)
                case .selectedText:
                    content = .init(text: try SelectionCapture.selectedText(target: target))
                }
                try Task.checkCancellation()
                guard let self, self.activeGesture == handle else { return }
                guard self.currentSafety().permits(content) else { self.cancel(); return }
                self.captureTask = nil
                self.coordinator.captured(content, for: handle)
            } catch {
                guard let self, self.activeGesture == handle, !Task.isCancelled else { return }
                self.captureTask = nil; self.captureError = error
                self.coordinator.captured(nil, for: handle)
            }
        }
        coordinator.release(handle)
        if activeGesture == handle, voiceHandle?.gesture == handle { voice.finish() }
    }

    /// Used by Lab's fixed-action buttons or custom-question input.
    public func choose(_ action: SelectionAction) { captureError = nil; coordinator.choose(action) }

    /// Call on Esc, close, pause, lock/sleep, display changes or monitor failure.
    /// Also cancel/disarm the host's own gesture controller and selection overlay.
    public func cancel() { stopNativeEffects(); coordinator.cancel(); captureError = nil }

    /// Call when permissions/secure input change, including while capture waits.
    public func safetyDidChange() { coordinator.safetyDidChange() }

    private func stopNativeEffects() {
        activeGesture = nil; targetApplication = nil; voiceHandle = nil
        captureTask?.cancel(); captureTask = nil
        voice.cancel()
    }
    private func currentSafety() -> SelectionSafety {
        let value = SelectionPermissions.current()
        return .init(paused: paused, secureInput: value.secureInput, accessibility: value.accessibility,
                     inputMonitoring: value.inputMonitoring, screenCapture: value.screenRecording)
    }

    /// Original selection pixels remain in memory. Only the network copy is
    /// resized; fixed text actions with OCR never send an image at all.
    nonisolated private static let networkSender: SelectionCoordinator.Sender = { work, context, onDelta in
        let images: [AIImageAttachment]
        if work.includesImage, let png = work.content.imagePNG {
            let prepared = try await Task.detached(priority: .userInitiated) { try ScreenshotNetworkImage.prepare(png: png) }.value
            images = [.init(label: "Selected region", png: prepared)]
        } else { images = [] }
        try Task.checkCancellation()
        let prompt = try work.prompt(outputLanguage: context.outputLanguage, translationTargetLanguage: context.translationTargetLanguage)
        return try await AIClient().sendStreaming(configuration: context.configuration, prompt: prompt, images: images, apiKey: context.apiKey) { event in
            if case .delta(let text, _) = event { await onDelta(text) }
        }
    }
}
