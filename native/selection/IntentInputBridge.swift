// Adapted from apps/macos/Sources/ChordCore/IntentInputBridge.swift.
// Standalone single-selection extraction; see source-provenance.json for changes and hashes.
import Foundation

public struct IntentPressToken: Equatable, Sendable {
    public let id: UInt64
    public let generation: UInt64
}
/// Quartz global points (primary display top-left), never a pointer history.
public struct IntentInputPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public var isFinite: Bool { x.isFinite && y.isFinite }
}
public enum IntentPressEdge: Equatable, Sendable { case began, moved, released, cancelled }
public enum IntentEscapeTarget: Equatable, Sendable { case press(IntentPressToken), selection(UInt64) }
public struct IntentPressEvent: Equatable, Sendable {
    public let token: IntentPressToken
    public let source: IntentInputSource
    public let edge: IntentPressEdge
    public let point: IntentInputPoint?
}
public struct IntentBridgeStep {
    public let consumes: Bool
    public let decision: BindingDecision
    public let event: IntentPressEvent?
}

/// One pending main-queue update per press. Release discards it and carries the
/// final point itself, so a late movement can never move a completed rectangle.
public struct IntentPointerMoveBuffer {
    private var pending: IntentPressEvent?
    private var scheduled: IntentPressToken?
    public init() {}
    public mutating func offer(_ event: IntentPressEvent) -> Bool {
        guard event.edge == .moved else { return false }
        pending = event
        guard scheduled != event.token else { return false }
        scheduled = event.token; return true
    }
    public mutating func take(_ token: IntentPressToken) -> IntentPressEvent? {
        guard scheduled == token, pending?.token == token else { return nil }
        defer { pending = nil; scheduled = nil }
        return pending
    }
    public mutating func discard(_ token: IntentPressToken) {
        if pending?.token == token { pending = nil; scheduled = nil }
    }
    public mutating func reset() { pending = nil; scheduled = nil }
}

