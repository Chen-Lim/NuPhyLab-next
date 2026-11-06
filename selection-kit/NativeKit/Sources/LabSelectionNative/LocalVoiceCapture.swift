// Adapted from apps/macos/Sources/Chord/AI/VoiceCaptureService.swift, apps/macos/Sources/ChordCore/InteractionSession.swift, apps/macos/Sources/ChordCore/InteractionDiagnostics.swift.
// Standalone single-selection extraction; see source-provenance.json for changes and hashes.
import Foundation
import Speech

public enum InteractionTranscript: Equatable, Sendable {
    case final(String), partial(String), unavailable
}

/// A no-UI facade over the extracted production speech worker. The host owns
/// permission explanations, recording feedback and prompt submission policy.
@MainActor public final class LocalVoiceCapture {
    private let service = VoiceCaptureService()
    public var onTranscript: ((String) -> Void)?
    public var onRecordingStarted: ((UUID) -> Void)?
    public var onRecordingEnded: (() -> Void)?
    public var onResolved: ((UUID, InteractionTranscript) -> Void)?
    public var onSafetyCancelled: (() -> Void)?
    public var language: AppLanguage = .en { didSet { service.language = language } }
    public var localeIdentifier: String? { didSet { service.localeIdentifierOverride = localeIdentifier } }
    public var phase: VoicePhase { service.session.phase }
    public var transcript: String { service.session.transcript }
    public var statusText: String { service.statusText }
    public var issue: String? { service.issue }

    public init(localeIdentifier: String? = nil) {
        self.localeIdentifier = localeIdentifier
        service.localeIdentifierOverride = localeIdentifier
        service.onTranscript = { [weak self] in self?.onTranscript?($0) }
        service.onRecordingStarted = { [weak self] in self?.onRecordingStarted?($0) }
        service.onRecordingEnded = { [weak self] in self?.onRecordingEnded?() }
        service.onResolved = { [weak self] in self?.onResolved?($0, $1) }
        service.onSafetyCancelled = { [weak self] in self?.onSafetyCancelled?() }
    }

    /// Captures microphone only. The first user-requested start may prompt for
    /// microphone/speech access. This package does not call start in tests.
    @discardableResult public func start(objectIDs: [UUID] = [], onPrepared: ((UUID) -> Void)? = nil) -> UUID {
        service.start(objectIDs: objectIDs, onPrepared: onPrepared)
        return service.session.generation
    }
    public func finish() { service.stop() }
    public func cancel() { service.cancel() }
    public func updateContext(_ phrases: [String], token: UUID) { service.updateRecognitionContext(phrases, token: token) }

    /// Speech framework language inventory, not a claim that local models are
    /// installed. On-device availability is checked again at actual startup.
    public static var supportedLocaleIdentifiers: [String] { SFSpeechRecognizer.supportedLocales().map(\.identifier).sorted() }
}

// Fixed speech timing metadata only. No user content, transcript or keys.
enum InteractionDiagnosticEvent: String, Sendable {
    case audioEngineCreated, audioInputFormat, audioTapInstalled, audioRecognitionStarted
    case audioEnginePrepared, audioEngineStarted, audioEngineStopped, audioTapRemoved, audioRecognitionCancelled
}
struct InteractionDiagnosticSample: Sendable {
    let event: InteractionDiagnosticEvent
    let uptime: TimeInterval
    let duration: TimeInterval?
    let generation: UInt64?
    init(event: InteractionDiagnosticEvent, uptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
         duration: TimeInterval? = nil, generation: UInt64? = nil) {
        self.event = event; self.uptime = uptime; self.duration = duration; self.generation = generation
    }
}
