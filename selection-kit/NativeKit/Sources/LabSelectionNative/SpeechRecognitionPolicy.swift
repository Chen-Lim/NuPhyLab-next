// Adapted from apps/macos/Sources/Chord/AI/SpeechRecognitionPolicy.swift.
// Standalone single-selection extraction; see source-provenance.json for changes and hashes.
import Foundation
import Speech

enum SpeechRecognitionPurpose: Sendable { case command }

/// Recognition hints affect the acoustic/language model. They never rewrite a
/// transcript, so legitimate homophones remain intact in spoken instructions.
enum SpeechRecognitionPolicy {
    static func localeIdentifier(chinese: Bool, preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        let language = chinese ? "zh" : "en"
        return preferredLanguages.first {
            let locale = Locale(identifier: $0)
            return locale.language.languageCode?.identifier == language && locale.region != nil
        } ?? (chinese ? "zh-CN" : "en-US")
    }

    static func contextualStrings(_ phrases: [String], purpose: SpeechRecognitionPurpose, chinese: Bool) -> [String] {
        let commands = purpose == .command ? (chinese
            ? ["翻译", "总结", "解释", "改写", "提问"]
            : ["translate", "summarize", "explain", "rewrite", "ask"]) : []
        var seen = Set<String>()
        // Prefer actual user-selected text over general command vocabulary.
        return (Array(phrases.prefix(100)) + commands).compactMap { phrase in
            let cleaned = phrase.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }.joined(separator: " ")
            guard !cleaned.isEmpty, cleaned.count <= 80,
                  !cleaned.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  seen.insert(cleaned).inserted else { return nil }
            return cleaned
        }.prefix(100).map { $0 }
    }

    static func configure(_ request: SFSpeechRecognitionRequest, purpose: SpeechRecognitionPurpose, context: [String]) {
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        // A full instruction ("replace the first heading with…") is not a
        // yes/no confirmation or a search query.
        request.taskHint = .unspecified
        request.contextualStrings = context
    }

    /// Actual finals resolve immediately. A busy local model gets time to drain
    /// its last audio instead of being cancelled at the former two-second limit.
    static func finalizationTimeout(recordedSeconds: TimeInterval) -> TimeInterval {
        recordedSeconds > 20 ? 10 : 6
    }

    /// SpeechTranscriber can insert Latin-style spaces around Chinese tokens
    /// and full-width punctuation. Normalize typography only, never words,
    /// numbers, homophones, punctuation choice, or spaces within Latin text.
    static func formattedTranscript(_ text: String, chinese: Bool) -> String {
        guard chinese else { return text }
        return chineseSpacing.reduce(text) { value, expression in
            expression.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: "")
        }
    }
    private static let chineseSpacing = [
        #"(?<=\p{Han})[\t ]+(?=[\p{Han}\p{N}])"#,
        #"(?<=\p{N})[\t ]+(?=\p{Han})"#,
        #"[\t ]+(?=[，。！？；：、）】》])"#,
        #"(?<=[，。！？；：、（【《])[\t ]+(?=\p{Han})"#
    ].compactMap { try? NSRegularExpression(pattern: $0) }
}

/// An ephemeral, per-recording context shared with the serial worker. No screen
/// reading or persistence occurs here; only an explicitly selected target can
/// supply phrases. The observer is invoked outside this short state lock.
final class VoiceRecognitionContext: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [String]
    private var observer: (@Sendable ([String]) -> Void)?
    init(_ strings: [String]) { value = strings }
    var strings: [String] { lock.lock(); defer { lock.unlock() }; return value }
    func update(_ strings: [String]) {
        lock.lock(); value = strings; let observer = observer; lock.unlock()
        observer?(strings)
    }
    func observe(_ observer: (@Sendable ([String]) -> Void)?) {
        lock.lock(); self.observer = observer; let value = value; lock.unlock()
        observer?(value)
    }
}

/// SpeechTranscriber reports finalized *segments*, not a completed recording.
/// Keep every finalized segment and replace the volatile suffix as it revises.
struct SpeechTranscriptAccumulator {
    private(set) var finalized = ""
    private(set) var volatile = ""
    mutating func receive(_ text: String, final: Bool) -> String {
        if final { finalized = String((finalized + text).prefix(16_000)); volatile = "" }
        else { volatile = String(text.prefix(max(0, 16_000 - finalized.count))) }
        return String((finalized + volatile).prefix(16_000))
    }
    var completeText: String { finalized }
}
