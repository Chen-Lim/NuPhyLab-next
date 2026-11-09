import AppKit
import Carbon
@main struct DragTriggerTests {
 static var checks=[String]()
 static func check(_ value:Bool,_ name:String) {precondition(value,name);checks.append(name)}
 static func main() throws {
  _ = NSApplication.shared
  let root=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  let options=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))) as! [[String:String]]
  check(Set(options.map{$0["value"]!}).count==options.count,"UI trigger IDs unique")
  check(options.count==DragTrigger.keyCodes.count+4,"UI and native catalogs same count")
  for row in options {
   let raw=row["value"]!;check(DragTrigger(raw) != nil,"UI key validated: \(raw)")
   var prefs=DragConvertPreferences();prefs.trigger=raw;let validated=try prefs.validated()
   let read=try JSONDecoder().decode(DragConvertPreferences.self,from:JSONEncoder().encode(validated))
   check(read==validated,"key survives codable roundtrip: \(raw)")
  }
  for raw in ["key:53","key:57","key:63","key:-1","key:001","key:128","key:65536","key:12+13","shift+option",""] {check(DragTrigger(raw)==nil,"reject invalid or reserved: \(raw)")}
  for (name,flag) in [("shift",NSEvent.ModifierFlags.shift),("option",.option),("control",.control),("command",.command)] {
   let trigger=DragTrigger(name)!
   check(trigger.isPressed(flags:flag,keyDown:{_ in false}),"single modifier held \(name)")
   check(!trigger.isPressed(flags:[],keyDown:{_ in true}),"modifier released \(name)")
   check(!trigger.isPressed(flags:[.shift,.command,.control,.option],keyDown:{_ in true}),"no chord match \(name)")
  }
  for code in DragTrigger.keyCodes {
   let trigger=DragTrigger("key:\(code)")!
   check(trigger.isPressed(flags:[],keyDown:{$0==code}),"physical key matches \(code)")
   check(!trigger.isPressed(flags:[],keyDown:{$0 != code}),"other key does not match \(code)")
   check(!trigger.isPressed(flags:.command,keyDown:{_ in true}),"shortcut chord not a drag trigger \(code)")
  }
  check(!DragTrigger("key:0")!.isPressed(flags:.function,keyDown:{_ in true}),"Fn A is not plain A")
  check(DragTrigger("key:122")!.isPressed(flags:.function,keyDown:{_ in true}),"automatic F1 function flag allowed")
  check(!DragTrigger("shift")!.isPressed(flags:[.function,.shift],keyDown:{_ in true}),"Fn Shift is not single Shift")
  let sources=TISCreateInputSourceList([kTISPropertyInputSourceCategory:kTISCategoryKeyboardInputSource] as CFDictionary,true).takeRetainedValue() as! [TISInputSource]
  var layouts=Set<String>()
  for source in sources {
   guard let raw=TISGetInputSourceProperty(source,kTISPropertyInputSourceID) else{continue}
   let id=Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
   guard ["com.apple.keylayout.ABC","com.apple.keylayout.French","com.apple.keylayout.Dvorak","com.apple.keylayout.German"].contains(id) else{continue}
   let labels=DragTrigger.labels(for:source);layouts.insert(id)
   check(!labels.isEmpty,"system layout labels exist \(id)")
   if id.hasSuffix("ABC"){check(labels["key:0"]=="A" && labels["key:12"]=="Q","ABC shown key agrees with physical code")}
   if id.hasSuffix("French"){check(labels["key:0"]=="Q" && labels["key:12"]=="A","French A is actual A key")}
   if id.hasSuffix("German"){check(labels["key:27"]=="ß","German sharp s remains one actual key label")}
   if id.hasSuffix("Dvorak"){check(labels["key:12"]=="'","Dvorak key label")}
  }
  check(layouts.count==4,"four system layouts tested without switching user input")
  for (raw,mask) in [("shift",UInt32(shiftKey)),("option",UInt32(optionKey)),("control",UInt32(controlKey)),("command",UInt32(cmdKey))] {
   check(DragTrigger.selectionReservation(keyCode:0,modifiers:mask,modifierOnly:true)==raw,"single modifier selection reservation \(raw)")
  }
  check(DragTrigger.selectionReservation(keyCode:0,modifiers:0,modifierOnly:false)=="key:0","selection plain A reservation")
  check(DragTrigger.selectionReservation(keyCode:0,modifiers:UInt32(cmdKey),modifierOnly:false)==nil,"modified A does not conflict")
  check(DragTrigger.selectionReservation(keyCode:0,modifiers:UInt32(cmdKey|shiftKey),modifierOnly:true)==nil,"modifier chord does not conflict")
  check(DragTrigger.selectionReservation(keyCode:123,modifiers:1<<23,modifierOnly:false)=="key:123","arrow function flag reservation matches polling")
  check(DragTrigger.selectionReservation(keyCode:122,modifiers:1<<23,modifierOnly:false)=="key:122","F1 function flag reservation matches polling")
  check(DragTrigger.selectionReservation(keyCode:0,modifiers:1<<23,modifierOnly:false)==nil,"Fn A remains distinct")
  var legacy=DragConvertPreferences();legacy.enabled=true;legacy.trigger="option"
  let file=root.appendingPathComponent("drag-convert.json");try JSONEncoder().encode(legacy).write(to:file)
  let controller=DragConvertController(directory:root,observeDrags:false);var granted=false;controller.inputAccess={granted}
  var reserved=Set<UInt32>();controller.reservedKeyCodes={reserved}
  func call(_ body:[String:Any]) -> ([String:Any]?,String?) {var answer:[String:Any]?;var failure:String?;controller.handle(body){result,error in answer=result as? [String:Any];failure=error};return(answer,failure)}
  func save(_ value:String) -> ([String:Any]?,String?) {var next=controller.preferences;next.trigger=value;return call(["op":"settings","preferences":try! JSONSerialization.jsonObject(with:JSONEncoder().encode(next))])}
  check(controller.preferences.trigger=="option","legacy Option retained")
  check(call(["op":"status"]).0?["inputPermissionNeeded"] as? Bool==false,"modifiers do not introduce input permission requirement")
  check(save("key:0").1==nil,"A saves while input access pending")
  check(call(["op":"status"]).0?["inputPermissionNeeded"] as? Bool==true,"missing permission visible")
  granted=true
  check(call(["op":"status"]).0?["issue"] as? String=="","grant takes effect without restart")
  controller.shutdown()
  let reopened=DragConvertController(directory:root,observeDrags:false);check(reopened.preferences.trigger=="key:0","custom key persists after reopen");reopened.shutdown()
  reserved=[122]
  let before=try Data(contentsOf:file)
  check(save("key:122").1 != nil,"reserved AI key rejected")
  check(try Data(contentsOf:file)==before,"rejected change does not touch saved preferences")
  reserved=[];check(save("key:122").1==nil,"F1 allowed while AI does not reserve it")
  reserved=[122];check((call(["op":"status"]).0?["issue"] as? String ?? "").contains("AI"),"later AI conflict is surfaced")
  check(save("shift").1==nil,"reset to default Shift")
  granted=false;check(call(["op":"status"]).0?["issue"] as? String=="","default remains usable without added permission")
  check(save("key:53").1 != nil,"Esc remains cancellation through native settings API")
  var selection:String?="shift";controller.selectionReservedTrigger={selection}
  check((call(["op":"status"]).0?["issue"] as? String ?? "").contains("Ask about"),"later selection binding pauses existing Shift")
  check(save("key:0").1==nil,"other key avoids selection conflict")
  let conflictBefore=try Data(contentsOf:file)
  check(save("shift").1 != nil,"modifier already used by selection rejected")
  check(try Data(contentsOf:file)==conflictBefore,"selection conflict keeps preference bytes")
  selection="key:0";check((call(["op":"status"]).0?["issue"] as? String ?? "").contains("Ask about"),"later selection A is detected regardless of gesture order")
  var unrelated=controller.preferences;unrelated.quality=0.72
  check(call(["op":"settings","preferences":try! JSONSerialization.jsonObject(with:JSONEncoder().encode(unrelated))]).1==nil,"unrelated quality setting remains editable during conflict")
  check(controller.preferences.quality==0.72 && controller.preferences.trigger=="key:0","quality saves without changing conflicted key")
  selection=nil;granted=true;check(call(["op":"status"]).0?["issue"] as? String=="","selection disabling frees key without restarting")
  check(save("shift").1==nil,"default restored after conflict ends")
  controller.shutdown()
  try JSONSerialization.data(withJSONObject:["passed":true,"checks":checks.count,"assertions":checks],options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("TRIGGER_RESULT.json"))
  print("PASS \(checks.count) trigger checks")
 }
}
