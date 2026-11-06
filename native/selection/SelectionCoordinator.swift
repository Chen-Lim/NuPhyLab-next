import Foundation

public struct SelectionRequestContext {
    public let configuration: AIConfiguration
    public let apiKey: String
    public let outputLanguage: String
    public let translationTargetLanguage: String?
    public init(configuration: AIConfiguration, apiKey: String, outputLanguage: String, translationTargetLanguage: String? = nil) {
        self.configuration = configuration; self.apiKey = apiKey; self.outputLanguage = outputLanguage
        self.translationTargetLanguage = translationTargetLanguage
    }
}

/// A host UI observes state; native capture/STT callbacks supply effects through
/// session handles. The sole completion result is the validated AI return value.
/// Persist credentials in the host's Keychain, never in this in-memory context.
@MainActor public final class SelectionCoordinator {
    public typealias DeltaHandler = @Sendable (String) async -> Void
    public typealias Sender = @Sendable (SelectionWork, SelectionRequestContext, @escaping DeltaHandler) async throws -> String
    public private(set) var session = SelectionSession()
    public private(set) var lastError: Error?
    public var onChange: (() -> Void)?
    private let safety: () -> SelectionSafety
    private let context: () async throws -> SelectionRequestContext
    private let sender: Sender
    private var requestTask: Task<Void, Never>?
    private var previousSafety: SelectionSafety?

    public init(safety: @escaping () -> SelectionSafety,
                context: @escaping () async throws -> SelectionRequestContext,
                sender: @escaping Sender = SelectionCoordinator.sendWithAIKit) {
        self.safety = safety; self.context = context; self.sender = sender
    }

    deinit { requestTask?.cancel() }

    nonisolated public static let sendWithAIKit: Sender = { work, context, onDelta in
        let prompt = try work.prompt(outputLanguage: context.outputLanguage, translationTargetLanguage: context.translationTargetLanguage)
        return try await AIClient().sendStreaming(configuration: context.configuration, prompt: prompt,
            images: work.images, apiKey: context.apiKey) { event in
                if case .delta(let text, _) = event { await onDelta(text) }
            }
    }

    @discardableResult public func begin(voiceExpected: Bool, defaultAction: SelectionAction? = nil) -> SelectionGesture {
        requestTask?.cancel(); requestTask = nil; lastError = nil
        previousSafety = safety()
        let handle = session.begin(voiceExpected: voiceExpected, defaultAction: defaultAction)
        onChange?(); return handle
    }

    public func captured(_ content: SelectedContent?, for handle: SelectionGesture) {
        session.captured(content, for: handle); advance()
    }
    public func voiceFinished(_ text: String?, for handle: SelectionGesture) {
        session.voiceFinished(text, for: handle); advance()
    }
    public func voiceFailed(for handle: SelectionGesture) {
        session.voiceFailed(for: handle); advance()
    }
    public func release(_ handle: SelectionGesture) {
        session.release(handle); advance()
    }
    public func choose(_ action: SelectionAction) {
        session.choose(action); advance()
    }

    /// Call immediately on Esc, close, pause, lock/sleep or revoked permissions.
    /// The host must also stop its native monitor gesture, capture and microphone.
    public func cancel() {
        requestTask?.cancel(); requestTask = nil; session.cancel(); lastError = nil; onChange?()
    }

    public func safetyDidChange() {
        let current = safety()
        defer { previousSafety = current }
        guard session.gesture != nil else { return }
        // Revocation must invalidate a gesture even while capture is pending;
        // otherwise a late callback could revive it after permission returns.
        let content = session.content ?? SelectedContent(text: "")
        let screenRevokedWhilePending = session.content == nil
            && previousSafety?.screenCapture == true && !current.screenCapture
        if !current.permits(content) || screenRevokedWhilePending { cancel() }
    }

    private func advance() {
        do {
            guard let work = try session.takeWork(safety: safety()) else { onChange?(); return }
            lastError = nil
            if work.action == .extractText {
                session.complete(work.content.text, for: work)
                onChange?(); return
            }
            // Capture dependencies independently so waiting on a provider does
            // not retain this coordinator after the host closes the feature.
            let contextProvider = context, send = sender
            requestTask = Task { [weak self] in
                do {
                    let context = try await contextProvider()
                    try Task.checkCancellation()
                    guard self?.authorize(work) == true else { return }
                    let answer = try await send(work, context) { [weak self] delta in
                        await self?.receive(delta, for: work)
                    }
                    try Task.checkCancellation()
                    self?.finish(answer, for: work)
                } catch {
                    self?.failed(error, for: work)
                }
            }
            onChange?()
        } catch { lastError = error; onChange?() }
    }

    private func authorize(_ work: SelectionWork) -> Bool {
        guard session.accepts(work) else { return false }
        guard safety().permits(work.content) else { cancel(); return false }
        return true
    }
    private func receive(_ delta: String, for work: SelectionWork) {
        guard authorize(work) else { return }
        session.append(delta, for: work); onChange?()
    }
    private func finish(_ text: String, for work: SelectionWork) {
        guard authorize(work) else { return }
        session.complete(text, for: work); requestTask = nil; onChange?()
    }
    private func failed(_ error: Error, for work: SelectionWork) {
        guard session.accepts(work) else { return }
        session.fail(work); lastError = error; requestTask = nil; onChange?()
    }
}
