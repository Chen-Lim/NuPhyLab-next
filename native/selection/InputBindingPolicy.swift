// Adapted from apps/macos/Sources/ChordCore/InputBinding.swift.
// Standalone single-selection extraction; see source-provenance.json for changes and hashes.
import Foundation

public enum InputBindingIssue: Error, Equatable {
    case reservedSystemInput, escapeReserved, capsLockToggle, modifierRequiresFlags, invalidKey, invalidMouseButton, invalidModifiers
}
public enum InputBindingPolicy {
    public static func issue(for binding: InputBinding) -> InputBindingIssue? {
        let known: InputModifiers = [.control, .option, .shift, .command, .function]
        guard binding.modifiers.subtracting(known).isEmpty else { return .invalidModifiers }
        switch binding.kind {
        case .disabled: return nil
        case .modifiers:
            guard binding.keyCode == nil, binding.buttonIndex == nil, !binding.modifiers.isEmpty else { return .invalidModifiers }
        case .keyboard:
            guard binding.buttonIndex == nil, let code = binding.keyCode, code <= 126 else { return .invalidKey }
            if code == 53 { return .escapeReserved }
            if code == 57 { return .capsLockToggle }
            if ModifierEventState.modifierKeyCodes.contains(code) { return .modifierRequiresFlags }
            let flags = binding.modifiers.subtracting(.function)
            if (code == 48 && flags.contains(.command)) ||
                (code == 49 && (flags == .command || flags == .control || flags == [.control, .option])) ||
                (code == 12 && flags.isSuperset(of: [.control, .command])) { return .reservedSystemInput }
        case .mouseButton:
            guard binding.keyCode == nil, let index = binding.buttonIndex, (3...31).contains(index) else { return .invalidMouseButton }
        }
        return nil
    }
}
