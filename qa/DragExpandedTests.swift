import AppKit
import PDFKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

@main struct DragExpandedTests {
    static var passed: [String] = []
    static func check(_ value: Bool, _ name: String) { guard value else { fatalError(name) }; passed.append(name) }
    static func fails(_ name: String, _ block: () throws -> Void) { do { try block(); fatalError("Expected error: \(name)") } catch { passed.append(name) } }
    static func pixelImage(_ width: Int, _ height: Int) -> CGImage {
        let c = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(gray:0.25,alpha:1));c.fill(CGRect(x:0,y:0,width:width,height:height));return c.makeImage()!
    }
    static func createPDF(_ url: URL, pages: Int) throws {
        let c = CGContext(consumer:CGDataConsumer(url:url as CFURL)!,mediaBox:nil,nil)!
        for i in 0..<pages {
            var rect=CGRect(x:0,y:0,width:240+i*40,height:180)
            c.beginPDFPage([kCGPDFContextMediaBox:Data(bytes:&rect,count:MemoryLayout<CGRect>.size)] as CFDictionary)
            c.setFillColor(CGColor(gray:0.2+Double(i)*0.3,alpha:1));c.fill(rect);c.endPDFPage()
        };c.closePDF()
    }
    static func audio(_ url: URL) throws {
        let format=AVAudioFormat(standardFormatWithSampleRate:44100,channels:2)!
        let file=try AVAudioFile(forWriting:url,settings:[AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:44100,AVNumberOfChannelsKey:2,AVLinearPCMBitDepthKey:16,AVLinearPCMIsFloatKey:false,AVLinearPCMIsBigEndianKey:false])
        let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:88200)!;buffer.frameLength=88200
        for i in 0..<88200 {let sample=Float(sin(Double(i)*2*Double.pi*330/44100)*0.1);buffer.floatChannelData![0][i]=sample;buffer.floatChannelData![1][i]=sample}
        try file.write(from:buffer)
    }
    static func video(_ url: URL) throws {
        let writer=try AVAssetWriter(outputURL:url,fileType:.mov)
        let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:320,AVVideoHeightKey:180])
        let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB,kCVPixelBufferWidthKey as String:320,kCVPixelBufferHeightKey as String:180])
        writer.add(input);check(writer.startWriting(),"video fixture starts");writer.startSession(atSourceTime:.zero)
        for i in 0..<30 {
            while !input.isReadyForMoreMediaData {Thread.sleep(forTimeInterval:0.002)}
            var pixel:CVPixelBuffer?;CVPixelBufferPoolCreatePixelBuffer(nil,adaptor.pixelBufferPool!,&pixel)
            CVPixelBufferLockBaseAddress(pixel!,[])
            memset(CVPixelBufferGetBaseAddress(pixel!),Int32(i*5),CVPixelBufferGetDataSize(pixel!))
            CVPixelBufferUnlockBaseAddress(pixel!,[])
            check(adaptor.append(pixel!,withPresentationTime:CMTime(value:Int64(i),timescale:15)),"video fixture frame \(i)")
        }
        input.markAsFinished();let sem=DispatchSemaphore(value:0);writer.finishWriting{sem.signal()};sem.wait()
        check(writer.status == .completed,"video fixture finalized")
    }
    static func run(_ root: URL) throws {
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        var prefs=DragConvertPreferences();prefs.maxDimension=800
        let image=root.appendingPathComponent("image.png")
        try DragImageConverter.encode(pixelImage(640,360),to:image,format:.png,quality:0.88)
        let imageBytes=try Data(contentsOf:image)
        for format in [DragFormat.heic,.tiff] {
            let output=try DragConverter.convert([image],to:format,preferences:prefs,control:DragJobControl())
            let decoded=try DragImageConverter.decode(output);check(decoded.width==640 && decoded.height==360,"\(format) real codec roundtrip")
        }
        let image2=root.appendingPathComponent("image2.png");try DragImageConverter.encode(pixelImage(120,240),to:image2,format:.png,quality:0.88)
        let imgPDF=try DragConverter.convert([image2,image],to:.imagesPDF,preferences:prefs,control:DragJobControl())
        let combined=PDFDocument(url:imgPDF)!;check(combined.pageCount==2,"two images become two PDF pages")
        check(combined.page(at:0)!.bounds(for:.mediaBox).width==640,"natural filename order for image PDF")
        let doc=root.appendingPathComponent("document.pdf"),doc2=root.appendingPathComponent("document2.pdf")
        try createPDF(doc,pages:2);try createPDF(doc2,pages:1);let original=try Data(contentsOf:doc)
        let merged=try DragConverter.convert([doc2,doc],to:.mergePDF,preferences:prefs,control:DragJobControl())
        check(PDFDocument(url:merged)?.pageCount==3,"merge PDF retains all pages")
        for format in [DragFormat.splitPDF,.pdfPNG,.pdfJPG] {
            let folder=try DragConverter.convert([doc],to:format,preferences:prefs,control:DragJobControl())
            let files=try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).sorted{$0.path<$1.path}
            check(files.count==2,"\(format) publishes complete page folder")
            if format == .splitPDF {check(PDFDocument(url:files[0])?.pageCount==1,"split each page is valid PDF")}
            else {let decoded=try DragImageConverter.decode(files[0]);check(decoded.width==480 && decoded.height==360,"\(format) render dimensions")}
            let repeatFolder=try DragConverter.convert([doc],to:format,preferences:prefs,control:DragJobControl())
            check(repeatFolder != folder,"\(format) directory collision preserved")
        }
        let rotated=PDFDocument(url:doc)!;rotated.page(at:0)!.rotation=90
        let rotatedImage=try DragDocumentConverter.render(rotated.page(at:0)!,maxDimension:800)
        check(rotatedImage.width==360 && rotatedImage.height==480,"PDF page rotation changes canvas")
        let bytes=CFDataGetBytePtr(rotatedImage.dataProvider!.data!)!;check(bytes[0]<150,"rotated PDF fills rendered canvas")
        let locked=root.appendingPathComponent("locked.pdf")
        check(PDFDocument(url:doc)!.write(to:locked,withOptions:[PDFDocumentWriteOption.ownerPasswordOption:"private-test",PDFDocumentWriteOption.userPasswordOption:"private-test"]),"encrypted PDF fixture")
        fails("password-protected PDF refused"){_ = try DragConverter.convert([locked],to:.pdfPNG,preferences:prefs,control:DragJobControl())}
        let malformed=root.appendingPathComponent("broken.pdf");try Data("broken".utf8).write(to:malformed)
        fails("malformed PDF refused"){_ = try DragConverter.convert([malformed],to:.splitPDF,preferences:prefs,control:DragJobControl())}
        let cancelled=DragJobControl();cancelled.cancel()
        fails("cancelled job does not produce files"){_ = try DragConverter.convert([doc],to:.pdfPNG,preferences:prefs,control:cancelled)}
        fails("staged failure removes partial output") {
            _ = try DragOutput.write(input:doc,preferences:prefs,ext:"txt") { file in try Data("partial".utf8).write(to:file);throw DragConvertError.encoding }
        }
        let sound=root.appendingPathComponent("tone.wav");try audio(sound);let soundBytes=try Data(contentsOf:sound)
        for format in [DragFormat.m4a,.wav,.aiff] {
            let output=try DragConverter.convert([sound],to:format,preferences:prefs,control:DragJobControl())
            let file=try AVAudioFile(forReading:output)
            check(abs(Double(file.length)/file.fileFormat.sampleRate-2)<0.1,"\(format) audio duration")
            let buffer=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:4096)!;try file.read(into:buffer)
            check(buffer.frameLength>100 && (0..<Int(buffer.frameLength)).contains{abs(buffer.floatChannelData![0][$0])>0.02},"\(format) output has real audio samples")
        }
        let clip=root.appendingPathComponent("silent.mov");try video(clip);let clipBytes=try Data(contentsOf:clip)
        for format in [DragFormat.mp4,.mov,.video720,.video1080] {
            let output=try DragConverter.convert([clip],to:format,preferences:prefs,control:DragJobControl())
            let asset=AVURLAsset(url:output);check(!asset.tracks(withMediaType:.video).isEmpty && abs(asset.duration.seconds-2)<0.15,"\(format) real video output")
        }
        fails("silent video gives no-audio error"){_ = try DragConverter.convert([clip],to:.m4a,preferences:prefs,control:DragJobControl())}
        let composition=AVMutableComposition()
        let v=AVURLAsset(url:clip),a=AVURLAsset(url:sound),range=CMTimeRange(start:.zero,duration:CMTime(seconds:2,preferredTimescale:600))
        try composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid)!.insertTimeRange(range,of:v.tracks(withMediaType:.video)[0],at:.zero)
        try composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid)!.insertTimeRange(range,of:a.tracks(withMediaType:.audio)[0],at:.zero)
        let movie=root.appendingPathComponent("movie.mov"),export=AVAssetExportSession(asset:composition,presetName:AVAssetExportPresetHighestQuality)!
        export.outputURL=movie;export.outputFileType = .mov;let sem=DispatchSemaphore(value:0);export.exportAsynchronously{sem.signal()};sem.wait();check(export.status == .completed,"video with audio fixture")
        let extracted=try DragConverter.convert([movie],to:.m4a,preferences:prefs,control:DragJobControl())
        check(AVURLAsset(url:extracted).tracks(withMediaType:.video).isEmpty && !AVURLAsset(url:extracted).tracks(withMediaType:.audio).isEmpty,"extract audio omits video")
        check(try Data(contentsOf:doc)==original && Data(contentsOf:image)==imageBytes && Data(contentsOf:sound)==soundBytes && Data(contentsOf:clip)==clipBytes,"all source files preserved")
        for count in 3...9 {for index in 0..<count {check(DragWheelGeometry.hit(DragWheelGeometry.labelPoint(index,count:count),count:count)==index,"\(count)-way label matches target \(index)")}}
        check(DragFileKind.actions(for:[image]).count==9,"image conversion and packing actions")
        check(DragFileKind.actions(for:[doc]).count==5 && DragFileKind.actions(for:[doc,doc2]).count==6,"merge only on multi PDF")
        check(DragFileKind.actions(for:[movie,sound]) == [.m4a,.wav,.aiff,.zip,.zipEach],"mixed media shares audio operations")
        check(DragFileKind.actions(for:[image,doc]) == [.zip,.zipEach,.tarGz],"mixed file types offer packing")
        check(try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).filter{$0.lastPathComponent.hasPrefix(".nuphy-convert-")}.isEmpty,"no partial staging files remain")
        try JSONSerialization.data(withJSONObject:["passed":true,"checks":passed.count,"assertions":passed],options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("EXPANDED_RESULT.json"))
        print("PASS \(passed.count) expanded checks")
    }
    static func main() {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]).standardizedFileURL
        DispatchQueue.global(qos:.userInitiated).async {do{try run(root);exit(0)}catch{print("FAIL: \(error)");exit(1)}}
        RunLoop.main.run()
    }
}
