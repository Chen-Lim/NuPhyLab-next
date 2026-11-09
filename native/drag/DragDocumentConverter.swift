import AppKit
import PDFKit
import CoreGraphics

final class DragJobControl {
    private let lock = NSLock()
    private var stopped = false
    private var fraction: Double = 0
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    var progress: Double { lock.lock(); defer { lock.unlock() }; return fraction }
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    func update(_ value: Double) { lock.lock(); fraction = min(1, max(0, value)); lock.unlock() }
    func check() throws { if cancelled { throw DragJobError.cancelled } }
}
enum DragJobError: Error, LocalizedError {
    case cancelled, lockedPDF, noAudio, noVideo, timeout, emptyPDF
    var errorDescription: String? {
        switch self {
        case .cancelled: return "已取消；已完成的副本保留 / Cancelled; completed copies kept"
        case .lockedPDF: return "PDF 受密码或复制权限保护，请先解锁 / Unlock this PDF first"
        case .noAudio: return "文件没有可用音轨 / No audio track"
        case .noVideo: return "文件没有可用视频轨 / No video track"
        case .timeout: return "转换超时，原文件已保留 / Conversion timed out"
        case .emptyPDF: return "PDF 没有可用页面 / PDF has no pages"
        }
    }
}

enum DragDocumentConverter {
    static func document(_ url: URL) throws -> PDFDocument {
        try DragOutput.validate(url, maxBytes: 512 * 1024 * 1024)
        guard let pdf = PDFDocument(url: url) else { throw DragConvertError.unreadable }
        guard !pdf.isLocked, pdf.allowsCopying else { throw DragJobError.lockedPDF }
        guard pdf.pageCount > 0 else { throw DragJobError.emptyPDF }
        guard pdf.pageCount <= 200 else { throw DragConvertError.tooLarge }
        return pdf
    }
    static func convert(_ inputs: [URL], to format: DragFormat, preferences: DragConvertPreferences, control: DragJobControl) throws -> URL {
        guard !inputs.isEmpty else { throw DragConvertError.unsupported }
        let access = inputs.map { ($0, $0.startAccessingSecurityScopedResource()) }
        defer { access.forEach { if $0.1 { $0.0.stopAccessingSecurityScopedResource() } } }
        // Natural filename order is deterministic even when a source's drag order isn't.
        let ordered = inputs.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        if format == .imagesPDF {
            return try DragOutput.write(input: ordered[0], preferences: preferences, suffix: "-images", ext: "pdf") { output in
                guard let consumer = CGDataConsumer(url: output as CFURL), let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw DragConvertError.encoding }
                for (index, input) in ordered.enumerated() {
                    try control.check()
                    try autoreleasepool {
                        let image = try DragImageConverter.decode(input)
                        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
                        context.beginPDFPage([kCGPDFContextMediaBox: NSData(bytes: [rect], length: MemoryLayout<CGRect>.size)] as CFDictionary)
                        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(rect); context.draw(image, in: rect)
                        context.endPDFPage()
                    }
                    control.update(Double(index + 1) / Double(ordered.count))
                }
                context.closePDF(); try control.check()
            }
        }
        if format == .mergePDF {
            let outputPDF = PDFDocument()
            for (index, input) in ordered.enumerated() {
                try control.check()
                let pdf = try document(input)
                guard outputPDF.pageCount + pdf.pageCount <= 200 else { throw DragConvertError.tooLarge }
                for pageIndex in 0..<pdf.pageCount {
                    guard let page = pdf.page(at: pageIndex) else { throw DragConvertError.unreadable }
                    outputPDF.insert(page, at: outputPDF.pageCount)
                }
                control.update(Double(index + 1) / Double(ordered.count))
            }
            return try DragOutput.write(input: ordered[0], preferences: preferences, suffix: "-merged", ext: "pdf") { url in
                try control.check(); guard outputPDF.write(to: url) else { throw DragConvertError.encoding }
                try control.check()
            }
        }
        let input = inputs[0], pdf = try document(input)
        guard [.splitPDF, .pdfPNG, .pdfJPG].contains(format) else { throw DragConvertError.unsupported }
        return try DragOutput.write(input: input, preferences: preferences, suffix: "-\(format == .splitPDF ? "pages" : format.fileExtension)", ext: "", directoryOutput: true) { directory in
            for index in 0..<pdf.pageCount {
                try control.check()
                try autoreleasepool {
                    guard let page = pdf.page(at: index) else { throw DragConvertError.unreadable }
                    let output = directory.appendingPathComponent(String(format: "page-%03d.%@", index + 1, format.fileExtension))
                    if format == .splitPDF {
                        let single = PDFDocument(); single.insert(page, at: 0)
                        guard single.write(to: output) else { throw DragConvertError.encoding }
                    } else {
                        let image = try render(page, maxDimension: preferences.maxDimension)
                        try DragImageConverter.encode(image, to: output, format: format, quality: preferences.quality)
                    }
                }
                control.update(Double(index + 1) / Double(pdf.pageCount))
            }
            try control.check()
        }
    }
    static func render(_ page: PDFPage, maxDimension: Int) throws -> CGImage {
        let bounds = page.bounds(for: .cropBox)
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { throw DragConvertError.unreadable }
        let rotated = abs(page.rotation) % 180 == 90
        let width = rotated ? bounds.height : bounds.width, height = rotated ? bounds.width : bounds.height
        let scale = min(2, Double(maxDimension) / max(width, height))
        let w = max(1, Int(ceil(width * scale))), h = max(1, Int(ceil(height * scale)))
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw DragConvertError.encoding }
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: context)
        guard let image = context.makeImage() else { throw DragConvertError.encoding }; return image
    }
}
