import AppKit
import Carbon
@main struct Check {
 static func main(){
  _ = NSApplication.shared
  let list=TISCreateInputSourceList([kTISPropertyInputSourceCategory:kTISCategoryKeyboardInputSource] as CFDictionary,true).takeRetainedValue() as! [TISInputSource]
  var layouts=0,keys=0,errors=[[String:Any]]()
  for source in list {
   guard let raw=TISGetInputSourceProperty(source,kTISPropertyUnicodeKeyLayoutData),let rawID=TISGetInputSourceProperty(source,kTISPropertyInputSourceID) else{continue}
   let data=Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue(),id=Unmanaged<CFString>.fromOpaque(rawID).takeUnretainedValue() as String
   let pointer=UnsafeRawPointer(CFDataGetBytePtr(data)!).assumingMemoryBound(to:UCKeyboardLayout.self),actual=DragTrigger.labels(for:source);layouts+=1
   for code in DragTrigger.keyCodes where code < 51 && ![36,48,49].contains(code) {
    var dead:UInt32=0,buffer=[UniChar](repeating:0,count:64),length=0
    let status=UCKeyTranslate(pointer,code,UInt16(kUCKeyActionDisplay),0,UInt32(LMGetKbdType()),OptionBits(1<<kUCKeyTranslateNoDeadKeysBit),&dead,buffer.count,&length,&buffer)
    guard status==noErr,length>0 else{continue}
    let rawText=String(utf16CodeUnits:buffer,count:length)
    guard rawText.unicodeScalars.allSatisfy({!CharacterSet.controlCharacters.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0)}) else{continue}
    let shown=actual["key:\(code)"]
    let expected=rawText.unicodeScalars.allSatisfy({$0.value>=97 && $0.value<=122}) ? rawText.uppercased():rawText
    keys+=1
    if shown != expected {errors.append(["layout":id,"key":code,"system":rawText,"shown":shown ?? "missing"])}
   }
  }
  print(String(data:try! JSONSerialization.data(withJSONObject:["layouts":layouts,"printableKeys":keys,"errors":errors],options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
  if !errors.isEmpty{exit(1)}
 }
}
