import AppKit
import QuartzCore
import ImageIO
import UniformTypeIdentifiers

@main struct DragWebPTests {
    static var checks = [String]()
    static func check(_ condition: Bool, _ name: String) { precondition(condition,name); checks.append(name) }
    static func fails(_ name: String, _ block: () throws -> Void) {
        do { try block(); preconditionFailure(name) } catch { checks.append(name) }
    }
    static func rgba(_ image: CGImage) -> [UInt8] {
        let context = CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,
            space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        return Array(UnsafeBufferPointer(start:context.data!.assumingMemoryBound(to:UInt8.self),count:image.width*image.height*4))
    }
    static func fixture(_ width: Int = 128, _ height: Int = 96) -> CGImage {
        let c = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
            space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        for y in 0..<height { for x in 0..<width {
            c.setFillColor(CGColor(srgbRed:CGFloat(x%17)/16,green:CGFloat(y%13)/12,blue:CGFloat((x+y)%11)/10,alpha:x<width/3 ? 0 : x<width*2/3 ? 0.5 : 1))
            c.fill(CGRect(x:x,y:y,width:1,height:1))
        }}
        return c.makeImage()!
    }
    static func main() throws {
        _ = NSApplication.shared
        let root=URL(fileURLWithPath:CommandLine.arguments[1]); try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let image=fixture(), input=root.appendingPathComponent("透明 色彩.png")
        try DragImageConverter.encode(image,to:input,format:.png,quality:1)
        let source=try Data(contentsOf:input), original=rgba(try DragImageConverter.decode(input))
        var prefs=DragConvertPreferences()
        for quality in [0.72,0.88,0.96,1.0] {
            prefs.quality=quality
            let file=try DragConverter.convert([input],to:.webp,preferences:prefs,control:DragJobControl())
            let bytes=try Data(contentsOf:file)
            check(String(data:bytes.prefix(4),encoding:.ascii)=="RIFF" && String(data:bytes[8..<12],encoding:.ascii)=="WEBP","real WebP header at quality \(quality)")
            let output=try DragImageConverter.decode(file), pixels=rgba(output)
            check(output.width==128 && output.height==96,"dimensions preserved \(quality)")
            check(stride(from:3,to:pixels.count,by:4).allSatisfy {pixels[$0]==original[$0]},"transparent and translucent alpha preserved \(quality)")
            if quality==1 {check(zip(original,pixels).allSatisfy {abs(Int($0)-Int($1))<=1},"lossless RGB, alpha and orientation round trip")}
        }
        check(try Data(contentsOf:input)==source,"original unchanged across four encodes")
        let existing=root.appendingPathComponent("透明 色彩.webp"), before=try Data(contentsOf:existing)
        let extra=try DragImageConverter.convert(existing,to:.webp,preferences:prefs)
        let existingAfter=try Data(contentsOf:existing)
        check(extra != existing && existingAfter==before,"WebP to WebP collision never overwrites input")
        let rotated=root.appendingPathComponent("rotated.jpg")
        let destination=CGImageDestinationCreateWithURL(rotated as CFURL,UTType.jpeg.identifier as CFString,1,nil)!
        CGImageDestinationAddImage(destination,image,[kCGImagePropertyOrientation:6] as CFDictionary);check(CGImageDestinationFinalize(destination),"rotated fixture")
        let upright=try DragImageConverter.convert(rotated,to:.webp,preferences:prefs)
        let decoded=try DragImageConverter.decode(upright)
        check(decoded.width==96 && decoded.height==128,"EXIF portrait rotation survives WebP")
        let cancelled=DragJobControl();cancelled.cancel()
        fails("cancelled before encode") {_ = try DragConverter.convert([input],to:.webp,preferences:prefs,control:cancelled)}
        var calls=0
        fails("cancel from encoder progress") {
            _ = try DragImageConverter.convert(input,to:.webp,preferences:prefs,check:{calls+=1;if calls>=5 {throw DragJobError.cancelled}})
        }
        check(calls>=5,"encoder called cancellation hook")
        let files=try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)
        check(!files.contains{$0.lastPathComponent.hasPrefix(".nuphy-convert-")},"cancelled staging cleaned")
        let wide=fixture(16384,1)
        fails("WebP dimension bound before allocation") {try DragWebPEncoder.encode(wide,to:root.appendingPathComponent("too-wide.webp"),quality:1,check:{})}
        check(!FileManager.default.fileExists(atPath:root.appendingPathComponent("too-wide.webp").path),"oversize creates no output")
        let widePNG=root.appendingPathComponent("wide-source.png")
        try DragImageConverter.encode(wide,to:widePNG,format:.png,quality:1)
        fails("metadata WebP edge limit before decode") {_ = try DragImageConverter.decode(widePNG,sourceEdgeLimit:16_383)}
        fails("production WebP edge limit") {_ = try DragImageConverter.convert(widePNG,to:.webp,preferences:prefs)}
        check(!FileManager.default.fileExists(atPath:root.appendingPathComponent("wide-source.webp").path),"oversize production has no output")
        let view=DragConvertWheelView(frame:CGRect(x:0,y:0,width:252,height:252))
        view.configure(urls:[input],english:false)
        let layers=view.layer!.sublayers!, sectors=layers.compactMap{$0 as? CAShapeLayer}, labels=layers.compactMap{$0 as? CATextLayer}
        check(sectors.count==9,"nine image actions are visible")
        func hex(_ color:CGColor?) -> String {
            let c=NSColor(cgColor:color!)!.usingColorSpace(.sRGB)!
            return String(format:"#%02X%02X%02X",Int((c.redComponent*255).rounded()),Int((c.greenComponent*255).rounded()),Int((c.blueComponent*255).rounded()))
        }
        check(hex(view.layer!.backgroundColor)=="#141414" && hex(view.layer!.borderColor)=="#636363","approved base and border")
        check(sectors.allSatisfy{hex($0.fillColor)=="#292929" && hex($0.strokeColor)=="#5A5A5A"},"approved idle fill and stroke")
        check(labels.prefix(10).allSatisfy{hex($0.foregroundColor)=="#EDEDED"} && hex(labels.last!.foregroundColor)=="#A0A0A0","approved labels, count and detail")
        for english in [false,true] {
            view.configure(urls:[input],english:english)
            view.trackPoint(DragWheelGeometry.labelPoint(2,count:9))
            check(hex(sectors[2].fillColor)=="#E6E6E6" && hex(sectors[2].strokeColor)=="#FFFFFF" && hex(labels[2].foregroundColor)=="#111111","approved hover palette \(english)")
            let context=CGContext(data:nil,width:504,height:504,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.scaleBy(x:2,y:2);view.layer!.render(in:context)
            try DragImageConverter.encode(context.makeImage()!,to:root.appendingPathComponent(english ? "menu-en.png":"menu-zh.png"),format:.png,quality:1)
            view.trackPoint(CGPoint(x:-100,y:-100))
            check(sectors.allSatisfy{hex($0.strokeColor)=="#5A5A5A" && hex($0.fillColor)=="#292929"},"leaving restores idle fill and borders \(english)")
        }
        try JSONSerialization.data(withJSONObject:["passed":true,"checks":checks.count,"assertions":checks],options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("WEBP_RESULT.json"))
        print("PASS \(checks.count) WebP and palette checks")
    }
}
