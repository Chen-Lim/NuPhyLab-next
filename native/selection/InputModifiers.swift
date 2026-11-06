// Adapted from apps/macos/Sources/ChordCore/InputMatching.swift.
// Standalone single-selection extraction; see source-provenance.json for changes and hashes.
import Foundation

public struct InputModifiers: OptionSet, Equatable, Hashable, Codable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let control = InputModifiers(rawValue: 1 << 0)
    public static let shift = InputModifiers(rawValue: 1 << 1)
    public static let option = InputModifiers(rawValue: 1 << 2)
    public static let command = InputModifiers(rawValue: 1 << 3)
    public static let function = InputModifiers(rawValue: 1 << 4)
}

