"""Production archive code with only the progress notification boundary instrumented.
The hook adds quarantine mid-operation to inert generated fixtures; nothing is executed.
"""
from pathlib import Path
from tempfile import TemporaryDirectory
import subprocess,json
root=Path(__file__).resolve().parents[1]
with TemporaryDirectory(prefix='nuphylab-quarantine-race-') as work:
 p=Path(work)
 document=(root/'native/drag/DragDocumentConverter.swift').read_text()
 needle='func update(_ value: Double) { lock.lock(); fraction = min(1, max(0, value)); lock.unlock() }'
 assert document.count(needle)==1
 document='var dragQuarantineTestProgressHook: (() -> Void)?\n'+document.replace(needle,needle[:-1]+'; if value > 0 { dragQuarantineTestProgressHook?() } }')
 (p/'DragDocumentConverter.swift').write_text(document)
 main=r'''
import Foundation
import Darwin
@main struct Check {
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1]),marker=Data("0083;65000000;NuPhyLab-QA;00000000-0000-0000-0000-000000000000".utf8)
  var prefs=DragConvertPreferences();prefs.enabled=true
  func mark(_ url:URL){precondition(marker.withUnsafeBytes{setxattr(url.path,"com.apple.quarantine",$0.baseAddress,marker.count,0,XATTR_NOFOLLOW)}==0)}
  func read(_ url:URL)->Data?{let n=getxattr(url.path,"com.apple.quarantine",nil,0,0,XATTR_NOFOLLOW);if n<0{return nil};var data=Data(count:n);let got=data.withUnsafeMutableBytes{getxattr(url.path,"com.apple.quarantine",$0.baseAddress,n,0,XATTR_NOFOLLOW)};precondition(got==n);return data}
  var checks=0
  for format in [DragFormat.zip,.zipFast,.tarGz] {
   let source=root.appendingPathComponent(format.rawValue+"-inert.bin")
   let bytes=Data((0..<131072).map{UInt8($0%251)});try bytes.write(to:source)
   precondition(read(source)==nil)
   var fired=false
   dragQuarantineTestProgressHook={if !fired{fired=true;mark(source)}}
   let packed=try DragArchiveConverter.convert([source],to:format,preferences:prefs,control:DragJobControl())
   dragQuarantineTestProgressHook=nil
   precondition(fired && read(source)==marker && read(packed)==marker);checks+=1
  }
  let plain=root.appendingPathComponent("extract-inert.bin");try Data("inert data; never executed".utf8).write(to:plain)
  let archive=try DragArchiveConverter.convert([plain],to:.zip,preferences:prefs,control:DragJobControl())
  precondition(read(archive)==nil)
  var fired=false
  dragQuarantineTestProgressHook={if !fired{fired=true;mark(archive)}}
  let folder=try DragArchiveConverter.convert([archive],to:.extract,preferences:prefs,control:DragJobControl())
  dragQuarantineTestProgressHook=nil
  precondition(fired && read(folder)==marker && read(folder.appendingPathComponent(plain.lastPathComponent))==marker);checks+=1
  print("PASS \(checks) mid-operation quarantine cases; inert fixtures; no execution")
 }
}
'''
 (p/'Check.swift').write_text(main)
 files=[str(f) for f in sorted((root/'native/drag').glob('*.swift')) if f.name!='DragDocumentConverter.swift']+[str(p/'DragDocumentConverter.swift'),str(root/'native/LabNotchGeometry.swift'),str(p/'Check.swift')]
 cmd=['swiftc','-swift-version','5','-import-objc-header',str(root/'native/AppBridge.h'),*files,'-o',str(p/'check'),'-larchive.2']
 for framework in ['AppKit','QuartzCore','SwiftUI','Carbon','ImageIO','UniformTypeIdentifiers','PDFKit','AVFoundation','CoreMedia']:cmd+=['-framework',framework]
 subprocess.run(cmd,cwd=root,check=True)
 fixtures=p/'fixtures';fixtures.mkdir()
 subprocess.run([str(p/'check'),str(fixtures)],check=True)
