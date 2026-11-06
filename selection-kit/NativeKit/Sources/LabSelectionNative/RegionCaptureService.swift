// Adapted from apps/macos/Sources/Chord/Input/RegionCaptureService.swift.
// Standalone single-selection extraction; see source-provenance.json for changes and hashes.
import AppKit
import Carbon
import ScreenCaptureKit
import Vision

public struct RegionCaptureResult: Sendable {
    public let imagePNG: Data
    public let text: String
    public var screenshotDuration: TimeInterval = 0
    public var ocrDuration: TimeInterval = 0
}

public enum RegionCaptureService {
    /// Screen coordinates are points. Keep the display's backing pixels all
    /// the way through local editing/export; network thumbnails are separate.
    public static func pixelDimensions(width: Double, height: Double, scale: Double) throws -> (width: Int, height: Int) {
        guard width.isFinite, height.isFinite, scale.isFinite,
              width > 0, height > 0, scale >= 1, scale <= 4,
              width * scale <= 8192, height * scale <= 8192 else {
            throw IntentServiceError.regionTooLarge
        }
        let pixelsWide = max(1, Int((width * scale).rounded(.up)))
        let pixelsHigh = max(1, Int((height * scale).rounded(.up)))
        guard pixelsWide <= 32_000_000 / pixelsHigh else { throw IntentServiceError.regionTooLarge }
        return (pixelsWide, pixelsHigh)
    }

    /// Single-frame, explicit-region capture on macOS 14. No stream is started.
    public static func capture(_ bounds: IntentBounds, excludingWindowIDs: Set<CGWindowID> = [], preferredLanguages: [String] = Locale.preferredLanguages) async throws -> RegionCaptureResult {
        try assertCaptureAllowed()
        guard bounds.isCapturableRegion else { throw IntentServiceError.invalidRegion }
        // Preserve the original controller's protected-focus/center check even
        // when a host calls this no-UI service directly.
        _ = try await ScreenAwarenessService().regionContext(at: CGPoint(x: bounds.x + bounds.width / 2, y: bounds.y + bounds.height / 2))
        try assertCaptureAllowed()
        let screenshotStarted = ProcessInfo.processInfo.systemUptime
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try assertCaptureAllowed()
        guard let display = content.displays.first(where: { bounds.contained(in: IntentBounds($0.frame)) }) else { throw IntentServiceError.invalidRegion }
        let excluded = content.windows.filter { excludingWindowIDs.contains($0.windowID) || $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: bounds.x - display.frame.minX, y: bounds.y - display.frame.minY, width: bounds.width, height: bounds.height)
        let scale = max(1, Double(filter.pointPixelScale))
        let pixels = try pixelDimensions(width: bounds.width, height: bounds.height, scale: scale)
        config.width = pixels.width
        config.height = pixels.height
        config.captureResolution = .best
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        try assertCaptureAllowed()
        guard image.width == pixels.width, image.height == pixels.height else { throw IntentServiceError.captureFailed }
        let screenshotDuration = ProcessInfo.processInfo.systemUptime - screenshotStarted
        let job = RegionOCRJob(image: image, preferredLanguages: preferredLanguages)
        return try await withTaskCancellationHandler {
            let task = Task.detached(priority: .userInitiated) { try job.run() }
            var result = try await task.value
            try assertCaptureAllowed()
            result.screenshotDuration = screenshotDuration
            return result
        } onCancel: { job.cancel() }
    }

    private static func assertCaptureAllowed() throws {
        try Task.checkCancellation()
        guard !IsSecureEventInputEnabled() else { throw IntentServiceError.secureInput }
        guard CGPreflightScreenCaptureAccess() else { throw IntentServiceError.screenPermission }
    }
}

final class RegionOCRJob: @unchecked Sendable {
    private let image: CGImage
    private let request = VNRecognizeTextRequest()
    private let lock = NSLock()
    private var cancelled = false
    private let preferredLanguages: [String]
    private let recognize: (VNRecognizeTextRequest, CGImage) throws -> String
    init(image: CGImage, preferredLanguages: [String] = Locale.preferredLanguages, recognize: @escaping (VNRecognizeTextRequest, CGImage) throws -> String = RegionOCRJob.recognizeText) {
        self.image = image; self.preferredLanguages = preferredLanguages; self.recognize = recognize
    }
    func cancel() { lock.lock(); cancelled = true; lock.unlock(); request.cancel() }
    private func checkCancellation() throws {
        lock.lock(); let isCancelled = cancelled; lock.unlock()
        if isCancelled { throw CancellationError() }
        guard !IsSecureEventInputEnabled() else { throw IntentServiceError.secureInput }
    }
    func run() throws -> RegionCaptureResult {
        try checkCancellation()
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw IntentServiceError.captureFailed }
        let ocrStarted = ProcessInfo.processInfo.systemUptime
        let text: String
        do {
            let supported = try request.supportedRecognitionLanguages()
            let preferred = preferredLanguages.filter { supported.contains($0) }
            if !preferred.isEmpty { request.recognitionLanguages = preferred }
            text = try recognize(request, image)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // A photograph or a temporary Vision failure is still a valid
            // screenshot. The host must not lose its pixels because OCR
            // was unavailable. Safety/cancellation always wins over fallback.
            try checkCancellation()
            text = ""
        }
        try checkCancellation()
        return RegionCaptureResult(imagePNG: png, text: IntentTextSafety.limited(text),
                                   ocrDuration: ProcessInfo.processInfo.systemUptime - ocrStarted)
    }

    private static func recognizeText(_ request: VNRecognizeTextRequest, image: CGImage) throws -> String {
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}

extension IntentBounds {
    init(_ rect: CGRect) { self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height) }
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
