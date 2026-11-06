import XCTest
@testable import LabSelectionFlow

final class SelectionSessionTests: XCTestCase {
    private let allowed = SelectionSafety(paused: false, secureInput: false, accessibility: true, inputMonitoring: true, screenCapture: true)

    func testReleaseWaitsForCaptureAndFinalSpeechAndOnlySendsOnce() throws {
        var session = SelectionSession()
        let handle = session.begin(voiceExpected: true, defaultAction: .translate(targetLanguage: "English"))
        session.release(handle)
        XCTAssertNil(try session.takeWork(safety: allowed))
        session.captured(.init(text: "文档正文"), for: handle)
        XCTAssertNil(try session.takeWork(safety: allowed))
        session.voiceFinished("请总结", for: handle)
        let work = try XCTUnwrap(session.takeWork(safety: allowed))
        XCTAssertEqual(work.action, .ask(instruction: "请总结"))
        session.release(handle); session.voiceFinished("请总结", for: handle)
        XCTAssertNil(try session.takeWork(safety: allowed))
    }

    func testCaptureAndSpeechMayFinishBeforeRelease() throws {
        var session = SelectionSession()
        let handle = session.begin(voiceExpected: true)
        session.voiceFinished("Explain this", for: handle)
        session.captured(.init(text: "x"), for: handle)
        XCTAssertNil(try session.takeWork(safety: allowed))
        session.release(handle)
        XCTAssertNotNil(try session.takeWork(safety: allowed))
    }

    func testSilentGestureWaitsForChosenAction() throws {
        var session = SelectionSession()
        let handle = session.begin(voiceExpected: false)
        session.captured(.init(text: "Selected text"), for: handle); session.release(handle)
        XCTAssertNil(try session.takeWork(safety: allowed))
        session.choose(.summarize)
        XCTAssertEqual(try session.takeWork(safety: allowed)?.action, .summarize)
    }

    func testCancelledAndOldCallbacksCannotReviveSelection() throws {
        var session = SelectionSession()
        let old = session.begin(voiceExpected: true, defaultAction: .summarize)
        session.cancel()
        session.captured(.init(text: "old"), for: old); session.voiceFinished("old", for: old); session.release(old)
        XCTAssertEqual(session.phase, .cancelled)
        let new = session.begin(voiceExpected: false, defaultAction: .rewrite)
        session.captured(.init(text: "old"), for: old)
        XCTAssertNil(session.content)
        session.captured(.init(text: "new"), for: new); session.release(new)
        XCTAssertEqual(try session.takeWork(safety: allowed)?.content.text, "new")
    }

    func testLateResponseCannotModifyNewSession() throws {
        var session = SelectionSession()
        let old = session.begin(voiceExpected: false, defaultAction: .summarize)
        session.captured(.init(text: "old"), for: old); session.release(old)
        let work = try XCTUnwrap(session.takeWork(safety: allowed))
        _ = session.begin(voiceExpected: false)
        session.append("late", for: work); session.complete("late", for: work); session.fail(work)
        XCTAssertEqual(session.phase, .holding); XCTAssertEqual(session.result, ""); XCTAssertEqual(session.preview, "")
    }

    func testRevokedPermissionsCancelBeforeSubmission() throws {
        var session = SelectionSession()
        let handle = session.begin(voiceExpected: false, defaultAction: .summarize)
        session.captured(.init(text: "screen OCR", requiresScreenPermission: true), for: handle); session.release(handle)
        var safety = allowed; safety.screenCapture = false
        XCTAssertNil(try session.takeWork(safety: safety)); XCTAssertEqual(session.phase, .cancelled)
    }

    func testAXTextDoesNotRequireScreenPermission() throws {
        var session = SelectionSession()
        let handle = session.begin(voiceExpected: false, defaultAction: .summarize)
        session.captured(.init(text: "AX selected text"), for: handle); session.release(handle)
        var safety = allowed; safety.screenCapture = false
        XCTAssertNotNil(try session.takeWork(safety: safety))
    }

    func testTextActionsAvoidImageUploadButVisualAskKeepsImage() throws {
        var session = SelectionSession()
        let handle = session.begin(voiceExpected: false, defaultAction: .translate(targetLanguage: "English"))
        session.captured(.init(text: "OCR", imagePNG: Data([1])), for: handle); session.release(handle)
        let textWork = try XCTUnwrap(session.takeWork(safety: allowed))
        XCTAssertFalse(textWork.includesImage)
        session.fail(textWork); session.choose(.ask(instruction: "What is in this photo?"))
        XCTAssertTrue(try XCTUnwrap(session.takeWork(safety: allowed)).includesImage)
    }

    func testEmptyOCRCannotReturnFakeLocalSuccess() throws {
        var session = SelectionSession()
        let handle = session.begin(voiceExpected: false, defaultAction: .extractText)
        session.captured(.init(text: "", imagePNG: Data([1])), for: handle); session.release(handle)
        XCTAssertThrowsError(try session.takeWork(safety: allowed)) { XCTAssertEqual($0 as? SelectionFlowError, .noRecognizedText) }
        XCTAssertEqual(session.phase, .awaitingAction)
    }

    func testFailedCaptureRequiresNewGesture() throws {
        var session = SelectionSession()
        let handle = session.begin(voiceExpected: false, defaultAction: .summarize)
        session.captured(nil, for: handle); session.release(handle); session.choose(.summarize)
        XCTAssertEqual(session.phase, .failed); XCTAssertNil(try session.takeWork(safety: allowed))
    }

    func testIncompleteAnswerIsClearedOnFailureAndManualRetryIsExplicit() throws {
        var session = SelectionSession()
        let handle = session.begin(voiceExpected: false, defaultAction: .summarize)
        session.captured(.init(text: "document"), for: handle); session.release(handle)
        let work = try XCTUnwrap(session.takeWork(safety: allowed))
        session.append("partial", for: work); XCTAssertEqual(session.result, "")
        session.fail(work); XCTAssertEqual(session.preview, ""); XCTAssertEqual(session.result, "")
        XCTAssertNil(try session.takeWork(safety: allowed))
        session.choose(.summarize)
        XCTAssertNotEqual(try session.takeWork(safety: allowed)?.requestID, work.requestID)
    }

    func testMissingTargetAndEmptyQuestionStayEditable() throws {
        var session = SelectionSession()
        let handle = session.begin(voiceExpected: false, defaultAction: .translate(targetLanguage: ""))
        session.captured(.init(text: "document"), for: handle); session.release(handle)
        XCTAssertThrowsError(try session.takeWork(safety: allowed))
        session.choose(.ask(instruction: "  "))
        XCTAssertThrowsError(try session.takeWork(safety: allowed))
        session.choose(.translate(targetLanguage: "日本語"))
        XCTAssertNotNil(try session.takeWork(safety: allowed))
    }
}
