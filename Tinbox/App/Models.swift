//
//  Models.swift
//  Tinbox
//

import Foundation
import CoreGraphics

// MARK: - Library

struct Game: Identifiable, Codable, Equatable, Hashable {
    /// Stable identifier derived from the ROM file name (used for state/cheat folders).
    let id: String
    /// File name inside Documents/ROMs (e.g. "Astro Knights.gba").
    var fileName: String
    var title: String
    var fileSize: Int64
    var addedAt: Date
    var lastPlayed: Date?
    /// Name of the layout profile to use; nil == Default.
    var layoutProfile: String?
    /// Applied ROM patch file name inside Documents/Patches, if any.
    var patchFileName: String?
    /// Header info, filled in on first boot.
    var internalTitle: String?
    var gameCode: String?
    /// Deterministic hue for the generated cover.
    var coverHue: Double

    var romURL: URL { FileLocations.roms.appendingPathComponent(fileName) }

    static func makeID(fileName: String) -> String {
        let base = (fileName as NSString).deletingPathExtension
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let cleaned = base.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(cleaned).trimmingCharacters(in: .whitespaces)
    }

    static func prettyTitle(fromFileName fileName: String) -> String {
        var base = (fileName as NSString).deletingPathExtension
        // Strip common ROM tags: "(USA)", "[!]", "(Rev 1)" …
        base = base.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        base = base.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        base = base.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return base.trimmingCharacters(in: .whitespaces).capitalizedWords
    }
}

extension String {
    var capitalizedWords: String {
        split(separator: " ").map { word -> String in
            let w = String(word)
            if w.uppercased() == w && w.count <= 3 { return w } // keep "GP", "II"
            return w.prefix(1).uppercased() + w.dropFirst()
        }.joined(separator: " ")
    }
}

// MARK: - Save states

struct SaveSlot: Identifiable, Codable, Equatable {
    /// 0 == Auto, 1…4 == Slot 1…4
    let index: Int
    var savedAt: Date?

    var id: Int { index }
    var name: String { index == 0 ? "Auto" : "Slot \(index)" }
    var isFilled: Bool { savedAt != nil }

    static let count = 5
    static var empty: [SaveSlot] { (0..<count).map { SaveSlot(index: $0, savedAt: nil) } }
}

// MARK: - Cheats

enum CheatType: Int, CaseIterable, Codable, Identifiable {
    case gameShark = 2
    case actionReplay = 3
    case codeBreaker = 1

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .gameShark: return "GameShark"
        case .actionReplay: return "Action Replay"
        case .codeBreaker: return "CodeBreaker"
        }
    }
    var coreType: GBACheatCodeType {
        switch self {
        case .gameShark: return .gameShark
        case .actionReplay: return .actionReplay
        case .codeBreaker: return .codeBreaker
        }
    }
}

struct Cheat: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var code: String
    var type: CheatType
    var enabled: Bool
}

// MARK: - Controls layout

enum ControlID: String, CaseIterable, Codable, Identifiable {
    case dpad, a, b, l, r, select, start, menu, fastForward
    var id: String { rawValue }

    var label: String {
        switch self {
        case .dpad: return "D-pad"
        case .a: return "A"
        case .b: return "B"
        case .l: return "L"
        case .r: return "R"
        case .select: return "SELECT"
        case .start: return "START"
        case .menu: return "MENU"
        case .fastForward: return "»"
        }
    }
}

/// Position of one control. `center` is normalised (0…1) within the controls
/// area of the current orientation; `scale` multiplies the design size.
struct ControlPlacement: Codable, Equatable {
    var x: Double
    var y: Double
    var scale: Double = 1
}

struct ControlLayout: Codable, Equatable {
    var placements: [ControlID: ControlPlacement]

    subscript(id: ControlID) -> ControlPlacement {
        get { placements[id] ?? ControlLayout.portraitDefault.placements[id] ?? ControlPlacement(x: 0.5, y: 0.5) }
        set { placements[id] = newValue }
    }

    /// Matches the portrait design: L/R pills top corners, D-pad left / A-B
    /// cluster right, SELECT · MENU · START bottom row. Coordinates are relative
    /// to the controls region (below the screen band).
    static let portraitDefault = ControlLayout(placements: [
        .l:           ControlPlacement(x: 0.13, y: 0.08),
        .r:           ControlPlacement(x: 0.87, y: 0.08),
        .dpad:        ControlPlacement(x: 0.22, y: 0.50),
        .fastForward: ControlPlacement(x: 0.89, y: 0.27),
        .a:           ControlPlacement(x: 0.86, y: 0.47),
        .b:           ControlPlacement(x: 0.64, y: 0.62),
        .select:      ControlPlacement(x: 0.24, y: 0.93),
        .menu:        ControlPlacement(x: 0.50, y: 0.93),
        .start:       ControlPlacement(x: 0.76, y: 0.93),
    ])

    /// Landscape overlay (coordinates relative to the full screen).
    static let landscapeDefault = ControlLayout(placements: [
        .l:           ControlPlacement(x: 0.135, y: 0.095),
        .r:           ControlPlacement(x: 0.865, y: 0.095),
        .dpad:        ControlPlacement(x: 0.155, y: 0.67),
        .fastForward: ControlPlacement(x: 0.945, y: 0.24),
        .a:           ControlPlacement(x: 0.90, y: 0.55),
        .b:           ControlPlacement(x: 0.80, y: 0.72),
        .select:      ControlPlacement(x: 0.395, y: 0.92),
        .menu:        ControlPlacement(x: 0.50, y: 0.92),
        .start:       ControlPlacement(x: 0.605, y: 0.92),
    ])
}

struct LayoutProfile: Identifiable, Codable, Equatable {
    var id: String { name }
    var name: String
    var portrait: ControlLayout
    var landscape: ControlLayout

    static let defaultName = "Default"
    static let `default` = LayoutProfile(name: defaultName, portrait: .portraitDefault, landscape: .landscapeDefault)
}

// MARK: - RetroAchievements

struct Achievement: Identifiable, Codable, Equatable {
    let id: Int
    let title: String
    let description: String
    let points: Int
    var earned: Bool
    var badgeName: String?
}

struct RAUser: Codable, Equatable {
    var username: String
    var token: String
    var score: Int
}

// MARK: - Per-game persisted data

struct GameData: Codable, Equatable {
    var slots: [SaveSlot] = SaveSlot.empty
    var cheats: [Cheat] = []
}
