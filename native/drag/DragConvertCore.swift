import Foundation
import CoreGraphics

enum DragFormat: String, Codable, CaseIterable {
    case jpg, png, webp, heic, tiff, small, imagesPDF
    case pdfPNG, pdfJPG, splitPDF, mergePDF
    case mp4, mov, video720, video1080, m4a, wav, aiff
    case zip, zipEach, zipFast, tarGz, extract
    var fileExtension: String {
        switch self {
        case .small, .pdfJPG: return "jpg"
        case .pdfPNG: return "png"
        case .imagesPDF, .splitPDF, .mergePDF: return "pdf"
        case .video720, .video1080: return "mp4"
        case .zipEach, .zipFast: return "zip"
        case .tarGz: return "tar.gz"
        default: return rawValue
        }
    }
    var combinesInputs: Bool { [.imagesPDF, .mergePDF, .zip, .zipFast, .tarGz].contains(self) }
    func title(english: Bool) -> String {
        switch self {
        case .webp: return "WebP"
        case .zip: return english ? "Pack ZIP" : "打包 ZIP"
        case .zipEach: return english ? "Each ZIP" : "分别 ZIP"
        case .zipFast: return english ? "Store ZIP" : "快速 ZIP"
        case .tarGz: return "TAR.GZ"
        case .extract: return english ? "Extract" : "解压"
        case .small: return english ? "Small JPG" : "小图 JPG"
        case .imagesPDF: return english ? "To PDF" : "合成 PDF"
        case .pdfPNG: return "PNG"
        case .pdfJPG: return "JPG"
        case .splitPDF: return english ? "Split" : "拆分页面"
        case .mergePDF: return english ? "Merge" : "合并 PDF"
        case .video720: return "720p"
        case .video1080: return "1080p"
        default: return rawValue.uppercased()
        }
    }
}

/// Extension-only routing on the input thread. Content validation and decoding
/// happen on the conversion queue, never while presenting the drag menu.
enum DragFileKind {
    case image, pdf, video, audio, archive, other
    static func kind(_ url: URL) -> Self? {
        guard url.isFileURL else { return nil }
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "heif", "webp", "tif", "tiff", "bmp": return .image
        case "pdf": return .pdf
        case "mp4", "mov", "m4v": return .video
        case "mp3", "m4a", "wav", "aif", "aiff", "caf", "aac", "flac": return .audio
        case "zip", "7z", "rar", "tar", "tgz", "tbz", "tbz2", "txz", "gz", "bz2", "xz": return .archive
        default: return .other
        }
    }
    static func actions(for urls: [URL]) -> [DragFormat] {
        guard !urls.isEmpty, urls.count <= 128, let first = kind(urls[0]) else { return [] }
        let kinds = urls.compactMap(kind)
        guard kinds.count == urls.count else { return [] }
        let packing: [DragFormat] = [.zip, urls.count > 1 ? .zipEach : .zipFast]
        if !kinds.allSatisfy({ $0 == first }) {
            return kinds.allSatisfy { $0 == .audio || $0 == .video } ? [.m4a, .wav, .aiff] + packing : packing + [.tarGz]
        }
        switch first {
        case .image: return [.jpg, .png, .webp, .heic, .tiff, .small, .imagesPDF] + packing
        case .pdf: return (urls.count > 1 ? [.mergePDF, .pdfPNG, .pdfJPG, .splitPDF] : [.pdfPNG, .pdfJPG, .splitPDF]) + packing
        case .video: return [.mp4, .mov, .video720, .video1080, .m4a] + packing
        case .audio: return [.m4a, .wav, .aiff] + packing
        case .archive: return [.extract, .zip, .tarGz]
        case .other: return packing + [.tarGz]
        }
    }
}

struct DragConvertPreferences: Codable, Equatable {
    var enabled = false
    var trigger = "shift"
    var quality = 0.88
    var maxDimension = 1600
    var outputDirectory: String? = nil
    func validated() throws -> Self {
        guard DragTrigger(trigger) != nil, quality.isFinite, (0.5...1).contains(quality),
              [800, 1200, 1600, 2400].contains(maxDimension),
              outputDirectory == nil || (outputDirectory!.hasPrefix("/") && !outputDirectory!.contains("\0")) else {
            throw DragConvertError.invalidSettings
        }
        return self
    }
}

enum DragConvertError: Error, LocalizedError {
    case invalidSettings, unsupported, tooLarge, unreadable, encoding, output
    var errorDescription: String? {
        switch self {
        case .invalidSettings: return "设置无效 / Invalid settings"
        case .unsupported: return "该文件的内容或编码不支持此操作 / Unsupported content or codec"
        case .tooLarge: return "文件超过处理限制 / File exceeds processing limits"
        case .unreadable: return "无法读取文件，请先下载到本机并检查权限 / Cannot read file"
        case .encoding: return "转换失败，原文件已保留 / Conversion failed; original kept"
        case .output: return "无法保存副本，请检查输出文件夹权限 / Cannot save copy"
        }
    }
}

