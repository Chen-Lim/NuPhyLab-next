import XCTest
import LabSelectionAI
@testable import LabSelectionFlow

private actor Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false
    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() { opened = true; continuation?.resume(); continuation = nil }
}

@MainActor final class SelectionCoordinatorTests: XCTestCase {
    private var safety: SelectionSafety { .init(paused: false, secureInput: false, accessibility: true, inputMonitoring: true, screenCapture: true) }
    private func context() -> SelectionRequestContext {
        .init(configuration: .init(provider: .custom, endpoint: "https://fixture.invalid/v1/chat/completions", model: "fixture"),
              apiKey: "fixture-key-not-a-secret", outputLanguage: "English")
    }

    func testOCRReturnsLocallyWithoutCredentialOrNetworkAccess() {
        let coordinator = SelectionCoordinator(safety: { self.safety }, context: {
            XCTFail("Local OCR must not read credentials"); return self.context()
        }, sender: { _, _, _ in XCTFail("Local OCR must not send requests"); return "" })
        let handle = coordinator.begin(voiceExpected: false, defaultAction: .extractText)
        coordinator.captured(.init(text: "原始文字"), for: handle); coordinator.release(handle)
        XCTAssertEqual(coordinator.session.result, "原始文字")
        XCTAssertEqual(coordinator.session.phase, .completed)
    }

    func testStreamingPreviewBecomesCopyableOnlyAfterSuccessfulTerminal() async {
        let preview = expectation(description: "preview")
        let completed = expectation(description: "completed")
        let gate = Gate()
        let coordinator = SelectionCoordinator(safety: { self.safety }, context: { self.context() }, sender: { _, _, delta in
            await delta("part"); await gate.wait(); return "complete answer"
        })
        coordinator.onChange = {
            if coordinator.session.preview == "part" { preview.fulfill() }
            if coordinator.session.phase == .completed { completed.fulfill() }
        }
        let handle = coordinator.begin(voiceExpected: false, defaultAction: .summarize)
        coordinator.captured(.init(text: "document"), for: handle); coordinator.release(handle)
        await fulfillment(of: [preview], timeout: 3)
        XCTAssertEqual(coordinator.session.result, "")
        await gate.open(); await fulfillment(of: [completed], timeout: 3)
        XCTAssertEqual(coordinator.session.result, "complete answer")
        coordinator.onChange = nil
    }

    func testCancellationWhileLoadingCredentialsNeverStartsRequest() async {
        let started = expectation(description: "credential loading")
        let resumed = expectation(description: "credential released")
        let gate = Gate()
        let coordinator = SelectionCoordinator(safety: { self.safety }, context: {
            started.fulfill(); await gate.wait(); resumed.fulfill(); return self.context()
        }, sender: { _, _, _ in XCTFail("Cancelled context must not start HTTP"); return "" })
        let handle = coordinator.begin(voiceExpected: false, defaultAction: .summarize)
        coordinator.captured(.init(text: "document"), for: handle); coordinator.release(handle)
        await fulfillment(of: [started], timeout: 3)
        coordinator.cancel(); await gate.open(); await fulfillment(of: [resumed], timeout: 3)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(coordinator.session.phase, .cancelled)
    }

    func testPermissionRecheckAfterCredentialLoadPreventsRequest() async {
        var permitted = true
        let started = expectation(description: "credential loading")
        let cancelled = expectation(description: "cancelled")
        let gate = Gate()
        let coordinator = SelectionCoordinator(safety: {
            var value = self.safety; value.screenCapture = permitted; return value
        }, context: {
            started.fulfill(); await gate.wait(); return self.context()
        }, sender: { _, _, _ in XCTFail("Revoked screen permission must block HTTP"); return "" })
        coordinator.onChange = { if coordinator.session.phase == .cancelled { cancelled.fulfill() } }
        let handle = coordinator.begin(voiceExpected: false, defaultAction: .summarize)
        coordinator.captured(.init(text: "screen text", requiresScreenPermission: true), for: handle); coordinator.release(handle)
        await fulfillment(of: [started], timeout: 3)
        permitted = false; await gate.open(); await fulfillment(of: [cancelled], timeout: 3)
        coordinator.onChange = nil
    }

    func testTransientRevocationWhileCapturePendingInvalidatesGesture() {
        for field in 0..<5 {
            var state = safety
            let coordinator = SelectionCoordinator(safety: { state }, context: {
                XCTFail("An invalidated capture must never load credentials"); return self.context()
            }, sender: { _, _, _ in XCTFail("Old gesture revived"); return "" })
            let handle = coordinator.begin(voiceExpected: false, defaultAction: .summarize)
            coordinator.release(handle)
            switch field {
            case 0: state.paused = true
            case 1: state.secureInput = true
            case 2: state.accessibility = false
            case 3: state.inputMonitoring = false
            default: state.screenCapture = false
            }
            coordinator.safetyDidChange()
            state = safety; coordinator.safetyDidChange()
            coordinator.captured(.init(text: "late", requiresScreenPermission: true), for: handle)
            XCTAssertEqual(coordinator.session.phase, .cancelled)
            XCTAssertNil(coordinator.session.content)
        }
    }
}
