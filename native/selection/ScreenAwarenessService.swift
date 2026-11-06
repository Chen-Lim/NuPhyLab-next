// Adapted from apps/macos/Sources/Chord/Input/ScreenAwarenessService.swift.
// Standalone single-selection extraction; see source-provenance.json for changes and hashes.
import AppKit
import ApplicationServices
import Carbon

public enum IntentServiceError: Error {
    case accessibilityPermission, inputPermission, screenPermission, secureInput, inactiveSession
    case objectUnavailable, unsupportedObject, captureFailed, invalidRegion, regionTooLarge, monitorFailed, busy, releasePointer

    public func message(_ language: AppLanguage) -> String {
        let text: (String, String)
        switch self {
        case .accessibilityPermission: text = ("Allow Accessibility to select objects. Your normal input remains available.", "请授予辅助功能权限以选择对象。普通输入仍可使用。")
        case .inputPermission: text = ("Allow Input Monitoring to use the hold shortcut.", "请授予输入监控权限以使用按住快捷键。")
        case .screenPermission: text = ("Allow Screen Recording to capture the region you draw. Object text does not need it.", "请授予屏幕录制权限以捕获所画区域。对象文字不需要此权限。")
        case .secureInput: text = ("Selection stopped for secure input or a protected field.", "检测到安全输入或受保护字段，已停止选择。")
        case .inactiveSession: text = ("Selection stopped because the session or display changed.", "会话或显示器状态发生变化，已停止选择。")
        case .objectUnavailable: text = ("This app does not expose an object here. Drag a region instead.", "此应用未提供这里的对象信息，请改为拖动圈选区域。")
        case .unsupportedObject: text = ("No useful object content was available. Drag a smaller region instead.", "未获取到可用的对象内容，请改为拖动圈选较小区域。")
        case .captureFailed: text = ("The selected region could not be captured. Try again after checking permissions.", "未能捕获所选区域，请检查权限后重试。")
        case .invalidRegion: text = ("Select a region at least 8 × 8 points within one display.", "请在同一显示器内选择至少 8 × 8 点的区域。")
        case .regionTooLarge: text = ("Select a smaller region to keep the original image sharp.", "请缩小选取范围，以保留原图清晰度。")
        case .monitorFailed: text = ("The hold shortcut stopped. Resume monitoring to try again.", "按住快捷键监听已停止，请恢复监听后重试。")
        case .busy: text = ("Finish or cancel the current request, recording or capture before selecting again.", "请先完成或取消当前请求、录音或截图，再次选择。")
        case .releasePointer: text = ("Release the mouse buttons, then start selecting again.", "请松开鼠标按钮，再重新开始选择。")
        }
        return language == .zh ? text.1 : text.0
    }
}

public struct IntentRegionContext: Sendable {
    public var appName = ""
    public var bundleID: String?
    public var windowTitle: String?
}

