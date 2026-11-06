import Foundation

public struct InputRuntimeStep: Equatable {
    public let consumes: Bool
    public let decision: BindingDecision
    public init(consumes: Bool = false, decision: BindingDecision = .pass) {
        self.consumes = consumes; self.decision = decision
    }
}

/// The production intent tap uses this reducer for modifier and physical pairs.
/// It stores only the configured input's ownership, never a typing history.
public struct InputBindingRuntimeState {
    public private(set) var pair = InputBindingPairState()
    private var modifierState = ModifierBindingState()
    private var modifierEvents = ModifierEventState()
    public init() {}

    public mutating func primeModifiers(_ modifiers: InputModifiers, binding: InputBinding) {
        modifierEvents.prime(modifiers)
        modifierState.interrupt()
        _ = modifierState.update(modifierEvents.normalized(modifiers), required: binding.modifiers, allowed: false)
    }
    public mutating func finishLogicalHold() {
        pair.cancelKeepingOwnership(); modifierState.finishLogicalHold()
    }
    public mutating func interrupt() {
        pair.cancelKeepingOwnership(); modifierState.interrupt(); modifierEvents.reset()
    }
    public mutating func resetAfterFailure() {
        pair.resetAfterFailure(); modifierState.interrupt(); modifierEvents.reset()
    }
    @discardableResult public mutating func observePhysicalState(isPressed: Bool, at time: TimeInterval) -> Bool {
        pair.observePhysicalState(isPressed: isPressed, at: time)
    }
    private mutating func suspend() -> BindingDecision {
        let wasActive = pair.logicalActive || modifierState.isActive
        finishLogicalHold()
        return wasActive ? .cancel : .pass
    }

    public mutating func flagsChanged(keyCode: UInt16, modifiers: InputModifiers,
                                      binding: InputBinding, allowed: Bool) -> InputRuntimeStep {
        if !allowed {
            let decision = suspend()
            // Every observed event latches suspension, including unsupported
            // flags keys. Only recognized modifier edges can update release/rearm.
            if let flags = modifierEvents.flagsChanged(keyCode: keyCode, modifiers: modifiers) {
                _ = modifierState.update(flags, required: binding.modifiers, allowed: false)
            }
            return .init(decision: decision)
        }
        guard let flags = modifierEvents.flagsChanged(keyCode: keyCode, modifiers: modifiers) else { return .init() }
        if binding.kind == .modifiers {
            return .init(decision: modifierState.update(flags, required: binding.modifiers, allowed: true))
        }
        return .init(decision: pair.modifiersChanged(flags))
    }

    public mutating func handle(input: BoundInput, edge: BoundInputEdge, isRepeat: Bool = false,
                                modifiers: InputModifiers, binding: InputBinding, allowed: Bool) -> InputRuntimeStep {
        let suspension = allowed ? BindingDecision.pass : suspend()
        if binding.kind == .modifiers, case .key = input, edge == .down, pair.owner != input {
            let cancel = modifierState.cancelForOtherInput()
            return .init(decision: suspension == .cancel ? .cancel : cancel)
        }
        let decision = pair.handle(input: input, edge: edge, isRepeat: isRepeat,
                                   modifiers: modifierEvents.normalized(modifiers), binding: binding, allowed: allowed)
        return .init(consumes: decision != .pass, decision: suspension == .cancel ? .cancel : decision)
    }
}
