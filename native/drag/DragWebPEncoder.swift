import Foundation
import CoreGraphics

/// Statically linked libwebp; sRGB pixels, original dimensions and alpha.
enum DragWebPEncoder {
    private final class Cancellation {
        let check: () throws -> Void
        var error: Error?
        init(_ check: @escaping () throws -> Void) { self.check = check }
    }
    static func encode(_ image: CGImage, to output: URL, quality: Double, check: @escaping () throws -> Void) throws {
        guard quality.isFinite, (0.5...1).contains(quality) else { throw DragConvertError.invalidSettings }
        let width = image.width, height = image.height
        guard width > 0, height > 0, width <= 16_383, height <= 16_383,
              width <= 100_000_000 / height else { throw DragConvertError.tooLarge }
        try check()
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data:nil, width:width, height:height, bitsPerComponent:8,
                bytesPerRow:width * 4, space:space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { throw DragConvertError.encoding }
        defer { withExtendedLifetime(context) {} }
        context.draw(image, in:CGRect(x:0,y:0,width:width,height:height))
        let rgba = data.assumingMemoryBound(to:UInt8.self)
        // CoreGraphics stores premultiplied RGBA, libwebp imports straight RGBA.
        // Unpremultiply to avoid dark fringes around translucent edges.
        for row in 0..<height {
            if row % 64 == 0 { try check() }
            for column in 0..<width {
                let index = (row * width + column) * 4, alpha = Int(rgba[index+3])
                if alpha > 0 && alpha < 255 {
                    for channel in 0..<3 { rgba[index+channel] = UInt8(min(255,(Int(rgba[index+channel])*255+alpha/2)/alpha)) }
                }
            }
        }
        var config = WebPConfig(), picture = WebPPicture(), memory = WebPMemoryWriter()
        guard WebPConfigInit(&config) != 0, WebPPictureInit(&picture) != 0 else { throw DragConvertError.encoding }
        config.lossless = quality == 1 ? 1 : 0
        config.quality = quality == 1 ? 75 : Float(quality * 100)
        config.method = 4; config.alpha_quality = 100; config.exact = 1
        guard WebPValidateConfig(&config) != 0 else { throw DragConvertError.encoding }
        picture.width = Int32(width); picture.height = Int32(height); picture.use_argb = 1
        WebPMemoryWriterInit(&memory)
        defer { WebPPictureFree(&picture); WebPMemoryWriterClear(&memory) }
        guard WebPPictureImportRGBA(&picture,rgba,Int32(width*4)) != 0 else { throw DragConvertError.encoding }
        let cancellation = Cancellation(check)
        picture.user_data = Unmanaged.passUnretained(cancellation).toOpaque()
        picture.progress_hook = { _, pointer in
            guard let opaque = pointer?.pointee.user_data else { return 0 }
            let state = Unmanaged<Cancellation>.fromOpaque(opaque).takeUnretainedValue()
            do { try state.check(); return 1 } catch { state.error = error; return 0 }
        }
        let encoded = withExtendedLifetime(cancellation) {
            withUnsafeMutablePointer(to:&memory) { writer -> Int32 in
                picture.custom_ptr = UnsafeMutableRawPointer(writer)
                picture.writer = WebPMemoryWrite
                return WebPEncode(&config,&picture)
            }
        }
        if let error = cancellation.error { throw error }
        guard encoded != 0, let bytes = memory.mem, memory.size > 0 else { throw DragConvertError.encoding }
        try check()
        try Data(bytes:bytes,count:memory.size).write(to:output)
    }
}
