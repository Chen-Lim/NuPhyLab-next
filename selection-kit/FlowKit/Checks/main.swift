import Foundation
import LabSelectionAI
import LabSelectionFlow

enum CheckFailure: Error { case failed(String) }
actor Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var open = false
    func wait() async { if !open { await withCheckedContinuation { continuation = $0 } } }
    func release() { open = true; continuation?.resume(); continuation = nil }
}

@main struct FlowChecks {
    @MainActor static var checks = 0
    @MainActor static func expect(_ value: @autoclosure () -> Bool, _ label: String) throws {
        guard value() else { throw CheckFailure.failed(label) }
        checks += 1
    }
    @MainActor static func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition() {
            guard Date() < deadline else { throw CheckFailure.failed("Async fixture deadline") }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }
    @MainActor static func main() async throws {
        let allowed = SelectionSafety(paused: false, secureInput: false, accessibility: true, inputMonitoring: true, screenCapture: true)
        // Both possible completion orders, duplicate releases, terminal speech.
        for voiceFirst in [false, true] {
            var s = SelectionSession()
            let h = s.begin(voiceExpected: true, defaultAction: .summarize)
            s.release(h)
            let before = try s.takeWork(safety: allowed)
            try expect(before == nil, "No premature send")
            if voiceFirst { s.voiceFinished("Translate into French", for: h) }
            else { s.captured(.init(text: "document"), for: h) }
            let mid = try s.takeWork(safety: allowed)
            try expect(mid == nil, "Wait for both effects")
            if voiceFirst { s.captured(.init(text: "document"), for: h) }
            else { s.voiceFinished("Translate into French", for: h) }
            guard let work = try s.takeWork(safety: allowed) else { throw CheckFailure.failed("Missing work") }
            try expect(work.action == .ask(instruction: "Translate into French"), "Speech overrides default")
            s.release(h); s.voiceFinished("duplicate", for: h)
            let duplicate = try s.takeWork(safety: allowed)
            try expect(duplicate == nil, "Exactly one submission")
            s.append("partial", for: work)
            try expect(s.result.isEmpty && s.preview == "partial", "Partial is not completed answer")
            s.fail(work)
            try expect(s.preview.isEmpty && s.result.isEmpty, "Incomplete preview cleared")
            let autoRetry = try s.takeWork(safety: allowed)
            try expect(autoRetry == nil, "No implicit retry")
            s.choose(.rewrite)
            let manual = try s.takeWork(safety: allowed)
            try expect(manual != nil && manual?.requestID != work.requestID, "Explicit retry owns new ticket")
            s.cancel(); s.complete("late", for: work); s.captured(.init(text: "old"), for: h)
            try expect(s.phase == .cancelled && s.content == nil, "Cancellation invalidates all old effects")
        }
        // No speech/no configured default remains at a visible action choice.
        var s = SelectionSession()
        var h = s.begin(voiceExpected: false)
        s.captured(.init(text: "text"), for: h); s.release(h)
        let noAction = try s.takeWork(safety: allowed)
        try expect(noAction == nil && s.phase == .awaitingAction, "Silent no-default waits")
        s.choose(.translate(targetLanguage: "日本語"))
        let chosen = try s.takeWork(safety: allowed)
        try expect(chosen != nil, "Chosen action can submit")

        // Known sensitive states fail closed for the request; event tap itself
        // separately fails open for the user's ordinary keyboard/mouse input.
        for field in 0..<5 {
            h = s.begin(voiceExpected: false, defaultAction: .summarize)
            s.captured(.init(text: "screen", requiresScreenPermission: true), for: h); s.release(h)
            var blocked = allowed
            switch field {
            case 0: blocked.paused = true
            case 1: blocked.secureInput = true
            case 2: blocked.accessibility = false
            case 3: blocked.inputMonitoring = false
            default: blocked.screenCapture = false
            }
            let denied = try s.takeWork(safety: blocked)
            try expect(denied == nil && s.phase == .cancelled, "Safety state prevents submission")
        }
        h = s.begin(voiceExpected: false, defaultAction: .summarize)
        s.captured(.init(text: "AX text"), for: h); s.release(h)
        var textSafety = allowed; textSafety.screenCapture = false
        let ax = try s.takeWork(safety: textSafety)
        try expect(ax != nil, "AX-only content needs no screen permission")

        h = s.begin(voiceExpected: false, defaultAction: .translate(targetLanguage: "English"))
        s.captured(.init(text: "OCR", imagePNG: Data([1])), for: h); s.release(h)
        let transform = try s.takeWork(safety: allowed)!
        try expect(transform.images.isEmpty, "Fixed text transform sends OCR text only")
        s.fail(transform); s.choose(.ask(instruction: "Describe the photo"))
        let visual = try s.takeWork(safety: allowed)!
        try expect(visual.images.count == 1, "Visual question does not silently drop screenshot")
        let prompt = try visual.prompt(outputLanguage: "English", translationTargetLanguage: "German")
        try expect(prompt.user.contains("Describe the photo") && prompt.user.contains("OCR"), "Prompt contains task and quoted selection")

        h = s.begin(voiceExpected: false, defaultAction: .extractText)
        s.captured(.init(text: "", imagePNG: Data([1])), for: h); s.release(h)
        do { _ = try s.takeWork(safety: allowed); throw CheckFailure.failed("Empty OCR accepted") }
        catch SelectionFlowError.noRecognizedText { checks += 1 }
        h = s.begin(voiceExpected: false, defaultAction: .summarize)
        s.captured(nil, for: h); s.release(h)
        let failedCapture = try s.takeWork(safety: allowed)
        try expect(failedCapture == nil && s.phase == .failed, "Failed capture never sends")

        h = s.begin(voiceExpected: true, defaultAction: .summarize)
        s.captured(.init(text: "document"), for: h); s.release(h)
        s.voiceFailed(for: h)
        let failedSpeech = try s.takeWork(safety: allowed)
        try expect(failedSpeech == nil && s.phase == .awaitingAction, "Speech failure suppresses default and waits for an explicit action")
        s.choose(.ask(instruction: "Manually corrected question"))
        let corrected = try s.takeWork(safety: allowed)
        try expect(corrected?.action == .ask(instruction: "Manually corrected question"), "Explicit question can recover from speech failure")

        let context = SelectionRequestContext(configuration: .init(provider: .custom, endpoint: "https://fixture.invalid/v1/chat/completions", model: "fixture"), apiKey: "fixture-no-real-key", outputLanguage: "English")
        var contextReads = 0
        let local = SelectionCoordinator(safety: { allowed }, context: { contextReads += 1; return context }, sender: { _, _, _ in throw CheckFailure.failed("Local OCR invoked sender") })
        h = local.begin(voiceExpected: false, defaultAction: .extractText)
        local.captured(.init(text: "本机文字"), for: h); local.release(h)
        try expect(local.session.result == "本机文字" && contextReads == 0, "Local OCR bypasses credentials and network")

        // A transient revoke while the capture is pending cannot be undone by
        // restoring permissions before an old callback arrives.
        for field in 0..<5 {
            var state = allowed
            var touchedContext = false
            let pending = SelectionCoordinator(safety: { state }, context: { touchedContext = true; return context }, sender: { _, _, _ in "unexpected" })
            let old = pending.begin(voiceExpected: false, defaultAction: .summarize)
            pending.release(old)
            switch field {
            case 0: state.paused = true
            case 1: state.secureInput = true
            case 2: state.accessibility = false
            case 3: state.inputMonitoring = false
            default: state.screenCapture = false
            }
            pending.safetyDidChange()
            state = allowed; pending.safetyDidChange()
            pending.captured(.init(text: "late OCR", requiresScreenPermission: true), for: old)
            try expect(pending.session.phase == .cancelled && pending.session.content == nil && !touchedContext, "Pending gesture stays cancelled after a transient revoke")
        }

        var loaded = false, sent = false
        let gate = Gate()
        let cancellable = SelectionCoordinator(safety: { allowed }, context: { loaded = true; await gate.wait(); return context }, sender: { _, _, _ in
            await MainActor.run { sent = true }; return "should not run"
        })
        h = cancellable.begin(voiceExpected: false, defaultAction: .summarize)
        cancellable.captured(.init(text: "text"), for: h); cancellable.release(h)
        try await waitUntil { loaded }; cancellable.cancel(); await gate.release()
        try await Task.sleep(nanoseconds: 10_000_000)
        try expect(!sent && cancellable.session.phase == .cancelled, "Cancel during credential lookup prevents HTTP")

        var permission = true, started = false
        let gate2 = Gate()
        let revoke = SelectionCoordinator(safety: { var v = allowed; v.screenCapture = permission; return v }, context: { started = true; await gate2.wait(); return context }, sender: { _, _, _ in
            await MainActor.run { sent = true }; return "should not run"
        })
        h = revoke.begin(voiceExpected: false, defaultAction: .summarize)
        revoke.captured(.init(text: "OCR", requiresScreenPermission: true), for: h); revoke.release(h)
        try await waitUntil { started }; permission = false; await gate2.release()
        try await waitUntil { revoke.session.phase == .cancelled }
        try expect(!sent, "Permission recheck after credential lookup prevents HTTP")

        let gate3 = Gate()
        let streamed = SelectionCoordinator(safety: { allowed }, context: { context }, sender: { _, _, delta in
            await delta("partial"); await gate3.wait(); return "complete"
        })
        h = streamed.begin(voiceExpected: false, defaultAction: .summarize)
        streamed.captured(.init(text: "document"), for: h); streamed.release(h)
        try await waitUntil { streamed.session.preview == "partial" }
        try expect(streamed.session.result.isEmpty, "Streaming preview is not copyable result")
        await gate3.release(); try await waitUntil { streamed.session.phase == .completed }
        try expect(streamed.session.result == "complete" && streamed.session.preview.isEmpty, "Validated terminal commits full result")
        print("FlowChecks: \(checks) assertions passed. Synthetic state/async effects; no live capture, microphone, Keychain or API calls.")
    }
}
