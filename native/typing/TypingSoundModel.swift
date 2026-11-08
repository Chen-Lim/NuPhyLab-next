import Foundation
import CoreFoundation

enum TypingKeyGroup: String, Codable, CaseIterable {
    case regular, space, enter, backspace, shiftLeft, shiftRight, tab, caps
    static func key(_ code: Int) -> Self? {
        switch code {
        case 49: return .space
        case 36, 76: return .enter
        case 51, 117: return .backspace
        case 48: return .tab
        case 56: return .shiftLeft
        case 60: return .shiftRight
        case 57: return .caps
        case 0...47, 50, 65, 67, 69, 71, 75, 78, 81...89, 91...95, 102, 104, 123...126: return .regular
        default: return nil // No function/media/Command/Option/Control key sounds.
        }
    }
}

struct TypingPressState {
    private(set) var held = Set<Int>()
    mutating func down(_ code: Int, repeated: Bool) -> TypingKeyGroup? {
        guard !repeated, let group = TypingKeyGroup.key(code), held.insert(code).inserted else { return nil }
        return group
    }
    mutating func up(_ code: Int) -> TypingKeyGroup? {
        guard held.remove(code) != nil else { return nil }; return TypingKeyGroup.key(code)
    }
    mutating func clear() { held.removeAll() }
}

struct TypingSoundPreferences: Codable, Equatable {
    var enabled = false
    var pack = "mahjong-crisp"
    var volume = 50.0
    var muted = false
    var release = 70.0
    var variation = true
    var gains = Dictionary(uniqueKeysWithValues: TypingKeyGroup.allCases.filter { $0 != .regular }.map { ($0.rawValue, 100.0) })
    var favorites: [String] = []
    var dictionary: [String:Any] { (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(self))) as? [String:Any] ?? [:] }
    func patch(_ patch: [String:Any], ids: Set<String>) throws -> Self {
        guard Set(patch.keys).isSubset(of: Set(dictionary.keys)) else { throw TypingSoundError.invalidSettings }
        var data = dictionary
        for (key, value) in patch {
            if ["volume", "release"].contains(key) {
                guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite,
                      (0...100).contains(n.doubleValue) else { throw TypingSoundError.invalidSettings }
            }
            if ["enabled", "muted", "variation"].contains(key) {
                guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { throw TypingSoundError.invalidSettings }
            }
            if key == "gains" {
                guard let g = value as? [String:Any], Set(g.keys).isSubset(of: Set(gains.keys)) else { throw TypingSoundError.invalidSettings }
                var merged = gains
                for (k, v) in g {
                    guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite,
                          (0...150).contains(n.doubleValue) else { throw TypingSoundError.invalidSettings }
                    merged[k] = n.doubleValue
                }
                data[key] = merged; continue
            }
            data[key] = value
        }
        let result = try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: data))
        guard ids.contains(result.pack), result.favorites.count <= ids.count,
              Set(result.favorites).count == result.favorites.count, Set(result.favorites).isSubset(of: ids) else { throw TypingSoundError.invalidSettings }
        return result
    }
    var masterGain: Float { muted ? 0 : Float(pow(volume / 100, 1.7) * 0.65) }
    func gain(group: TypingKeyGroup, release: Bool) -> Float {
        Float((group == .regular ? 1 : (gains[group.rawValue] ?? 100) / 100) * (release ? self.release / 100 : 1))
    }
}
enum TypingSoundError: Error { case invalidSettings, invalidCatalog, audio, unavailable, recording }

struct TypingSoundPack: Decodable {
    var id: String
    var designed: Bool?
    var variants: [Int]
    var samples: [String:[String:[String]]]?
    func paths(_ group: TypingKeyGroup, release: Bool) -> [String] {
        let phase = release ? "release" : "press"
        if let samples { return samples[group.rawValue]?[phase] ?? [] }
        let stem: String
        switch group {
        case .space: stem = "SPACE"
        case .enter: stem = "ENTER"
        case .backspace, .shiftLeft, .shiftRight: stem = "BACKSPACE"
        default: stem = "GENERIC"
        }
        if stem == "GENERIC", !release { return variants.map { "press/GENERIC_R\($0).mp3" } }
        return ["\(phase)/\(stem).mp3"]
    }
}
struct TypingSoundCatalog: Decodable {
    var packs: [TypingSoundPack]
    var assets: [String]
    func validate() throws {
        guard packs.count == 18, Set(packs.map(\.id)).count == packs.count, Set(assets).count == assets.count else { throw TypingSoundError.invalidCatalog }
        let allowed = Set(assets)
        for p in packs {
            guard p.id.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil else { throw TypingSoundError.invalidCatalog }
            for g in TypingKeyGroup.allCases { for release in [false, true] {
                let paths = p.paths(g, release: release)
                guard !paths.isEmpty, paths.allSatisfy({ !$0.contains("..") && !$0.hasPrefix("/") && allowed.contains("audio/\(p.id)/\($0)") }) else { throw TypingSoundError.invalidCatalog }
            } }
        }
    }
}

enum TypingDictationCompletion {
    static func confirmed(_ result: [String:Any]?) -> Bool {
        result?["released"] as? Bool == true && ["idle","finishing"].contains(result?["observedState"] as? String ?? "unknown")
    }
}
