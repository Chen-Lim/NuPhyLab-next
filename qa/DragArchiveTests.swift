import Foundation
import AppKit
import Darwin

@main struct DragArchiveTests {
    static var passed:[String]=[]
    static func check(_ condition:Bool,_ name:String) {guard condition else {fatalError(name)};passed.append(name)}
    static func fails(_ name:String,_ body:() throws -> Void) {do {try body();fatalError("Expected failure: \(name)")} catch {passed.append(name)}}
    static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]).standardizedFileURL
        let fixtures=URL(fileURLWithPath:CommandLine.arguments[2]).standardizedFileURL
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        var prefs=DragConvertPreferences();prefs.outputDirectory=root.path
        let sources=root.appendingPathComponent("sources"),folder=sources.appendingPathComponent("中文 资料")
        try FileManager.default.createDirectory(at:folder.appendingPathComponent("空目录"),withIntermediateDirectories:true)
        let file=folder.appendingPathComponent("笔记.txt"),blob=sources.appendingPathComponent("data.bin")
        try Data("hello 中文\n".utf8).write(to:file);try Data(repeating:65,count:256*1024).write(to:blob)
        let original=try Data(contentsOf:file)
        let executable=sources.appendingPathComponent("inert-fixture.command")
        try Data("fixture data only; never executed".utf8).write(to:executable)
        check(chmod(executable.path,0o700)==0,"fixture executable bit set")
        let marker=Data("0083;65000000;NuPhyLab-QA;00000000-0000-0000-0000-000000000000".utf8)
        let attributeResult=marker.withUnsafeBytes{setxattr(executable.path,"com.apple.quarantine",$0.baseAddress,marker.count,0,0)}
        check(attributeResult==0,"fixture download marker set")
        let protectedZIP=try DragArchiveConverter.convert([executable],to:.zip,preferences:prefs,control:DragJobControl())
        func markerAt(_ url:URL)->Data {
            var value=Data(count:1024)
            let count=value.withUnsafeMutableBytes{getxattr(url.path,"com.apple.quarantine",$0.baseAddress,1024,0,0)}
            return count<0 ? Data():value.prefix(count)
        }
        check(markerAt(protectedZIP)==marker,"packing retains source quarantine")
        let protectedOutput=try DragArchiveConverter.convert([protectedZIP],to:.extract,preferences:prefs,control:DragJobControl())
        let protectedFile=protectedOutput.appendingPathComponent(executable.lastPathComponent)
        check(markerAt(protectedOutput)==marker && markerAt(protectedFile)==marker,"extract propagates quarantine to directory and file")
        check(try Data(contentsOf:protectedFile)==Data(contentsOf:executable),"quarantine propagation preserves inert payload")
        let normal=try DragArchiveConverter.convert([folder,blob],to:.zip,preferences:prefs,control:DragJobControl())
        let extracted=try DragConverter.convert([normal],to:.extract,preferences:prefs,control:DragJobControl())
        check(try Data(contentsOf:extracted.appendingPathComponent("中文 资料/笔记.txt"))==original,"Unicode paths roundtrip")
        check(try Data(contentsOf:extracted.appendingPathComponent("data.bin")).count==256*1024,"multi-select combines all inputs")
        check(FileManager.default.fileExists(atPath:extracted.appendingPathComponent("中文 资料/空目录").path),"empty directories retained")
        let store=try DragArchiveConverter.convert([blob],to:.zipFast,preferences:prefs,control:DragJobControl())
        check(try Data(contentsOf:store).count>Data(contentsOf:normal).count,"store-only ZIP is distinct from compressed ZIP")
        let tar=try DragArchiveConverter.convert([folder,blob],to:.tarGz,preferences:prefs,control:DragJobControl())
        let untar=try DragArchiveConverter.convert([tar],to:.extract,preferences:prefs,control:DragJobControl())
        check(try Data(contentsOf:untar.appendingPathComponent("中文 资料/笔记.txt"))==original,"TAR.GZ roundtrip")
        let each=try DragConverter.convert([blob],to:.zipEach,preferences:prefs,control:DragJobControl())
        check(each.pathExtension=="zip","individual job accepts zipEach after batch grouping")
        let again=try DragArchiveConverter.convert([normal],to:.extract,preferences:prefs,control:DragJobControl())
        check(again != extracted && FileManager.default.fileExists(atPath:extracted.path),"extraction never replaces previous directory")
        let duplicateDir=sources.appendingPathComponent("other")
        try FileManager.default.createDirectory(at:duplicateDir,withIntermediateDirectories:true)
        let duplicate=duplicateDir.appendingPathComponent("data.bin");try Data("second source".utf8).write(to:duplicate)
        let duplicateZip=try DragArchiveConverter.convert([blob,duplicate],to:.zip,preferences:prefs,control:DragJobControl())
        let duplicateResult=try DragArchiveConverter.convert([duplicateZip],to:.extract,preferences:prefs,control:DragJobControl())
        check(try FileManager.default.contentsOfDirectory(atPath:duplicateResult.path).sorted()==["data-2.bin","data.bin"],"same basenames from different folders retained distinctly")
        let nested=try DragArchiveConverter.convert([folder,file],to:.zip,preferences:prefs,control:DragJobControl())
        let nestedResult=try DragArchiveConverter.convert([nested],to:.extract,preferences:prefs,control:DragJobControl())
        check(try FileManager.default.contentsOfDirectory(atPath:nestedResult.path)==["中文 资料"],"parent and selected child stored once")
        var inside=prefs;inside.outputDirectory=folder.path
        let insideZip=try DragArchiveConverter.convert([folder],to:.zip,preferences:inside,control:DragJobControl())
        check(try Data(contentsOf:insideZip).count<10000,"output inside selected directory cannot archive itself")
        let link=sources.appendingPathComponent("link");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:blob)
        fails("packing symlink refused without following target"){_ = try DragArchiveConverter.convert([link],to:.zip,preferences:prefs,control:DragJobControl())}
        for name in ["normal.zip","test_read_format_7zip_copy.7z","test_read_format_rar5_stored.rar","reference.tar","reference.tar.gz","reference.tar.bz2","reference.tar.xz","hello.txt.gz","hello.txt.bz2","hello.txt.xz","empty.zip"] {
            let output=try DragArchiveConverter.convert([fixtures.appendingPathComponent(name)],to:.extract,preferences:prefs,control:DragJobControl())
            check(FileManager.default.fileExists(atPath:output.path),"extract system format \(name)")
            if name.hasPrefix("hello") {check(try Data(contentsOf:output.appendingPathComponent("hello.txt"))==Data("compressed single file".utf8),"single stream payload \(name)")}
            if name=="normal.zip" {check(try Data(contentsOf:output.appendingPathComponent("line\nbreak.txt"))==Data("newlines are filenames".utf8),"newline filename is data, not a command")}
        }
        for name in ["traversal.zip","absolute.zip","backslash.zip","drive.zip","duplicate.zip","symlink.zip","hardlink.tar","huge.tar","crc.zip","broken.zip","fake.gz","encrypted.zip","test_read_format_rar.rar"] {
            fails("reject \(name)"){_ = try DragArchiveConverter.convert([fixtures.appendingPathComponent(name)],to:.extract,preferences:prefs,control:DragJobControl())}
        }
        let cancelled=DragJobControl();cancelled.cancel()
        fails("cancelled pack has no published output"){_ = try DragArchiveConverter.convert([blob],to:.zip,preferences:prefs,control:cancelled)}
        fails("cancelled extract has no published output"){_ = try DragArchiveConverter.convert([normal],to:.extract,preferences:prefs,control:cancelled)}
        check(try Data(contentsOf:file)==original,"source bytes retained")
        check(try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).allSatisfy{!$0.lastPathComponent.hasPrefix(".nuphy-convert-")},"all failed staging directories removed")
        check(!FileManager.default.fileExists(atPath:root.appendingPathComponent("escaped.txt").path),"no traversal payload escaped staging")
        for count in 3...8 {for i in 0..<count {check(DragWheelGeometry.hit(DragWheelGeometry.labelPoint(i,count:count),count:count)==i,"\(count)-target geometry \(i)")}}
        check(DragFileKind.actions(for:[file,blob]) == [.zip,.zipEach,.tarGz],"mixed content offers packing")
        check(DragFileKind.actions(for:[normal,tar]).first == .extract,"multiple archives prioritise extraction")
        try JSONSerialization.data(withJSONObject:["passed":true,"checks":passed.count,"assertions":passed],options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("ARCHIVE_RESULT.json"))
        print("PASS \(passed.count) archive checks")
    }
}
