// Adapted from apps/macos/Sources/ChordCore/ModifierEventState.swift.
// Standalone single-selection extraction; see source-provenance.json for changes and hashes.
import Foundation

/// Fn/Globe is a modifier, not F1–F20. Only a flagsChanged event for the
/// documented kVK_Function (0x3f) establishes its pressed state. A function bit
/// attached to an ordinary key event cannot invent a Fn press.
public struct ModifierEventState {
    public static let functionKeyCode: UInt16 = 0x3f
    public static let modifierKeyCodes: Set<UInt16> = [54,55,56,58,59,60,61,62,63]
    public private(set) var functionIsDown = false
    public init() {}

    /// A startup/configuration snapshot can inhibit an already-held Fn. It must
    /// not synthesize a fresh press from a later duplicate flagsChanged event.
    public mutating func prime(_ modifiers: InputModifiers) { functionIsDown = modifiers.contains(.function) }

    public mutating func flagsChanged(keyCode: UInt16, modifiers: InputModifiers) -> InputModifiers? {
        guard Self.modifierKeyCodes.contains(keyCode) else { return nil }
        if keyCode == Self.functionKeyCode || !modifiers.contains(.function) { functionIsDown = modifiers.contains(.function) }
        return normalized(modifiers)
    }
    public func normalized(_ modifiers: InputModifiers) -> InputModifiers {
        modifiers.subtracting(.function).union(functionIsDown && modifiers.contains(.function) ? .function : [])
    }
    public mutating func reset() { functionIsDown = false }
}