/// AX requests run serially away from the event callback and never walk children.
/// Content is read only for the exact object explicitly clicked by the user.
public actor ScreenAwarenessService {
    public init() {}
    public func snapshot(at point: CGPoint, selectedAt: Date = Date()) throws -> IntentSelection {
        try assertAvailable()
        let element = try hitTest(point)
        try assertNotProtected(element)
        let role = string(element, kAXRoleAttribute)
        // A whole web area/window/container is not equivalent to a chosen semantic item.
        guard let role, ![kAXApplicationRole, kAXWindowRole, kAXScrollAreaRole, "AXWebArea"].contains(role) else { throw IntentServiceError.unsupportedObject }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { throw IntentServiceError.objectUnavailable }
        let name = firstNonempty([string(element, kAXTitleAttribute), string(element, kAXDescriptionAttribute), string(element, kAXLabelValueAttribute)])
        let textRoles = [kAXStaticTextRole, kAXTextFieldRole, kAXTextAreaRole, "AXLink", kAXCellRole]
        let text: String
        if role == kAXTextFieldRole || role == kAXTextAreaRole {
            // Text documents can expose enormous AXValue strings. Request at most
            // 20k characters from an explicit selection or the currently visible range.
            text = boundedTextRange(element)
        } else {
            let selected = string(element, kAXSelectedTextAttribute)
            let value = textRoles.contains(role) ? string(element, kAXValueAttribute) : nil
            text = IntentTextSafety.limited(firstNonempty([selected, value]))
        }
        guard !name.isEmpty || !text.isEmpty || [kAXButtonRole, kAXImageRole, "AXLink", kAXCheckBoxRole, kAXRadioButtonRole].contains(role) else { throw IntentServiceError.unsupportedObject }
        guard let bounds = bounds(element), bounds.isUsable else { throw IntentServiceError.unsupportedObject }
        let windowTitle = relatedElement(element, kAXWindowAttribute).flatMap { string($0, kAXTitleAttribute) }
        try assertAvailable()
        try assertNotProtected(element)
        return IntentSelection(kind: .accessibility, appName: app.localizedName ?? app.bundleIdentifier ?? "", bundleID: app.bundleIdentifier,
                               windowTitle: windowTitle.map { String($0.prefix(500)) }, role: role,
                               name: String(name.prefix(500)), text: text, bounds: bounds, selectedAt: selectedAt)
    }

    /// Region capture reads only protection metadata and the app/window at its center.
    /// No screenshots or OCR are produced by this service.
    public func regionContext(at point: CGPoint) throws -> IntentRegionContext {
        try assertAvailable()
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        if let focused = relatedElement(system, kAXFocusedUIElementAttribute) { try assertNotProtected(focused) }
        guard let element = try? hitTest(point) else { return IntentRegionContext() }
        try assertNotProtected(element)
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: pid) else { return IntentRegionContext() }
        let title = relatedElement(element, kAXWindowAttribute).flatMap { string($0, kAXTitleAttribute) }
        return IntentRegionContext(appName: app.localizedName ?? app.bundleIdentifier ?? "", bundleID: app.bundleIdentifier, windowTitle: title.map { String($0.prefix(500)) })
    }

    private func assertAvailable() throws {
        try Task.checkCancellation()
        guard !IsSecureEventInputEnabled() else { throw IntentServiceError.secureInput }
        guard AXIsProcessTrusted() else { throw IntentServiceError.accessibilityPermission }
    }
    private func hitTest(_ point: CGPoint) throws -> AXUIElement {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &found) == .success, let found else { throw IntentServiceError.objectUnavailable }
        AXUIElementSetMessagingTimeout(found, 0.15)
        var pid: pid_t = 0
        if AXUIElementGetPid(found, &pid) == .success, pid == ProcessInfo.processInfo.processIdentifier {
            // Release may already show the host's small thinking panel. Resolve only
            // the first real app window beneath it at the authorized gesture point.
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            for window in windows {
                guard let owner = window[kCGWindowOwnerPID as String] as? Int32,
                      owner != pid, (window[kCGWindowLayer as String] as? Int) == 0,
                      let rawBounds = window[kCGWindowBounds as String] as? NSDictionary,
                      let rectangle = CGRect(dictionaryRepresentation: rawBounds as CFDictionary), rectangle.contains(point),
                      (window[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
                let app = AXUIElementCreateApplication(owner)
                AXUIElementSetMessagingTimeout(app, 0.15)
                var underlying: AXUIElement?
                guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &underlying) == .success,
                      let underlying else { throw IntentServiceError.objectUnavailable }
                AXUIElementSetMessagingTimeout(underlying, 0.15)
                return underlying
            }
            throw IntentServiceError.objectUnavailable
        }
        return found
    }
    private func assertNotProtected(_ element: AXUIElement) throws {
        var current: AXUIElement? = element
        for _ in 0..<12 {
            try assertAvailable()
            guard let item = current else { break }
            let role = string(item, kAXRoleAttribute)
            if IntentTextSafety.isProtected(role: role, subrole: string(item, kAXSubroleAttribute)) { throw IntentServiceError.secureInput }
            if role == kAXWindowRole || role == kAXApplicationRole { break }
            current = relatedElement(item, kAXParentAttribute)
        }
    }
    private func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
    }
    private func string(_ element: AXUIElement, _ key: String) -> String? {
        guard let raw = value(element, key) else { return nil }
        if let string = raw as? String { return IntentTextSafety.limited(string) }
        if let attributed = raw as? NSAttributedString { return IntentTextSafety.limited(attributed.string) }
        return nil
    }
    private func relatedElement(_ element: AXUIElement, _ key: String) -> AXUIElement? {
        guard let raw = value(element, key), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(raw, to: AXUIElement.self)
    }
    private func boundedTextRange(_ element: AXUIElement) -> String {
        var ranges: [CFRange] = []
        for attribute in [kAXSelectedTextRangeAttribute, kAXVisibleCharacterRangeAttribute] {
            guard let raw = value(element, attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { continue }
            var range = CFRange(location: 0, length: 0)
            if AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cfRange, &range), range.location >= 0, range.length > 0 {
                range.length = min(range.length, IntentTextSafety.maximumTextLength)
                ranges.append(range)
            }
        }
        for var range in ranges {
            guard let parameter = AXValueCreate(.cfRange, &range) else { continue }
            var result: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &result) == .success,
               let string = result as? String, !string.isEmpty { return IntentTextSafety.limited(string) }
        }
        // Unsupported range APIs get an honest region fallback, never whole-document value.
        return ""
    }
    private func bounds(_ element: AXUIElement) -> IntentBounds? {
        guard let rawPosition = value(element, kAXPositionAttribute), let rawSize = value(element, kAXSizeAttribute),
              CFGetTypeID(rawPosition) == AXValueGetTypeID(), CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(rawPosition, to: AXValue.self), .cgPoint, &position),
              AXValueGetValue(unsafeBitCast(rawSize, to: AXValue.self), .cgSize, &size) else { return nil }
        return IntentBounds(x: position.x, y: position.y, width: size.width, height: size.height)
    }
    private func firstNonempty(_ candidates: [String?]) -> String { candidates.compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? "" }
}
