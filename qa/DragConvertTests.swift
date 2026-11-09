import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

@main struct DragConvertTests {
    static var checks = 0
    static func check(_ value: Bool, _ name: String) {
        guard value else { fatalError("FAIL: \(name)") }; checks += 1
    }
    static func expectError(_ name: String, _ action: () throws -> Void) {
        do { try action(); fatalError("Expected failure: \(name)") } catch { checks += 1 }
    }
    static func image(_ file: URL, uti: String = UTType.png.identifier, width: Int = 1600, height: Int = 900, orientation: Int = 1) throws {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.3, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width/2, height: height))
        let destination = CGImageDestinationCreateWithURL(file as CFURL, uti as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw DragConvertError.encoding }
    }
    static func size(_ file: URL) -> CGSize {
        let source = CGImageSourceCreateWithURL(file as CFURL, nil)!
        let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
        return CGSize(width: p[kCGImagePropertyPixelWidth] as! Int, height: p[kCGImagePropertyPixelHeight] as! Int)
    }
    static func run() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var state = DragGestureState()
        state.begin(change: 1, trigger: true)
        check(state.sample(button:true,change:1,hasFiles:true,trigger:true) == .none,"Shift selection with stale drag board cannot open")
        check(state.sample(button:true,change:2,hasFiles:true,trigger:true,moved:false) == .none,"Shift click without movement cannot open")
        check(state.sample(button:true,change:2,hasFiles:true,trigger:true,moved:true) == .show,"Shift held before a real file drag opens first time")
        state.begin(change:1,trigger:true)
        check(state.sample(button:true,change:1,hasFiles:true,trigger:false) == .none,"released selection key cannot activate stale files")
        _ = state.sample(button:true,change:2,hasFiles:true,trigger:false)
        check(state.sample(button:true,change:2,hasFiles:true,trigger:true) == .show,"fresh tap opens")
        check(state.sample(button:true,change:2,hasFiles:true,trigger:false) == .none && state.phase == .visible,"key release leaves menu open")
        check(state.sample(button:false,change:2,hasFiles:true,trigger:false) == .end,"mouseup only ends UI")
        state.begin(change:4,trigger:false)
        check(state.sample(button:true,change:5,hasFiles:true,trigger:true,now:1) == .show,"first poll handles both new drag and Shift")
        state.begin(change:5,trigger:false)
        check(state.sample(button:true,change:6,hasFiles:false,trigger:true,now:1) == .none,"wait for staged pasteboard types")
        check(state.sample(button:true,change:6,hasFiles:true,trigger:false,now:1.1) == .show,"short first tap survives delayed file types")
        state.retryPresentation()
        check(state.sample(button:true,change:6,hasFiles:true,trigger:false,now:1.15) == .show,"retry URL values not yet published")
        state.begin(change:7,trigger:false)
        check(state.sample(button:true,change:7,hasFiles:false,trigger:true,now:1,moved:false) == .none,"Shift pressed while preparing a drag waits")
        check(state.sample(button:true,change:8,hasFiles:true,trigger:true,now:2,moved:true) == .show,"held Shift waits for actual drag beyond tap-buffer duration")
        state.begin(change:9,trigger:false)
        check(state.sample(button:true,change:9,hasFiles:true,trigger:true,now:2) == .none,"stale board never opens")
        check(state.sample(button:true,change:9,hasFiles:true,trigger:false,now:2.1) == .none,"ordinary click does not open")
        check(state.sample(button:true,change:10,hasFiles:true,trigger:false,now:2.5) == .none,"expired tap cannot activate later drag")
        state.begin(change:11,trigger:false)
        _ = state.sample(button:true,change:12,hasFiles:false,trigger:true,now:1)
        check(state.sample(button:true,change:12,hasFiles:false,trigger:false,now:1.2) == .none,"text drags never open")
        state.cancel()
        check(state.sample(button:true,change:13,hasFiles:true,trigger:true) == .none,"Esc locks this drag")
        check(DragWheelGeometry.hit(DragWheelGeometry.center) == nil, "centre cancels")
        check(DragWheelGeometry.hit(CGPoint(x: 0, y: 0)) == nil, "corners cancel")
        for index in 0..<3 {
            check(DragWheelGeometry.hit(DragWheelGeometry.labelPoint(index)) == index, "label and drop agree \(index)")
            let a = CGFloat(index) * 2 * .pi / 3 + .pi / 3
            check(DragWheelGeometry.hit(CGPoint(x:126+sin(a)*80,y:126+cos(a)*80)) == nil, "sector boundary cancels")
        }
        for screen in [CGRect(x:0,y:0,width:1440,height:900),CGRect(x:-1920,y:-200,width:1920,height:1080)] {
            for point in [screen.origin,CGPoint(x:screen.maxX,y:screen.maxY),CGPoint(x:screen.midX,y:screen.midY)] {
                check(screen.contains(DragWheelGeometry.frame(at: point, visible: screen)), "menu stays within each screen")
            }
        }
        var preferences = DragConvertPreferences(); preferences.maxDimension = 800
        let source = root.appendingPathComponent("transparent.png")
        try image(source)
        let original = try Data(contentsOf: source)
        let jpg = try DragImageConverter.convert(source, to: .jpg, preferences: preferences)
        check(size(jpg) == CGSize(width:1600,height:900), "JPG keeps dimensions")
        let small = try DragImageConverter.convert(source, to: .small, preferences: preferences)
        check(size(small) == CGSize(width:800,height:450), "small preserves aspect")
        let png = try DragImageConverter.convert(source, to: .png, preferences: preferences)
        check(png != source && png.lastPathComponent == "transparent-1.png", "same type is a separate copy")
        check(try Data(contentsOf: source) == original, "source bytes preserved")
        let decoded = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(jpg as CFURL,nil)!,0,nil)!
        let pixel = UnsafeMutablePointer<UInt8>.allocate(capacity:4);defer{pixel.deallocate()}
        let context = CGContext(data:pixel,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x:-CGFloat(decoded.width-1),y:0);context.draw(decoded,in:CGRect(x:0,y:0,width:decoded.width,height:decoded.height))
        check(pixel[0]>245 && pixel[1]>245 && pixel[2]>245,"JPG transparency is white")
        let alpha = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(png as CFURL,nil)!,0,nil)!
        check(alpha.alphaInfo != .none && alpha.alphaInfo != .noneSkipLast && alpha.alphaInfo != .noneSkipFirst,"PNG retains alpha")
        let rotated = root.appendingPathComponent("portrait.jpg")
        try image(rotated,uti:UTType.jpeg.identifier,width:120,height:80,orientation:6)
        let oriented = try DragImageConverter.convert(rotated,to:.png,preferences:preferences)
        check(size(oriented)==CGSize(width:80,height:120),"EXIF rotation materialized")
        let heic = root.appendingPathComponent("sample.heic")
        try image(heic,uti:UTType.heic.identifier,width:64,height:48)
        let heicResult = try DragImageConverter.convert(heic,to:.jpg,preferences:preferences)
        check(size(heicResult)==CGSize(width:64,height:48),"HEIC decode")
        let webp = root.appendingPathComponent("web-image.webp")
        try Data(base64Encoded:"UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEADsD+JaQAA3AAAAAA")!.write(to:webp)
        let webpResult = try DragImageConverter.convert(webp,to:.png,preferences:preferences)
        check(size(webpResult)==CGSize(width:1,height:1),"WebP decode")
        check(DragImageConverter.supports([source,webp,heic,rotated]),"mixed supported images batch")
        check(!DragImageConverter.supports([source,root.appendingPathComponent("movie.mov")]),"mixed unsupported batch rejected")
        check(!DragImageConverter.supports(Array(repeating:source,count:129)),"batch bounded")
        let fake = root.appendingPathComponent("broken.png");try Data("bad data".utf8).write(to:fake)
        expectError("corrupt image refused"){_ = try DragImageConverter.convert(fake,to:.jpg,preferences:preferences)}
        let folder = root.appendingPathComponent("folder.png",isDirectory:true);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        expectError("directory refused"){_ = try DragImageConverter.convert(folder,to:.jpg,preferences:preferences)}
        var invalid=preferences;invalid.maxDimension=999
        expectError("invalid settings refused"){_ = try invalid.validated()}
        invalid=preferences;invalid.quality = .infinity
        expectError("nonfinite quality refused"){_ = try invalid.validated()}
        let custom=root.appendingPathComponent("outputs",isDirectory:true);try FileManager.default.createDirectory(at:custom,withIntermediateDirectories:true)
        preferences.outputDirectory=custom.path
        let collision=custom.appendingPathComponent("transparent.jpg")
        try FileManager.default.createSymbolicLink(at:collision,withDestinationURL:source)
        let safe=try DragImageConverter.convert(source,to:.jpg,preferences:preferences)
        check(safe.lastPathComponent=="transparent-1.jpg","existing symlink not replaced")
        check(try Data(contentsOf:source)==original,"collision source remains unchanged")
        let previous=try Data(contentsOf:safe)
        let again=try DragImageConverter.convert(source,to:.jpg,preferences:preferences)
        check(again.lastPathComponent=="transparent-2.jpg","collision auto numbering")
        check(try Data(contentsOf:safe)==previous,"previous output not replaced")
        preferences.outputDirectory=root.appendingPathComponent("missing/subfolder").path
        expectError("bad destination explicit failure"){_ = try DragImageConverter.convert(source,to:.jpg,preferences:preferences)}
        let hidden=try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).filter{$0.lastPathComponent.hasPrefix(".nuphy-convert-")}
        check(hidden.isEmpty,"temporary outputs cleaned")
        let result:[String:Any] = ["passed":true,"checks":checks,"scope":"pure drag state, screen geometry, real ImageIO and output safety; not physical drag timing"]
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("RESULT.json"))
        print("PASS \(checks) checks")
    }
    static func main() throws { try run() }
}
