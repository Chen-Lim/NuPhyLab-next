// Adapted from apps/macos/Sources/Chord/ScreenshotAIImagePreparation.swift.
// Standalone single-selection extraction; see source-provenance.json for changes and hashes.
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ScreenshotNetworkImageError: Error, Equatable { case invalidPNG, imageTooLarge }

/// Adapted from Chord/ScreenshotAIImagePreparation.swift. Creates a bounded
/// network copy of one screenshot; the caller's original Data stays unchanged.
/// No editor, storage, screenshot capture or model API is involved.
public enum ScreenshotNetworkImage {
    public static let maximumBytes = 3 * 1024 * 1024
    public static let maximumDimension = 2048

    /// CPU/image decoding work: invoke off the main actor. Cancellation is
    /// checked between ImageIO operations; a native decode cannot be interrupted.
    public static func prepare(png: Data) throws -> Data {
        try Task.checkCancellation()
        return try autoreleasepool {
            guard let source = CGImageSourceCreateWithData(png as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  CGImageSourceGetType(source) == UTType.png.identifier as CFString,
                  CGImageSourceGetCount(source) == 1,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0,
                  width <= 8192, height <= 8192, width <= 32_000_000 / height else {
                throw ScreenshotNetworkImageError.invalidPNG
            }
            for dimension in [2048, 1600, 1200, 800] {
                try Task.checkCancellation()
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: dimension,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true
                ]
                guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                    throw ScreenshotNetworkImageError.invalidPNG
                }
                let output = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
                    throw ScreenshotNetworkImageError.invalidPNG
                }
                CGImageDestinationAddImage(destination, image, nil)
                guard CGImageDestinationFinalize(destination) else { throw ScreenshotNetworkImageError.invalidPNG }
                try Task.checkCancellation()
                if output.length <= maximumBytes { return output as Data }
            }
            throw ScreenshotNetworkImageError.imageTooLarge
        }
    }
}
