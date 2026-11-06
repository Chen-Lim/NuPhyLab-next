import XCTest
import CoreGraphics
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import LabSelectionNative

final class NativeCoreTests: XCTestCase {
    func testReservedSystemBindingsRejected() {
        XCTAssertEqual(InputBindingPolicy.issue(for: .keyboard(keyCode: 48, modifiers: .command)), .reservedSystemInput)
        XCTAssertEqual(InputBindingPolicy.issue(for: .keyboard(keyCode: 12, modifiers: [.control, .command])), .reservedSystemInput)
        XCTAssertEqual(InputBindingPolicy.issue(for: .keyboard(keyCode: 53)), .escapeReserved)
        XCTAssertEqual(InputBindingPolicy.issue(for: .keyboard(keyCode: 57)), .capsLockToggle)
        XCTAssertEqual(InputBindingPolicy.issue(for: .mouseButton(index: 0)), .invalidMouseButton)
        XCTAssertNil(InputBindingPolicy.issue(for: .mouseButton(index: 3)))
        XCTAssertNil(InputBindingPolicy.issue(for: .fnGlobe))
    }
    func testSideButtonOwnsExactPairOnly() {
        var bridge = IntentInputBridge()
        let binding = InputBinding.mouseButton(index: 3)
        XCTAssertFalse(bridge.handle(input: .mouse(4), edge: .down, modifiers: [], binding: binding, allowed: true).consumes)
        let down = bridge.handle(input: .mouse(3), edge: .down, modifiers: [], binding: binding, allowed: true, point: .init(x: 10, y: 12))
        XCTAssertTrue(down.consumes); XCTAssertEqual(down.event?.edge, .began)
        XCTAssertFalse(bridge.handle(input: .key(0), edge: .down, modifiers: [], binding: binding, allowed: true).consumes)
        let up = bridge.handle(input: .mouse(3), edge: .up, modifiers: [], binding: binding, allowed: true, point: .init(x: 40, y: 50))
        XCTAssertEqual(up.event?.point, .init(x: 40, y: 50)); XCTAssertEqual(up.event?.token, down.event?.token)
        XCTAssertEqual(up.event?.edge, .released)
        XCTAssertNil(bridge.handle(input: .mouse(3), edge: .up, modifiers: [], binding: binding, allowed: true).event)
    }
    func testSafetyCancellationCannotReviveOldPress() {
        var bridge = IntentInputBridge()
        let binding = InputBinding.mouseButton(index: 4)
        let down = bridge.handle(input: .mouse(4), edge: .down, modifiers: [], binding: binding, allowed: true)
        XCTAssertEqual(bridge.pointerMoved(.init(x: 1, y: 1), allowed: false).event?.edge, .cancelled)
        XCTAssertNil(bridge.pointerMoved(.init(x: 2, y: 2), allowed: true).event)
        XCTAssertNil(bridge.handle(input: .mouse(4), edge: .up, modifiers: [], binding: binding, allowed: true).event)
        bridge.invalidate()
        XCTAssertFalse(bridge.accepts(down.event!))
    }
    func testLateFinishCannotCancelNewPress() {
        var bridge = IntentInputBridge()
        let binding = InputBinding.keyboard(keyCode: 50)
        let old = bridge.handle(input: .key(50), edge: .down, modifiers: [], binding: binding, allowed: true).event!.token
        _ = bridge.handle(input: .key(50), edge: .up, modifiers: [], binding: binding, allowed: true)
        let new = bridge.handle(input: .key(50), edge: .down, modifiers: [], binding: binding, allowed: true).event!.token
        bridge.finish(old)
        XCTAssertEqual(bridge.activePress, new)
    }
    func testFnRequiresActualModifierEdge() {
        var bridge = IntentInputBridge()
        XCTAssertNil(bridge.handle(input: .key(122), edge: .down, modifiers: .function, binding: .fnGlobe, allowed: true).event)
        XCTAssertEqual(bridge.flagsChanged(keyCode: 63, modifiers: .function, binding: .fnGlobe, allowed: true).event?.edge, .began)
        let typing = bridge.handle(input: .key(0), edge: .down, modifiers: .function, binding: .fnGlobe, allowed: true)
        XCTAssertEqual(typing.event?.edge, .cancelled); XCTAssertFalse(typing.consumes)
        XCTAssertNil(bridge.flagsChanged(keyCode: 63, modifiers: .function, binding: .fnGlobe, allowed: true).event)
        _ = bridge.flagsChanged(keyCode: 63, modifiers: [], binding: .fnGlobe, allowed: true)
        XCTAssertEqual(bridge.flagsChanged(keyCode: 63, modifiers: .function, binding: .fnGlobe, allowed: true).event?.edge, .began)
    }
    func testMoveCoalescingDropsPendingMovementAtRelease() {
        var bridge = IntentInputBridge(), buffer = IntentPointerMoveBuffer()
        let binding = InputBinding.mouseButton(index: 4)
        let token = bridge.handle(input: .mouse(4), edge: .down, modifiers: [], binding: binding, allowed: true).event!.token
        XCTAssertTrue(buffer.offer(bridge.movement(.init(x: 10, y: 10))!))
        XCTAssertFalse(buffer.offer(bridge.movement(.init(x: 20, y: 20))!))
        XCTAssertEqual(buffer.take(token)?.point, .init(x: 20, y: 20))
        _ = buffer.offer(bridge.movement(.init(x: 30, y: 30))!)
        buffer.discard(token)
        XCTAssertNil(buffer.take(token))
    }
    func testSideGeometryClampsToOriginalDisplay() {
        var bridge = IntentInputBridge(), geometry = IntentSideSelectionState()
        let token = bridge.handle(input: .mouse(3), edge: .down, modifiers: [], binding: .mouseButton(index: 3), allowed: true).event!.token
        geometry.begin(token, at: .init(x: 20, y: 20), screen: .init(x: 0, y: 0, width: 100, height: 100))
        geometry.move(.init(x: 200, y: 200), token: token)
        XCTAssertEqual(geometry.finish(token), .region(.init(x: 20, y: 20, width: 80, height: 80)))
        XCTAssertNil(geometry.finish(token))
    }
    func testPointerJitterKeepsObjectSelection() {
        var bridge = IntentInputBridge(), geometry = IntentSideSelectionState()
        let token = bridge.handle(input: .mouse(3), edge: .down, modifiers: [], binding: .mouseButton(index: 3), allowed: true).event!.token
        geometry.begin(token, at: .init(x: 20, y: 20), screen: .init(x: 0, y: 0, width: 100, height: 100))
        geometry.move(.init(x: 21, y: 21), token: token)
        XCTAssertEqual(geometry.finish(token), .object(.init(x: 20, y: 20)))
    }
    func testCaptureGeometryAndPixelBudgets() throws {
        let dimensions = try RegionCaptureService.pixelDimensions(width: 500, height: 300, scale: 2)
        XCTAssertEqual(dimensions.width, 1000); XCTAssertEqual(dimensions.height, 600)
        XCTAssertThrowsError(try RegionCaptureService.pixelDimensions(width: .infinity, height: 1, scale: 2))
        XCTAssertThrowsError(try RegionCaptureService.pixelDimensions(width: 5000, height: 4000, scale: 2))
        XCTAssertFalse(IntentBounds(x: 0, y: 0, width: 7, height: 10).isCapturableRegion)
        XCTAssertFalse(IntentBounds(x: .nan, y: 0, width: 30, height: 30).isUsable)
    }
    func testProtectedTextMetadata() {
        XCTAssertTrue(IntentTextSafety.isProtected(role: "AXSecureTextField", subrole: nil))
        XCTAssertTrue(IntentTextSafety.isProtected(role: "AXTextField", subrole: "AXSecureTextField"))
        XCTAssertTrue(IntentTextSafety.isProtected(role: nil, subrole: nil, inputType: "PASSWORD"))
        XCTAssertEqual(IntentTextSafety.limited(String(repeating: "字", count: 25_000)).count, 20_000)
    }
    func testVoiceGenerationRejectsCancelledTranscript() {
        var state = VoiceSession()
        let old = state.begin(objectIDs: [UUID()]); XCTAssertTrue(state.authorized(generation: old))
        state.cancel()
        XCTAssertFalse(state.update("late", generation: old, final: true))
        let new = state.begin(objectIDs: []); XCTAssertTrue(state.authorized(generation: new))
        XCTAssertFalse(state.bindObjects([UUID()], generation: old))
        XCTAssertTrue(state.update("Translate this", generation: new, final: false))
        state.stop(); XCTAssertEqual(state.phase, .finishing)
        XCTAssertTrue(state.update("Translate this paragraph", generation: new, final: true))
        XCTAssertEqual(state.phase, .ready)
    }
    func testVoiceLeaseStopDuringStartupInvalidatesImmediately() {
        let lease = VoiceAudioLease(); lease.stopInput()
        XCTAssertFalse(lease.isValid); XCTAssertFalse(lease.permitsBuffers)
        XCTAssertThrowsError(try lease.checkCancellation())
    }
    func testPartialAudioInstallationHasExactlyOneCleanup() {
        var lifecycle = VoiceInputLifecycle(), removals = 0
        XCTAssertThrowsError(try lifecycle.install(sampleRate: 48_000, channelCount: 1, install: { false }, remove: { removals += 1 }))
        lifecycle.stop { removals += 1 }
        XCTAssertEqual(removals, 1)
    }
    func testSpeechFormattingPreservesEnglishAndNumbers() {
        XCTAssertEqual(SpeechRecognitionPolicy.formattedTranscript("Translate 12.5 USD", chinese: false), "Translate 12.5 USD")
        XCTAssertEqual(SpeechRecognitionPolicy.formattedTranscript("翻译 这 段 文字", chinese: true), "翻译这段文字")
        var accumulator = SpeechTranscriptAccumulator()
        XCTAssertEqual(accumulator.receive("First. ", final: true), "First. ")
        XCTAssertEqual(accumulator.receive("Next", final: false), "First. Next")
        XCTAssertEqual(accumulator.receive("Second.", final: true), "First. Second.")
    }
    #if DEBUG
    func testAdapterDrainsCancelledSideUpAndInvalidatesCallbacks() throws {
        let receiver = IntentBindingReceiver()
        receiver.binding = .mouseButton(index: 3); receiver.enabled = true; receiver.testSafetyAllowed = true
        var events: [IntentPressEvent] = []
        receiver.onPress = { events.append($0) }
        let down = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown,
            mouseCursorPosition: .zero, mouseButton: .center))
        down.setIntegerValueField(.mouseEventButtonNumber, value: 3); down.timestamp = 100
        XCTAssertTrue(receiver.receive(.otherMouseDown, event: down))
        XCTAssertEqual(events.map(\.edge), [.began])
        receiver.cancelLogical(); receiver.enabled = false
        let up = try XCTUnwrap(down.copy()); up.type = .otherMouseUp; up.timestamp = 200
        XCTAssertTrue(receiver.receive(.otherMouseUp, event: up))
        XCTAssertEqual(events.map(\.edge), [.began])
        XCTAssertTrue(receiver.hasOwnedInput)
        receiver.observeSidePhysicalState(3, isPressed: false, at: 1)
        receiver.observeSidePhysicalState(3, isPressed: false, at: 1.4)
        XCTAssertFalse(receiver.hasOwnedInput)
        let gate = IntentTapCallbackContext(receiver: receiver); gate.invalidate()
        XCTAssertTrue(gate.receive(.otherMouseDown, event: down)?.takeUnretainedValue() === down)
        XCTAssertEqual(events.count, 1)
    }
    #endif
    func testNetworkPNGPreparationPreservesOriginalAndBounds() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 2300, height: 100, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.7, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2300, height: 100))
        let pixels = try XCTUnwrap(context.makeImage()), data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, pixels, nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
        let original = data as Data, retained = original
        let output = try ScreenshotNetworkImage.prepare(png: original)
        XCTAssertEqual(original, retained); XCTAssertLessThanOrEqual(output.count, ScreenshotNetworkImage.maximumBytes)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(output as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 2048)
        XCTAssertThrowsError(try ScreenshotNetworkImage.prepare(png: Data()))
    }
}