/// Pure gesture state. Selection alone never activates the menu; a real file
/// drag accepts both Shift-before-drag and Shift-during-drag ordering.
/// Polling only presents/dismisses UI; it cannot commit any file operation.
struct DragGestureState {
    enum Phase: Equatable { case idle, armed, dragging, visible, ignored }
    enum Effect { case none, show, end }
    private(set) var phase: Phase = .idle
    private var baseline = 0
    private var held = false
    private var changed = false
    private var heldAtStart = false
    private var pendingUntil: TimeInterval?
    mutating func begin(change: Int, trigger: Bool) {
        baseline = change; held = trigger; heldAtStart = trigger; changed = false; pendingUntil = nil; phase = .armed
    }
    mutating func cancel() { phase = .ignored; pendingUntil = nil }
    mutating func reset() { phase = .idle; pendingUntil = nil }
    mutating func retryPresentation() { if phase == .visible { phase = .dragging } }
    mutating func sample(button: Bool, change: Int, hasFiles: Bool, trigger: Bool, now: TimeInterval = 0, moved: Bool = true) -> Effect {
        guard phase != .idle else { return .none }
        guard button else { let wasVisible = phase == .visible; reset(); return wasVisible ? .end : .none }
        let pressed = trigger && !held; held = trigger
        guard phase == .armed || phase == .dragging else { return .none }
        // Finder can publish the drag board in several steps. Remember a fresh
        // tap briefly instead of losing it on the armed -> dragging transition.
        if pressed { pendingUntil = now + 0.35 }
        if change != baseline { changed = true }
        if !trigger { heldAtStart = false }
        if let until = pendingUntil, now > until, !trigger { pendingUntil = nil }
        guard changed, hasFiles, moved else { return .none }
        phase = .dragging
        if heldAtStart && trigger { pendingUntil = now + 0.35; heldAtStart = false }
        if pendingUntil != nil { phase = .visible; return .show }
        return .none
    }
}

/// Same geometry is used to draw, hover, prepare and commit a drop.
/// A neutral centre and angular gutters make ambiguous releases a no-op.
struct DragWheelGeometry {
    static let maximumSectors = 9
    static let side: CGFloat = 252
    static let inner: CGFloat = 34
    static let outer: CGFloat = 112
    static let gap: CGFloat = 0.045
    static let center = CGPoint(x: side / 2, y: side / 2)
    static func angle(_ point: CGPoint) -> CGFloat {
        var a = atan2(point.x - center.x, point.y - center.y)
        if a < 0 { a += 2 * .pi }; return a
    }
    private static let sectorPaths = (3...maximumSectors).map { count in (0..<count).map { makePath($0, count: count) } }
    static func path(_ index: Int, count: Int = 3) -> CGPath { sectorPaths[count - 3][index] }
    private static func makePath(_ index: Int, count: Int) -> CGPath {
        let mid = CGFloat(index) * 2 * .pi / CGFloat(count)
        let start = mid - .pi / CGFloat(count) + gap, end = mid + .pi / CGFloat(count) - gap
        // AppKit coordinates, clockwise starting at twelve o'clock.
        let p = CGMutablePath()
        p.addArc(center: center, radius: inner, startAngle: .pi / 2 - start, endAngle: .pi / 2 - end, clockwise: true)
        p.addArc(center: center, radius: outer, startAngle: .pi / 2 - end, endAngle: .pi / 2 - start, clockwise: false)
        p.closeSubpath(); return p
    }
    static func hit(_ point: CGPoint, count: Int = 3) -> Int? {
        guard (3...maximumSectors).contains(count) else { return nil }
        return (0..<count).first { path($0, count: count).contains(point) }
    }
    static func frame(at point: CGPoint, visible: CGRect) -> CGRect {
        let size = CGSize(width: side, height: side)
        let x = min(max(point.x - side / 2, visible.minX + 8), visible.maxX - side - 8)
        let y = min(max(point.y - side / 2, visible.minY + 8), visible.maxY - side - 8)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
    static func labelPoint(_ index: Int, count: Int = 3) -> CGPoint {
        let a = CGFloat(index) * 2 * .pi / CGFloat(count)
        return CGPoint(x: center.x + sin(a) * 77, y: center.y + cos(a) * 77)
    }
}

struct DragConversionResult {
    let input: URL
    let output: URL?
    let error: String?
}
