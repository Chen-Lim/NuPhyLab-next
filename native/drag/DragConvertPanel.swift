import AppKit
import QuartzCore

/// User-approved sRGB palette, shared visually with the settings preview.
enum DragMenuPalette {
    private static func gray(_ value: Int) -> CGColor {
        let channel = CGFloat(value) / 255
        return NSColor(srgbRed: channel, green: channel, blue: channel, alpha: 1).cgColor
    }
    static let background = gray(0x14)
    static let idle = gray(0x29)
    static let selected = gray(0xe6)
    static let border = gray(0x63)
    static let idleBorder = gray(0x5a)
    static let selectedBorder = gray(0xff)
    static let text = gray(0xed)
    static let selectedText = gray(0x11)
    static let detail = gray(0xa0)
}

final class DragConvertPanel: NSPanel {
    let wheel: DragConvertWheelView
    var onDrop: ((DragFormat, [URL]) -> Bool)?
    var visibilityChanged: ((Bool) -> Void)?
    var isAwaitingDrop:Bool { wheel.hasActiveSession }
    private var hideWork: DispatchWorkItem?
    private(set) var lastPresentationMilliseconds: Double = 0
    private(set) var generation = 0
    init() {
        let rect = NSRect(x: 0, y: 0, width: DragWheelGeometry.side, height: DragWheelGeometry.side)
        wheel = DragConvertWheelView(frame: rect)
        super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        level = .popUpMenu; collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false; isReleasedWhenClosed = false; animationBehavior = .none
        contentView = wheel
        wheel.onDrop = { [weak self] format, urls in
            guard let self else { return false }
            let accepted=self.onDrop?(format, urls) ?? false
            self.hideImmediately()
            return accepted
        }
        wheel.onSessionEnd = { [weak self] in self?.hideImmediately() }
        // Allocate layers and text before the first real drag. No visible window.
        wheel.displayIfNeeded()
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    func present(at point: NSPoint, urls: [URL], english: Bool) {
        let start = CACurrentMediaTime()
        hideWork?.cancel(); hideWork = nil; generation += 1
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        guard let screen else { hideImmediately();return }
        let frame = DragWheelGeometry.frame(at: point, visible: screen.visibleFrame)
        wheel.configure(urls: urls, english: english)
        wheel.activationPoint = NSPoint(x: point.x - frame.minX, y: point.y - frame.minY)
        wheel.hasMovedFromActivation = false
        setFrame(frame, display: false)
        ignoresMouseEvents = false
        alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0.85
        orderFrontRegardless()
        visibilityChanged?(isVisible)
        // Fade only: geometry and all drop targets are correct from the first frame.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.075
            animator().alphaValue = 1
        }
        lastPresentationMilliseconds = (CACurrentMediaTime() - start) * 1000
    }
    func move(_ point: NSPoint) {
        guard isVisible else { return }
        wheel.trackPoint(NSPoint(x: point.x - frame.minX, y: point.y - frame.minY))
    }
    func released() {
        // The real drop callback can arrive after the mouse-up poll. This delay
        // only keeps the destination alive; it NEVER submits a conversion.
        let current = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == current else { return }; self.hideImmediately()
        }
        hideWork?.cancel(); hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
    }
    func hideImmediately() {
        hideWork?.cancel(); hideWork = nil; generation += 1
        ignoresMouseEvents = true; orderOut(nil); wheel.invalidateSession()
        visibilityChanged?(false)
    }
}

