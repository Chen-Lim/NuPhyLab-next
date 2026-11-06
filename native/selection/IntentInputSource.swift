import Foundation

public enum IntentInputSource: String, Equatable, Sendable {
    case keyboard, mouse, onscreen

    public func title(language: AppLanguage) -> String {
        switch self {
        case .keyboard: return language == .zh ? "键盘" : "Keyboard"
        case .mouse: return language == .zh ? "鼠标" : "Mouse"
        case .onscreen: return language == .zh ? "屏幕操作" : "On-screen"
        }
    }
    public func selectionInstruction(language: AppLanguage) -> String {
        switch self {
        case .keyboard: return language == .zh ? "按住 AI 按键，用左键或触控板拖选，也可同时说话。" : "Hold the AI key, then click or drag with your mouse or trackpad. You can speak too."
        case .mouse: return language == .zh ? "按住侧键并移动鼠标框选，松开完成；也可同时说话。" : "Hold the side button and move to select a region. Release to finish; you can speak too."
        case .onscreen: return language == .zh ? "点击对象或按下拖动框选，松开后选择动作。" : "Click an object or drag a region, then release to choose an action."
        }
    }
    public func finishInstruction(language: AppLanguage, triggerLabel: String? = nil) -> String {
        if self == .onscreen { return language == .zh ? "松开后选择动作" : "Release to choose an action" }
        let label = triggerLabel ?? (language == .zh ? (self == .mouse ? "侧键" : "AI 按键") : (self == .mouse ? "side button" : "AI key"))
        return language == .zh ? "松开 \(label) 完成" : "Release \(label) to finish"
    }
    public func hudInstruction(language: AppLanguage) -> String {
        switch self {
        case .keyboard: return language == .zh ? "左键或触控板拖选 · 可以同时说话" : "Click or drag with your mouse or trackpad"
        case .mouse: return language == .zh ? "按住侧键移动框选 · 松开完成" : "Hold side button and move; release to finish"
        case .onscreen: return language == .zh ? "点击或拖动框选 · 松开后选择动作" : "Click or drag a region; release to choose an action"
        }
    }
}

public extension InputBinding {
    var source: IntentInputSource {
        switch kind { case .disabled: return .onscreen; case .mouseButton: return .mouse; case .keyboard, .modifiers: return .keyboard }
    }
}
