import AppKit
import Carbon

// Adapted from the permission-free mouse-down / drag-pasteboard state approach
// in Swivel (Jonathan Lotan, MIT) and Kumquat (Ian Di Filippo, MIT).
// Their licence texts and pinned revisions are in assets/drag-convert-licenses.
final class DragFileWatcher {
    var trigger: () -> DragTrigger = { DragTrigger("shift")! }
    var canActivate: () -> Bool = { true }
    private func triggerDown() -> Bool {
        canActivate() && trigger().isPressed(flags:NSEvent.modifierFlags, keyDown:{CGEventSource.keyState(.hidSystemState,key:$0)})
    }
    var show: (() -> Bool)?
    var ended: (() -> Void)?
    var cancelled: (() -> Void)?
    var moved: ((NSPoint) -> Void)?
    private(set) var state = DragGestureState()
    private var monitors: [Any] = []
    private var timer: Timer?
    private let pasteboard = NSPasteboard(name: .drag)
    private var escapeWasDown = false
    private var downPoint = NSPoint.zero
    private var dragMoved = false
    var isRunning: Bool { !monitors.isEmpty }
    var isFileDragActive: Bool { state.phase == .dragging || state.phase == .visible }

    func start() {
        guard monitors.isEmpty else { return }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in self?.begin() }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] event in self?.begin(); return event }) { monitors.append(monitor) }
    }
    func stop() {
        monitors.forEach(NSEvent.removeMonitor); monitors.removeAll()
        timer?.invalidate(); timer = nil; state.reset(); cancelled?()
    }
    private func begin() {
        timer?.invalidate()
        downPoint = NSEvent.mouseLocation; dragMoved = false
        state.begin(change: pasteboard.changeCount, trigger: triggerDown())
        escapeWasDown = CGEventSource.keyState(.combinedSessionState, key: 53)
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.001
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    private func tick() {
        let escape = CGEventSource.keyState(.combinedSessionState, key: 53)
        if escape && !escapeWasDown { state.cancel(); cancelled?() }
        escapeWasDown = escape
        let point = NSEvent.mouseLocation
        if hypot(point.x - downPoint.x, point.y - downPoint.y) >= 6 { dragMoved = true }
        let effect = state.sample(button: NSEvent.pressedMouseButtons & 1 != 0,
                                  change: pasteboard.changeCount, hasFiles: pasteboard.types?.contains(.fileURL) == true,
                                  trigger: triggerDown(), now: ProcessInfo.processInfo.systemUptime, moved: dragMoved)
        switch effect {
        case .show: if show?() != true { state.retryPresentation() }
        case .end: ended?()
        case .none: break
        }
        if state.phase == .visible { moved?(NSEvent.mouseLocation) }
        if state.phase == .idle { timer?.invalidate(); timer = nil }
    }
    func ignoreCurrentDrag() { state.cancel(); cancelled?() }
}
