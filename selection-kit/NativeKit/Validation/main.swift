import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import LabSelectionNative

// Standalone executable checks, not XCTest. It uses only public APIs and
// synthetic data. No event tap, TCC request, screenshot or microphone starts.
var checkCount = 0
func verify(_ condition: @autoclosure () -> Bool, _ message: String, line: UInt = #line) {
    checkCount += 1
    guard condition() else { fatalError("Validation failed at line \(line): \(message)") }
}
func expectFailure(_ message: String, _ block: () throws -> Void) {
    do { try block(); verify(false, message) } catch { verify(true, message) }
}
func validateBindingsAndOwnership() {
    verify(InputBindingPolicy.issue(for: .keyboard(keyCode: 48, modifiers: .command)) == .reservedSystemInput, "Command-Tab reserved")
    verify(InputBindingPolicy.issue(for: .keyboard(keyCode: 12, modifiers: [.control, .command])) == .reservedSystemInput, "lock-screen reserved")
    verify(InputBindingPolicy.issue(for: .keyboard(keyCode: 53)) == .escapeReserved, "Escape reserved")
    verify(InputBindingPolicy.issue(for: .keyboard(keyCode: 57)) == .capsLockToggle, "CapsLock refused")
    verify(InputBindingPolicy.issue(for: .mouseButton(index: 0)) == .invalidMouseButton, "primary click never bound")
    verify(InputBindingPolicy.issue(for: .mouseButton(index: 3)) == nil, "side binding allowed")
    verify(InputBindingPolicy.issue(for: .fnGlobe) == nil, "standard Fn accepted")
    var bridge = IntentInputBridge()
    let binding = InputBinding.mouseButton(index: 3)
    verify(!bridge.handle(input: .mouse(4), edge: .down, modifiers: [], binding: binding, allowed: true).consumes, "other side passes")
    let down = bridge.handle(input: .mouse(3), edge: .down, modifiers: [], binding: binding, allowed: true, point: .init(x: 10, y: 12))
    verify(down.consumes && down.event?.edge == .began, "configured side owns down")
    verify(!bridge.handle(input: .key(0), edge: .down, modifiers: [], binding: binding, allowed: true).consumes, "normal typing passes")
    let up = bridge.handle(input: .mouse(3), edge: .up, modifiers: [], binding: binding, allowed: true, point: .init(x: 40, y: 50))
    verify(up.event?.point == .init(x: 40, y: 50), "release coordinate retained")
    verify(up.event?.token == down.event?.token && up.event?.edge == .released, "release belongs to same press")
    verify(bridge.handle(input: .mouse(3), edge: .up, modifiers: [], binding: binding, allowed: true).event == nil, "duplicate up not delivered")
}
func validateCancellationAndFn() {
    var bridge = IntentInputBridge()
    let binding = InputBinding.mouseButton(index: 4)
    let down = bridge.handle(input: .mouse(4), edge: .down, modifiers: [], binding: binding, allowed: true)
    verify(bridge.pointerMoved(.init(x: 1, y: 1), allowed: false).event?.edge == .cancelled, "secure-input loss cancels")
    verify(bridge.pointerMoved(.init(x: 2, y: 2), allowed: true).event == nil, "permission regain cannot resurrect")
    verify(bridge.handle(input: .mouse(4), edge: .up, modifiers: [], binding: binding, allowed: true).event == nil, "cancelled release never submits")
    bridge.invalidate(); verify(!bridge.accepts(down.event!), "queued old callback invalidated")
    let key = InputBinding.keyboard(keyCode: 50)
    let old = bridge.handle(input: .key(50), edge: .down, modifiers: [], binding: key, allowed: true).event!.token
    _ = bridge.handle(input: .key(50), edge: .up, modifiers: [], binding: key, allowed: true)
    let new = bridge.handle(input: .key(50), edge: .down, modifiers: [], binding: key, allowed: true).event!.token
    bridge.finish(old); verify(bridge.activePress == new, "late finish cannot cancel new press")
    bridge = IntentInputBridge()
    verify(bridge.handle(input: .key(122), edge: .down, modifiers: .function, binding: .fnGlobe, allowed: true).event == nil, "F1 event is not Fn hold")
    verify(bridge.flagsChanged(keyCode: 63, modifiers: .function, binding: .fnGlobe, allowed: true).event?.edge == .began, "actual Fn edge begins")
    let typing = bridge.handle(input: .key(0), edge: .down, modifiers: .function, binding: .fnGlobe, allowed: true)
    verify(typing.event?.edge == .cancelled && !typing.consumes, "Fn typing cancels and passes")
    verify(bridge.flagsChanged(keyCode: 63, modifiers: .function, binding: .fnGlobe, allowed: true).event == nil, "held Fn stays disarmed")
    _ = bridge.flagsChanged(keyCode: 63, modifiers: [], binding: .fnGlobe, allowed: true)
    verify(bridge.flagsChanged(keyCode: 63, modifiers: .function, binding: .fnGlobe, allowed: true).event?.edge == .began, "next physical Fn can begin")
}
func validatePointerGeometry() throws {
    var bridge = IntentInputBridge(), buffer = IntentPointerMoveBuffer(), geometry = IntentSideSelectionState()
    let binding = InputBinding.mouseButton(index: 4)
    let token = bridge.handle(input: .mouse(4), edge: .down, modifiers: [], binding: binding, allowed: true).event!.token
    verify(buffer.offer(bridge.movement(.init(x: 10, y: 10))!), "first move schedules")
    verify(!buffer.offer(bridge.movement(.init(x: 20, y: 20))!), "second move coalesces")
    verify(buffer.take(token)?.point == .init(x: 20, y: 20), "latest move wins")
    _ = buffer.offer(bridge.movement(.init(x: 30, y: 30))!); buffer.discard(token)
    verify(buffer.take(token) == nil, "release discards pending move")
    geometry.begin(token, at: .init(x: 20, y: 20), screen: .init(x: 0, y: 0, width: 100, height: 100))
    geometry.move(.init(x: 200, y: 200), token: token)
    verify(geometry.finish(token) == .region(.init(x: 20, y: 20, width: 80, height: 80)), "region clamped to initial display")
    verify(geometry.finish(token) == nil, "finish emits once")
    geometry.begin(token, at: .init(x: 20, y: 20), screen: .init(x: 0, y: 0, width: 100, height: 100))
    geometry.move(.init(x: 21, y: 21), token: token)
    verify(geometry.finish(token) == .object(.init(x: 20, y: 20)), "jitter remains point selection")
    let pixels = try RegionCaptureService.pixelDimensions(width: 500, height: 300, scale: 2)
    verify(pixels.width == 1000 && pixels.height == 600, "retina pixel dimensions")
    expectFailure("reject non-finite size") { _ = try RegionCaptureService.pixelDimensions(width: .infinity, height: 1, scale: 2) }
    expectFailure("reject excessive backing pixels") { _ = try RegionCaptureService.pixelDimensions(width: 5000, height: 4000, scale: 2) }
    verify(!IntentBounds(x: 0, y: 0, width: 7, height: 10).isCapturableRegion, "small region rejected")
    verify(!IntentBounds(x: .nan, y: 0, width: 30, height: 30).isUsable, "invalid coordinates rejected")
    verify(IntentTextSafety.isProtected(role: "AXSecureTextField", subrole: nil), "protected role")
    verify(IntentTextSafety.isProtected(role: "AXTextField", subrole: "AXSecureTextField"), "protected ancestor metadata")
    verify(IntentTextSafety.isProtected(role: nil, subrole: nil, inputType: "PASSWORD"), "protected input type")
    verify(IntentTextSafety.limited(String(repeating: "字", count: 25_000)).count == 20_000, "text bounded")
}
func validateVoiceState() {
    var state = VoiceSession()
    let old = state.begin(objectIDs: [UUID()]); verify(state.authorized(generation: old), "voice first generation")
    state.cancel(); verify(!state.update("late", generation: old, final: true), "cancelled transcript rejected")
    let new = state.begin(objectIDs: []); verify(state.authorized(generation: new), "voice new generation")
    verify(!state.bindObjects([UUID()], generation: old), "old object updates rejected")
    verify(state.update("Translate this", generation: new, final: false), "partial transcript admitted")
    state.stop(); verify(state.phase == .finishing, "release waits for final")
    verify(state.update("Translate this paragraph", generation: new, final: true), "final transcript admitted")
    verify(state.phase == .ready, "final resolves ready")
    let lease = VoiceAudioLease(); lease.stopInput()
    verify(!lease.isValid && !lease.permitsBuffers, "stop during startup invalidates lease")
    expectFailure("cancelled startup throws") { try lease.checkCancellation() }
    var lifecycle = VoiceInputLifecycle(), removals = 0
    expectFailure("partial install fails") { try lifecycle.install(sampleRate: 48_000, channelCount: 1, install: { false }, remove: { removals += 1 }) }
    lifecycle.stop { removals += 1 }; verify(removals == 1, "partial tap removed once")
}
func validatePhysicalDrain() {
    var pair = InputBindingPairState()
    let binding = InputBinding.keyboard(keyCode: 50)
    verify(pair.handle(input: .key(50), edge: .down, modifiers: [], binding: binding, allowed: true) == .begin, "drain fixture begins")
    verify(!pair.observePhysicalState(isPressed: false, at: 0), "missing physical snapshot never ends active hold")
    verify(pair.logicalActive, "active logical hold survives advisory mask")
    pair.cancelKeepingOwnership()
    verify(pair.owner == .key(50) && !pair.logicalActive, "cancel retains physical up ownership")
    verify(!pair.observePhysicalState(isPressed: false, at: 1), "first absent snapshot cannot drain")
    verify(!pair.observePhysicalState(isPressed: false, at: 1.29), "drain waits for sustained release")
    verify(pair.observePhysicalState(isPressed: false, at: 1.31), "sustained absent snapshot drains cancelled pair")
    verify(pair.owner == nil, "drained pair clears owner")
    _ = pair.handle(input: .key(50), edge: .down, modifiers: [], binding: binding, allowed: true)
    pair.cancelKeepingOwnership()
    verify(pair.handle(input: .key(50), edge: .up, modifiers: [], binding: binding, allowed: false) == .consume, "pause consumes only owned up")
    verify(pair.handle(input: .key(1), edge: .up, modifiers: [], binding: binding, allowed: false) == .pass, "unrelated up passes while paused")
}
func syntheticPNG(width: Int, height: Int, noise: Bool) throws -> Data {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    var random: UInt32 = 0x29A56B3
    for offset in stride(from: 0, to: bytes.count, by: 4) {
        for channel in 0..<3 {
            random ^= random << 13; random ^= random >> 17; random ^= random << 5
            bytes[offset + channel] = noise ? UInt8(truncatingIfNeeded: random) : UInt8(35 + channel * 50)
        }
        bytes[offset + 3] = 255
    }
    let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: .init(rawValue: CGImageAlphaInfo.last.rawValue),
        provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw ScreenshotNetworkImageError.invalidPNG }
    return output as Data
}
func validateNetworkImage() throws {
    let original = try syntheticPNG(width: 2300, height: 1500, noise: true), retained = original
    let prepared = try ScreenshotNetworkImage.prepare(png: original)
    verify(original == retained, "network preparation preserves original bytes")
    verify(prepared.count <= ScreenshotNetworkImage.maximumBytes, "network PNG at most 3 MiB")
    let source = CGImageSourceCreateWithData(prepared as CFData, nil)!
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
    let width = properties[kCGImagePropertyPixelWidth] as! Int, height = properties[kCGImagePropertyPixelHeight] as! Int
    verify(width <= 2048 && height <= 2048, "network image dimensions bounded")
    verify(width < 2048, "noisy image exercises byte-budget downscaling")
    verify(abs(Double(width) / Double(height) - 2300.0 / 1500.0) < 0.01, "aspect ratio preserved")
    let small = try syntheticPNG(width: 30, height: 20, noise: false)
    let smallOutput = try ScreenshotNetworkImage.prepare(png: small)
    let smallSource = CGImageSourceCreateWithData(smallOutput as CFData, nil)!
    let smallProperties = CGImageSourceCopyPropertiesAtIndex(smallSource, 0, nil)! as NSDictionary
    verify(smallProperties[kCGImagePropertyPixelWidth] as! Int == 30, "small input not enlarged")
    expectFailure("invalid image rejected") { _ = try ScreenshotNetworkImage.prepare(png: Data("invalid".utf8)) }
    expectFailure("empty image rejected") { _ = try ScreenshotNetworkImage.prepare(png: Data()) }
}

do {
    validateBindingsAndOwnership()
    validateCancellationAndFn()
    try validatePointerGeometry()
    validateVoiceState()
    validatePhysicalDrain()
    try validateNetworkImage()
    print("LabSelectionNativeValidation: \(checkCount) checks passed; synthetic data only; no native input, recording or screen capture started.")
} catch {
    fatalError("Validation threw unexpected error: \(error)")
}