final class DragConvertWheelView: NSView {
    var onDrop: ((DragFormat, [URL]) -> Bool)?
    var onSessionEnd: (() -> Void)?
    var activationPoint = DragWheelGeometry.center
    var hasMovedFromActivation = false
    private var urls: [URL] = []
    private var actions: [DragFormat] = []
    private var english = false
    private var hover: Int?
    private var committed = false
    var hasActiveSession:Bool { !committed && !urls.isEmpty }
    private var paths: [CAShapeLayer] = []
    private var titleLayers: [CATextLayer] = []
    private let countLabel = CATextLayer()
    private let detailLabel = CATextLayer()
    private let centerDot = CAShapeLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = DragMenuPalette.background
        layer?.cornerRadius = LabNotchStyle.radius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.75; layer?.borderColor = DragMenuPalette.border
        for index in 0..<DragWheelGeometry.maximumSectors {
            let shape = CAShapeLayer(); shape.path = DragWheelGeometry.path(index, count: DragWheelGeometry.maximumSectors)
            shape.fillColor = DragMenuPalette.idle
            shape.strokeColor = DragMenuPalette.idleBorder; shape.lineWidth = 0.75
            layer?.addSublayer(shape); paths.append(shape)
            let label = textLayer(size: 14, weight: .medium)
            let point = DragWheelGeometry.labelPoint(index, count: DragWheelGeometry.maximumSectors)
            label.frame = CGRect(x: point.x - 49, y: point.y - 10, width: 98, height: 21)
            layer?.addSublayer(label); titleLayers.append(label)
        }
        let center = DragWheelGeometry.center
        countLabel.frame = CGRect(x: center.x - 29, y: center.y + 2, width: 58, height: 19)
        configureText(countLabel, size: 14, weight: .medium)
        detailLabel.frame = CGRect(x: center.x - 29, y: center.y - 16, width: 58, height: 15)
        configureText(detailLabel, size: 10, weight: .regular)
        detailLabel.foregroundColor = DragMenuPalette.detail
        layer?.addSublayer(countLabel); layer?.addSublayer(detailLabel)
        centerDot.path = CGPath(ellipseIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4), transform: nil)
        centerDot.fillColor = NSColor(white: 0.6, alpha: 1).cgColor
        // Text-only targets echo the selection HUD. The centre stays neutral.
        registerForDraggedTypes([.fileURL])
        setAccessibilityLabel("拖拽转换 / Drag Convert")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func configureText(_ label: CATextLayer, size: CGFloat, weight: NSFont.Weight) {
        label.font = NSFont.systemFont(ofSize: size, weight: weight); label.fontSize = size
        label.alignmentMode = .center; label.foregroundColor = DragMenuPalette.text
        label.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
    }
    private func textLayer(size: CGFloat, weight: NSFont.Weight) -> CATextLayer {
        let value = CATextLayer(); configureText(value, size: size, weight: weight); return value
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        ([countLabel, detailLabel] + titleLayers).forEach { $0.contentsScale = window?.backingScaleFactor ?? 2 }
    }
    func configure(urls: [URL], english: Bool) {
        self.urls = urls; self.english = english; committed = false; hover = nil
        actions = DragFileKind.actions(for: urls)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for index in 0..<DragWheelGeometry.maximumSectors {
            let visible = index < actions.count
            paths[index].isHidden = !visible; titleLayers[index].isHidden = !visible
            if visible {
                paths[index].path = DragWheelGeometry.path(index, count: actions.count)
                let point = DragWheelGeometry.labelPoint(index, count: actions.count)
                let width: CGFloat = actions.count >= 7 ? 68 : (actions.count >= 5 ? 76 : 98)
                let title = actions[index].title(english: english)
                let split = english && actions.count >= 9 && title.contains(" ")
                titleLayers[index].frame = CGRect(x: point.x - width / 2, y: point.y - (split ? 14 : 9), width: width, height: split ? 30 : 20)
                titleLayers[index].fontSize = actions.count >= 7 ? 11 : (actions.count >= 5 ? 12 : 14)
                titleLayers[index].string = split ? title.replacingOccurrences(of: " ", with: "\n") : title
            }
        }
        countLabel.string = String(urls.count); detailLabel.string = english ? "FILES" : "个文件"
        paths.forEach { $0.fillColor = DragMenuPalette.idle; $0.strokeColor = DragMenuPalette.idleBorder }
        titleLayers.forEach { $0.foregroundColor = DragMenuPalette.text }
        CATransaction.commit()
    }
    func invalidateSession() { urls = []; committed = true; hover = nil }
    func trackPoint(_ point: NSPoint) {
        if hypot(point.x - activationPoint.x, point.y - activationPoint.y) >= 7 { hasMovedFromActivation = true }
        // Near a display edge the menu is clamped, so the initial cursor could
        // be on a sector. Require a small intentional move before it can select.
        let next = hasMovedFromActivation ? DragWheelGeometry.hit(point, count: actions.count) : nil
        guard next != hover else { return }; hover = next
        CATransaction.begin()
        CATransaction.setAnimationDuration(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.065)
        for index in 0..<actions.count {
            paths[index].fillColor = index == next ? DragMenuPalette.selected : DragMenuPalette.idle
            paths[index].strokeColor = index == next ? DragMenuPalette.selectedBorder : DragMenuPalette.idleBorder
            titleLayers[index].foregroundColor = index == next ? DragMenuPalette.selectedText : DragMenuPalette.text
        }
        CATransaction.commit()
    }
    private func safeOperation(_ mask: NSDragOperation) -> NSDragOperation {
        for operation in [NSDragOperation.copy, .generic, .link] where mask.contains(operation) { return operation }
        return [] // Never return move/delete: sources must retain the originals.
    }
    private func track(_ sender: NSDraggingInfo) -> NSDragOperation {
        trackPoint(convert(sender.draggingLocation, from: nil))
        return hover != nil && !committed && !urls.isEmpty ? safeOperation(sender.draggingSourceOperationMask) : []
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { track(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { track(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { trackPoint(NSPoint(x: -100, y: -100)) }
    override func wantsPeriodicDraggingUpdates() -> Bool { true }
    override func draggingEnded(_ sender: NSDraggingInfo) { onSessionEnd?() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !track(sender).isEmpty }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard !track(sender).isEmpty, let index = hover, !committed,
              let actual = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              actual.map(\.standardizedFileURL) == urls.map(\.standardizedFileURL), DragFileKind.actions(for: actual) == actions, actions.indices.contains(index) else { return false }
        committed = true
        return onDrop?(actions[index], actual) ?? false
    }
}
