// Adapted from apps/macos/Sources/Chord/Input/SelectionCapture.swift, apps/macos/Sources/Chord/Input/PermissionService.swift, apps/macos/Sources/Chord/Input/ScreenAwarenessService.swift.
// Standalone single-selection extraction; see source-provenance.json for changes and hashes.
import AppKit
import ApplicationServices
import Carbon
import CoreGraphics

public struct SelectionPermissions: Equatable, Sendable {
    public let accessibility: Bool
    public let inputMonitoring: Bool
    public let screenRecording: Bool
    public let secureInput: Bool

    /// Read-only. Host UI owns any permission explanation and explicit request.
    public static func current() -> Self {
        .init(accessibility: AXIsProcessTrusted(), inputMonitoring: CGPreflightListenEventAccess(),
              screenRecording: CGPreflightScreenCaptureAccess(), secureInput: IsSecureEventInputEnabled())
    }
}

public enum SelectedTextError: Error { case secureInput, permission, noTarget, noSelection, unsupportedSelection, accessibilityFailure }

/// Explicit user selection only. Does not copy the clipboard or synthesize keys.
public enum SelectionCapture {
    @MainActor public static func selectedText(target: NSRunningApplication?) throws -> String {
        guard !IsSecureEventInputEnabled() else { throw SelectedTextError.secureInput }
        guard AXIsProcessTrusted() else { throw SelectedTextError.permission }
        guard let target, !target.isTerminated,
              target.processIdentifier != ProcessInfo.processInfo.processIdentifier else { throw SelectedTextError.noTarget }
        let app = AXUIElementCreateApplication(target.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value)
        guard status == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            if status == .attributeUnsupported || status == .noValue { throw SelectedTextError.unsupportedSelection }
            throw SelectedTextError.accessibilityFailure
        }
        let focused = unsafeBitCast(value, to: AXUIElement.self)
        try assertNotProtected(focused)
        var result: CFTypeRef?
        switch AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &result) {
        case .success:
            try assertNotProtected(focused)
            guard let text = result as? String, !text.isEmpty else { throw SelectedTextError.noSelection }
            return IntentTextSafety.limited(text)
        case .noValue: throw SelectedTextError.noSelection
        case .attributeUnsupported, .notImplemented: throw SelectedTextError.unsupportedSelection
        default: throw SelectedTextError.accessibilityFailure
        }
    }

    private static func assertNotProtected(_ element: AXUIElement) throws {
        var current: AXUIElement? = element
        for _ in 0..<12 {
            guard !IsSecureEventInputEnabled() else { throw SelectedTextError.secureInput }
            guard let item = current else { return }
            AXUIElementSetMessagingTimeout(item, 0.15)
            var role: CFTypeRef?, subrole: CFTypeRef?, parent: CFTypeRef?
            AXUIElementCopyAttributeValue(item, kAXRoleAttribute as CFString, &role)
            AXUIElementCopyAttributeValue(item, kAXSubroleAttribute as CFString, &subrole)
            guard !IntentTextSafety.isProtected(role: role as? String, subrole: subrole as? String) else { throw SelectedTextError.secureInput }
            if [kAXWindowRole, kAXApplicationRole].contains(role as? String ?? "") { return }
            AXUIElementCopyAttributeValue(item, kAXParentAttribute as CFString, &parent)
            current = parent.flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? unsafeBitCast($0, to: AXUIElement.self) : nil }
        }
    }
}