/// Production tap-to-controller bridge. Finishing an old press never interrupts
/// a newer physical owner or invalidates its already-queued begin event.
public struct IntentInputBridge {
    public private(set) var runtime = InputBindingRuntimeState()
    public private(set) var generation: UInt64 = 0
    public private(set) var activePress: IntentPressToken?
    private var nextID: UInt64 = 0
    private var minimumBeginID: UInt64 = 0
    private var lastPointerPoint: IntentInputPoint?
    private var activeSource: IntentInputSource = .keyboard
    public init() {}
    public mutating func primeModifiers(_ modifiers: InputModifiers, binding: InputBinding) { runtime.primeModifiers(modifiers, binding: binding) }
    public func accepts(_ event: IntentPressEvent) -> Bool {
        event.token.generation == generation && (event.edge != .began || event.token.id >= minimumBeginID)
    }
    public mutating func finish(_ token: IntentPressToken) {
        guard token.generation == generation else { return }
        if activePress == token { runtime.finishLogicalHold(); activePress = nil; lastPointerPoint = nil }
    }
    /// Escape belongs to the press observed in the tap, not whichever session
    /// exists when Main eventually receives it. A later press remains deliverable.
    public mutating func cancelPress(_ token: IntentPressToken) {
        guard token.generation == generation else { return }
        minimumBeginID = max(minimumBeginID, token.id &+ 1)
        finish(token)
    }
    public mutating func escapeTarget(observedPress: IntentPressToken?, selectionGeneration: UInt64?) -> IntentEscapeTarget? {
        if let token = activePress ?? observedPress, token.generation == generation {
            cancelPress(token)
            return .press(token)
        }
        return selectionGeneration.map(IntentEscapeTarget.selection)
    }
    /// Explicit cancellation discards queued logical events, but a known physical
    /// release remains known. Suspension/configuration may require a fresh edge.
    public mutating func invalidate(preservingRelease: Bool = true) {
        generation &+= 1; activePress = nil; lastPointerPoint = nil
        if preservingRelease { runtime.finishLogicalHold() } else { runtime.interrupt() }
    }
    public mutating func resetAfterFailure() { generation &+= 1; activePress = nil; lastPointerPoint = nil; runtime.resetAfterFailure() }
    @discardableResult public mutating func observePhysicalState(isPressed: Bool, at time: TimeInterval) -> Bool {
        runtime.observePhysicalState(isPressed: isPressed, at: time)
    }
    public mutating func flagsChanged(keyCode: UInt16, modifiers: InputModifiers, binding: InputBinding, allowed: Bool,
                                     point: IntentInputPoint? = nil) -> IntentBridgeStep {
        let step = runtime.flagsChanged(keyCode: keyCode, modifiers: modifiers, binding: binding, allowed: allowed)
        return transition(step, source: binding.source, point: point)
    }
    public mutating func handle(input: BoundInput, edge: BoundInputEdge, isRepeat: Bool = false,
                                modifiers: InputModifiers, binding: InputBinding, allowed: Bool,
                                point: IntentInputPoint? = nil) -> IntentBridgeStep {
        let step = runtime.handle(input: input, edge: edge, isRepeat: isRepeat, modifiers: modifiers, binding: binding, allowed: allowed)
        let transitioned = transition(step, source: binding.source, point: point)
        if edge == .dragged, step.decision == .consume, allowed, let event = movement(point) {
            return .init(consumes: step.consumes, decision: step.decision, event: event)
        }
        return transitioned
    }
    public mutating func movement(_ point: IntentInputPoint?) -> IntentPressEvent? {
        guard let token = activePress, runtime.pair.logicalActive, case .mouse? = runtime.pair.owner,
              let point, point.isFinite else { return nil }
        lastPointerPoint = point
        return .init(token: token, source: .mouse, edge: .moved, point: point)
    }
    /// The native mouseMoved adapter uses this even when unavailable. Seeing an
    /// unsafe interval latches cancellation immediately; restoring permission
    /// before the timer/up cannot revive the old hold.
    public mutating func pointerMoved(_ point: IntentInputPoint?, allowed: Bool) -> IntentBridgeStep {
        if !allowed, activePress != nil {
            runtime.finishLogicalHold()
            return transition(.init(decision: .cancel), source: activeSource, point: nil)
        }
        return .init(consumes: false, decision: .pass, event: allowed ? movement(point) : nil)
    }
    private mutating func transition(_ step: InputRuntimeStep, source: IntentInputSource, point: IntentInputPoint?) -> IntentBridgeStep {
        let event: IntentPressEvent?
        switch step.decision {
        case .begin:
            nextID &+= 1
            let token = IntentPressToken(id: nextID, generation: generation); activePress = token
            activeSource = source; lastPointerPoint = source == .mouse ? point : nil
            event = .init(token: token, source: source, edge: .began, point: point)
        case .release, .cancel:
            if let token = activePress {
                if step.decision == .cancel { minimumBeginID = token.id &+ 1 }
                let finalPoint = step.decision == .release ? (point ?? lastPointerPoint) : nil
                event = .init(token: token, source: source, edge: step.decision == .release ? .released : .cancelled, point: finalPoint)
            } else { event = nil }
            activePress = nil; lastPointerPoint = nil
        default: event = nil
        }
        return .init(consumes: step.consumes, decision: step.decision, event: event)
    }
}

public enum IntentSideSelection: Equatable { case object(IntentInputPoint), region(IntentBounds) }
/// Side-button geometry is independent of overlay-owned left/right pairs.
public struct IntentSideSelectionState {
    public private(set) var token: IntentPressToken?
    public private(set) var origin: IntentInputPoint?
    public private(set) var current: IntentInputPoint?
    private var screen: IntentBounds?
    public init() {}
    public mutating func begin(_ token: IntentPressToken, at point: IntentInputPoint, screen: IntentBounds) {
        guard point.isFinite, screen.isUsable else { return }
        self.token = token; origin = point; current = point; self.screen = screen
    }
    public mutating func move(_ point: IntentInputPoint, token: IntentPressToken) {
        guard self.token == token, point.isFinite else { return }; current = point
    }
    public var bounds: IntentBounds? {
        guard let origin, let current, let screen else { return nil }
        return IntentBounds.drag(fromX: origin.x, fromY: origin.y, toX: current.x, toY: current.y, within: screen)
    }
    /// The preview and commit must agree on when a hold becomes a selection.
    /// Pointer jitter below this distance must not become an accidental rectangle.
    public var isRegionSelection: Bool {
        guard let origin, let current else { return false }
        return hypot(current.x - origin.x, current.y - origin.y) >= 6 && bounds != nil
    }
    public mutating func finish(_ token: IntentPressToken, at point: IntentInputPoint? = nil) -> IntentSideSelection? {
        guard self.token == token, let origin else { return nil }
        if let point { move(point, token: token) }
        defer { cancel() }
        guard current != nil else { return nil }
        return isRegionSelection ? bounds.map(IntentSideSelection.region) : .object(origin)
    }
    public mutating func cancel() { token = nil; origin = nil; current = nil; screen = nil }
}
