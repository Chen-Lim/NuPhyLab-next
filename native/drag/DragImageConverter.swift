import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

enum DragImageConverter {
    static func supports(_ urls: [URL]) -> Bool {
        !urls.isEmpty && urls.count <= 128 && urls.allSatisfy { DragFileKind.kind($0) == .image }
    }
    static func decode(_ input: URL, maxDimension: Int? = nil, sourceEdgeLimit: Int? = nil) throws -> CGImage {
        guard supports([input]) else { throw DragConvertError.unsupported }
        try DragOutput.validate(input, maxBytes: 512 * 1024 * 1024)
        guard let source = CGImageSourceCreateWithURL(input as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?,
              [UTType.jpeg.identifier, UTType.png.identifier, UTType.heic.identifier, UTType.heif.identifier, UTType.webP.identifier, UTType.tiff.identifier, UTType.bmp.identifier].contains(type),
              CGImageSourceGetCount(source) > 0 else { throw DragConvertError.unreadable }
        // HEIF auxiliary images are allowed; never silently discard animation or TIFF pages.
        if ![UTType.heic.identifier, UTType.heif.identifier].contains(type), CGImageSourceGetCount(source) > 1 { throw DragConvertError.unsupported }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0,
              width <= 100_000_000 / height else { throw DragConvertError.tooLarge }
        if let sourceEdgeLimit, max(width, height) > sourceEdgeLimit { throw DragConvertError.tooLarge }
        let dimension = min(maxDimension ?? max(width, height), max(width, height))
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: dimension, kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { throw DragConvertError.unreadable }
        return image
    }
    static func encode(_ decoded: CGImage, to destinationURL: URL, format: DragFormat, quality: Double, check: @escaping () throws -> Void = {}) throws {
        if format == .webp { try DragWebPEncoder.encode(decoded, to: destinationURL, quality: quality, check: check); return }
        let uti: String
        switch format {
        case .jpg, .small, .pdfJPG: uti = UTType.jpeg.identifier
        case .png, .pdfPNG: uti = UTType.png.identifier
        case .heic: uti = UTType.heic.identifier
        case .tiff: uti = UTType.tiff.identifier
        default: throw DragConvertError.unsupported
        }
        guard (CGImageDestinationCopyTypeIdentifiers() as! [String]).contains(uti),
              let space = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(data: nil,
              width: decoded.width, height: decoded.height, bitsPerComponent: 8, bytesPerRow: 0,
              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw DragConvertError.encoding }
        let rect = CGRect(x: 0, y: 0, width: decoded.width, height: decoded.height)
        if uti == UTType.jpeg.identifier || uti == UTType.heic.identifier { context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(rect) }
        context.draw(decoded, in: rect)
        guard let image = context.makeImage(), let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, uti as CFString, 1, nil) else { throw DragConvertError.encoding }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw DragConvertError.encoding }
    }
    static func convert(_ input: URL, to format: DragFormat, preferences: DragConvertPreferences, check: @escaping () throws -> Void = {}) throws -> URL {
        let preferences = try preferences.validated()
        let access = input.startAccessingSecurityScopedResource()
        defer { if access { input.stopAccessingSecurityScopedResource() } }
        let decoded = try decode(input, maxDimension: format == .small ? preferences.maxDimension : nil, sourceEdgeLimit: format == .webp ? 16_383 : nil)
        try check()
        return try DragOutput.write(input: input, preferences: preferences, suffix: format == .small ? "-small" : "", ext: format.fileExtension) { output in
            try encode(decoded, to: output, format: format, quality: preferences.quality, check: check)
            try check()
        }
    }
}
