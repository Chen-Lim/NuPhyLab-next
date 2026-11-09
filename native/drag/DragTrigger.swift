import AppKit
import Carbon

/// A physical single key. Escape remains cancellation; combinations are not triggers.
struct DragTrigger: Equatable {
    let rawValue: String
    static let keyCodes: Set<CGKeyCode> = [0,1,2,3,4,5,6,7,8,9,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,96,97,98,99,100,101,103,109,111,114,115,116,117,118,119,120,121,122,123,124,125,126]
    init?(_ value: String) {
        if ["shift","option","control","command"].contains(value) { rawValue=value; return }
        guard value.hasPrefix("key:"), let code=UInt16(value.dropFirst(4)),
              value == "key:\(code)", Self.keyCodes.contains(code) else { return nil }
        rawValue=value
    }
    static func selectionReservation(keyCode:UInt32, modifiers:UInt32, modifierOnly:Bool) -> String? {
        if modifierOnly {
            switch modifiers {
            case UInt32(shiftKey): return "shift"
            case UInt32(optionKey): return "option"
            case UInt32(controlKey): return "control"
            case UInt32(cmdKey): return "command"
            default: return nil
            }
        }
        let effective = keyCode >= 96 ? modifiers & ~(1 << 23) : modifiers
        guard effective == 0 else { return nil }
        return DragTrigger("key:\(keyCode)")?.rawValue
    }
    static func labels(for source:TISInputSource) -> [String:String] {
        guard let raw=TISGetInputSourceProperty(source,kTISPropertyUnicodeKeyLayoutData) else {return [:]}
        let data=Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        guard let bytes=CFDataGetBytePtr(data) else{return [:]}
        let layout=UnsafeRawPointer(bytes).assumingMemoryBound(to:UCKeyboardLayout.self)
        var result=[String:String]()
        for code in keyCodes where code < 51 && ![36,48,49].contains(code) {
            var dead:UInt32=0, buffer=[UniChar](repeating:0,count:8), length=0
            let error=UCKeyTranslate(layout,code,UInt16(kUCKeyActionDisplay),0,UInt32(LMGetKbdType()),OptionBits(1 << kUCKeyTranslateNoDeadKeysBit),&dead,buffer.count,&length,&buffer)
            guard error == noErr, length > 0 else{continue}
            let rawName=String(utf16CodeUnits:buffer,count:length)
            // Uppercase ASCII letters only. Unicode casing can change a key's
            // identity (e.g. German ß -> SS or Greek final sigma -> Σ).
            let asciiLetter = rawName.utf16.count == 1 && rawName.unicodeScalars.first.map { (97...122).contains($0.value) } == true
            let name = asciiLetter ? rawName.uppercased() : rawName
            if name.count <= 4 && name.unicodeScalars.allSatisfy({!CharacterSet.controlCharacters.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0)}) { result["key:\(code)"]=name }
        }
        return result
    }
    private static var cachedLayout=""
    private static var cachedLabels=[String:String]()
    static func currentLabels() -> [String:String] {
        var source=TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        if TISGetInputSourceProperty(source,kTISPropertyUnicodeKeyLayoutData) == nil { source=TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue() }
        let id=TISGetInputSourceProperty(source,kTISPropertyInputSourceID).map{Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String} ?? ""
        let cacheKey="\(id):\(LMGetKbdType())"
        if cacheKey != cachedLayout { cachedLabels=labels(for:source);cachedLayout=cacheKey }
        return cachedLabels
    }
    var keyCode:CGKeyCode? { rawValue.hasPrefix("key:") ? UInt16(rawValue.dropFirst(4)) : nil }
    var needsInputAccess:Bool { keyCode != nil }
    func isPressed(flags:NSEvent.ModifierFlags, keyDown:(CGKeyCode)->Bool) -> Bool {
        let modifiers=flags.intersection([.shift,.option,.control,.command])
        if let code=keyCode { return modifiers.isEmpty && (!flags.contains(.function) || code >= 96) && keyDown(code) }
        let wanted:NSEvent.ModifierFlags
        switch rawValue {case "option":wanted = .option;case "control":wanted = .control;case "command":wanted = .command;default:wanted = .shift}
        return modifiers == wanted && !flags.contains(.function)
    }
}
