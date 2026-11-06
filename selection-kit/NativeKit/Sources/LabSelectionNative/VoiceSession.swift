import Foundation

public enum VoicePhase: String, Equatable { case idle, authorizing, recording, finishing, ready, unavailable }

/// A recording is bound to a snapshot of the objects the user was pointing at.
/// Generation checks prevent late recognition callbacks from reviving cancelled audio.
public struct VoiceSession: Equatable {
    public private(set) var phase: VoicePhase = .idle
    public private(set) var generation = UUID()
    public private(set) var objectIDs: [UUID] = []
    public private(set) var transcript = ""
    public init() {}
    public var isActive: Bool { [.authorizing, .recording, .finishing].contains(phase) }
    @discardableResult public mutating func begin(objectIDs: [UUID]) -> UUID {
        generation = UUID(); self.objectIDs = Array(objectIDs.prefix(2)); transcript = ""; phase = .authorizing
        return generation
    }
    @discardableResult public mutating func authorized(generation token: UUID) -> Bool {
        guard generation == token, phase == .authorizing else { return false }
        phase = .recording; return true
    }
    @discardableResult public mutating func update(_ value: String, generation token: UUID, final: Bool) -> Bool {
        guard generation == token, [.recording, .finishing].contains(phase) else { return false }
        transcript = String(value.prefix(16_000))
        if final { phase = .ready }
        return true
    }
    public mutating func stop() { if phase == .recording { phase = .finishing } }
    @discardableResult public mutating func bindObjects(_ IDs: [UUID], generation token: UUID) -> Bool {
        guard generation == token, [.recording, .finishing, .ready].contains(phase), IDs.count <= 2 else { return false }
        objectIDs = IDs; return true
    }
    public mutating func finish(generation token: UUID) {
        guard generation == token, phase == .finishing else { return }; phase = .ready
    }
    public mutating func unavailable(generation token: UUID) {
        guard generation == token else { return }; phase = .unavailable
    }
    public mutating func cancel() { generation = UUID(); phase = .idle; transcript = ""; objectIDs = [] }
}
