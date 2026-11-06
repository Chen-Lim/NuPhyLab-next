// Adapted from apps/macos/Sources/ChordCore/IntentModels.swift.
// Standalone single-selection extraction; see source-provenance.json for changes and hashes.
import Foundation

public enum AppLanguage: String, Sendable { case zh, en }
public enum IntentSelectionKind: String, Codable, Sendable { case accessibility, region }

public struct IntentBounds: Equatable, Codable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
    public var isUsable: Bool { [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0 }
    public var isCapturableRegion: Bool { isUsable && width >= 8 && height >= 8 }
    public func contained(in other: IntentBounds) -> Bool {
        isUsable && other.isUsable && x >= other.x && y >= other.y && x + width <= other.x + other.width && y + height <= other.y + other.height
    }
    public static func drag(fromX: Double, fromY: Double, toX: Double, toY: Double, within screen: IntentBounds) -> IntentBounds? {
        guard [fromX, fromY, toX, toY].allSatisfy(\.isFinite), screen.isUsable else { return nil }
        let left = max(screen.x, min(fromX, toX)), top = max(screen.y, min(fromY, toY))
        let right = min(screen.x + screen.width, max(fromX, toX)), bottom = min(screen.y + screen.height, max(fromY, toY))
        let result = IntentBounds(x: left, y: top, width: right - left, height: bottom - top)
        return result.isUsable ? result : nil
    }
}

public struct IntentSelection: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let kind: IntentSelectionKind
    public let appName: String
    public let bundleID: String?
    public let windowTitle: String?
    public let role: String?
    public let name: String
    public let text: String
    public let bounds: IntentBounds
    public let imagePNG: Data?
    public let selectedAt: Date
    public init(id: UUID = UUID(), kind: IntentSelectionKind, appName: String, bundleID: String? = nil, windowTitle: String? = nil, role: String? = nil, name: String, text: String, bounds: IntentBounds, imagePNG: Data? = nil, selectedAt: Date = Date()) {
        self.id = id; self.kind = kind; self.appName = appName; self.bundleID = bundleID
        self.windowTitle = windowTitle; self.role = role; self.name = name; self.text = text; self.bounds = bounds; self.imagePNG = imagePNG; self.selectedAt = selectedAt
    }
}

public enum IntentTextSafety {
    public static let maximumTextLength = 20_000
    public static func limited(_ text: String?) -> String { String((text ?? "").prefix(maximumTextLength)) }
    /// Refuse protected AX roles and the common secure text-input purpose metadata.
    public static func isProtected(role: String?, subrole: String?, inputType: String? = nil) -> Bool {
        subrole == "AXSecureTextField" || role == "AXSecureTextField" || inputType?.lowercased() == "password"
    }
}

