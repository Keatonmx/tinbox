//
//  Theme.swift
//  Tinbox
//
//  Semantic colour tokens resolved from the active theme. Values are the
//  THEMES object from the design prototype (GBA Player.dc.html), verbatim.
//

import SwiftUI

enum ThemeName: String, CaseIterable, Codable, Identifiable {
    case modern = "Modern"
    case outpost = "Outpost"
    var id: String { rawValue }
}

struct ThemeTokens: Equatable {
    let name: ThemeName

    /// Primary accent (`#8C7BF4` / `#C97B4A`).
    let accent: Color
    /// Accent text on dark surfaces.
    let accentText: Color
    /// Landscape / compact-dialog accent text variant.
    let accentText2: Color
    /// Accent tint fills.
    let tint: Color
    let tint2: Color
    let tint3: Color
    let tintBorder: Color
    let tintBorder2: Color
    /// FF badge background.
    let badge: Color
    /// Placeholder stripes.
    let stripe: Color
    let stripe2: Color

    let bg: Color
    let sheet: Color
    let card: Color
    let well: Color
    let chip: Color
    /// Secondary button.
    let secondaryButton: Color
    /// Toggle track when off.
    let trackOff: Color

    static let modern = ThemeTokens(
        name: .modern,
        accent: Color(hex: 0x8C7BF4),
        accentText: Color(hex: 0xA99BFF),
        accentText2: Color(hex: 0xB5A9FF),
        tint: Color(rgba: 140, 123, 244, 0.16),
        tint2: Color(rgba: 140, 123, 244, 0.22),
        tint3: Color(rgba: 140, 123, 244, 0.12),
        tintBorder: Color(rgba: 140, 123, 244, 0.5),
        tintBorder2: Color(rgba: 140, 123, 244, 0.55),
        badge: Color(rgba: 140, 123, 244, 0.9),
        stripe: Color(rgba: 140, 123, 244, 0.07),
        stripe2: Color(rgba: 140, 123, 244, 0.1),
        bg: Color(hex: 0x0E0E11),
        sheet: Color(hex: 0x1B1B1F),
        card: Color(hex: 0x26262B),
        well: Color(hex: 0x131317),
        chip: Color(hex: 0x1C1C1E),
        secondaryButton: Color(hex: 0x39393D),
        trackOff: Color(hex: 0x39393D)
    )

    static let outpost = ThemeTokens(
        name: .outpost,
        accent: Color(hex: 0xC97B4A),
        accentText: Color(hex: 0xE0A277),
        accentText2: Color(hex: 0xE8B08A),
        tint: Color(rgba: 201, 123, 74, 0.16),
        tint2: Color(rgba: 201, 123, 74, 0.22),
        tint3: Color(rgba: 201, 123, 74, 0.14),
        tintBorder: Color(rgba: 201, 123, 74, 0.5),
        tintBorder2: Color(rgba: 201, 123, 74, 0.55),
        badge: Color(rgba: 178, 104, 58, 0.92),
        stripe: Color(rgba: 201, 123, 74, 0.09),
        stripe2: Color(rgba: 201, 123, 74, 0.12),
        bg: Color(hex: 0x14100B),
        sheet: Color(hex: 0x1E1812),
        card: Color(hex: 0x282017),
        well: Color(hex: 0x17120D),
        chip: Color(hex: 0x211A13),
        secondaryButton: Color(hex: 0x3E342A),
        trackOff: Color(hex: 0x3E342A)
    )

    static func tokens(for name: ThemeName) -> ThemeTokens {
        switch name {
        case .modern: return .modern
        case .outpost: return .outpost
        }
    }
}

/// Colours shared by both themes.
enum Palette {
    static let destructive = Color(hex: 0xFF6961)
    static let textPrimary = Color.white
    static let textSecondary = Color(rgba: 235, 235, 245, 0.6)
    static let textTertiary = Color(rgba: 235, 235, 245, 0.45)
    static let textQuaternary = Color(rgba: 235, 235, 245, 0.3)
    static let text40 = Color(rgba: 235, 235, 245, 0.4)
    static let text55 = Color(rgba: 235, 235, 245, 0.55)
    static let text70 = Color(rgba: 235, 235, 245, 0.7)
    static let text75 = Color(rgba: 235, 235, 245, 0.75)
    static let text80 = Color(rgba: 235, 235, 245, 0.8)
    static let text85 = Color(rgba: 235, 235, 245, 0.85)
    static let separator = Color(rgba: 84, 84, 88, 0.5)
    static let separatorStrong = Color(rgba: 84, 84, 88, 0.65)
    static let hairline06 = Color.white.opacity(0.06)
    static let hairline07 = Color.white.opacity(0.07)
    static let hairline08 = Color.white.opacity(0.08)
    static let hairline10 = Color.white.opacity(0.10)
    static let hairline12 = Color.white.opacity(0.12)
    static let hairline14 = Color.white.opacity(0.14)
    static let backdrop = Color.black.opacity(0.55)
    static let toast = Color(rgba: 44, 44, 48, 0.95)
    static let grabber = Color(rgba: 235, 235, 245, 0.25)
    static let canvas = Color.black
    /// Physical button circle gradient (shared by themes; overridden by skins).
    static let buttonTop = Color(hex: 0x45454C)
    static let buttonBottom = Color(hex: 0x2C2C31)
    static let padTop = Color(hex: 0x3A3A40)
    static let padBottom = Color(hex: 0x26262B)
    static let shoulderTop = Color(hex: 0x3A3A40)
    static let shoulderBottom = Color(hex: 0x2A2A2F)
}

// MARK: - Controller skins

enum ControllerSkinName: String, CaseIterable, Codable, Identifiable {
    case modern = "Modern"
    case outpostWood = "Outpost Wood"
    case grapeClassic = "Grape Classic"
    var id: String { rawValue }
}

struct ControllerSkin: Equatable {
    let name: ControllerSkinName
    let description: String
    let buttonTop: Color
    let buttonBottom: Color
    let padTop: Color
    let padBottom: Color

    var buttonGradient: LinearGradient {
        LinearGradient(colors: [buttonTop, buttonBottom], startPoint: .top, endPoint: .bottom)
    }
    var padGradient: LinearGradient {
        LinearGradient(colors: [padTop, padBottom], startPoint: .top, endPoint: .bottom)
    }

    static let modern = ControllerSkin(
        name: .modern, description: "Neutral graphite",
        buttonTop: Color(hex: 0x45454C), buttonBottom: Color(hex: 0x2C2C31),
        padTop: Color(hex: 0x3A3A40), padBottom: Color(hex: 0x26262B))
    static let outpostWood = ControllerSkin(
        name: .outpostWood, description: "Warm walnut",
        buttonTop: Color(hex: 0x6B4F35), buttonBottom: Color(hex: 0x463222),
        padTop: Color(hex: 0x5C432E), padBottom: Color(hex: 0x3E2D1F))
    static let grapeClassic = ControllerSkin(
        name: .grapeClassic, description: "Purple handheld",
        buttonTop: Color(hex: 0x5C4E8C), buttonBottom: Color(hex: 0x3A3160),
        padTop: Color(hex: 0x4E4278), padBottom: Color(hex: 0x332B54))

    static let all: [ControllerSkin] = [.modern, .outpostWood, .grapeClassic]

    static func skin(named name: ControllerSkinName) -> ControllerSkin {
        all.first { $0.name == name } ?? .modern
    }
}

// MARK: - Environment

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: ThemeTokens = .modern
}

private struct SkinKey: EnvironmentKey {
    static let defaultValue: ControllerSkin = .modern
}

extension EnvironmentValues {
    var theme: ThemeTokens {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
    var skin: ControllerSkin {
        get { self[SkinKey.self] }
        set { self[SkinKey.self] = newValue }
    }
}

// MARK: - Color helpers

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    init(rgba r: Int, _ g: Int, _ b: Int, _ a: Double) {
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: a)
    }
}

// MARK: - Typography (SF Pro via system font)

enum Typography {
    static let largeTitle = Font.system(size: 34, weight: .bold)
    static let sheetTitle = Font.system(size: 20, weight: .bold)
    static let dialogTitle = Font.system(size: 17, weight: .bold)
    static let row = Font.system(size: 16, weight: .regular)
    static let rowSemibold = Font.system(size: 16, weight: .semibold)
    static let rowSubtitle = Font.system(size: 12, weight: .regular)
    static let cardTitle = Font.system(size: 15, weight: .semibold)
    static let meta = Font.system(size: 12, weight: .regular)
    static let meta13 = Font.system(size: 13, weight: .regular)
    static let detail = Font.system(size: 14, weight: .regular)
    static let detailSemibold = Font.system(size: 14, weight: .semibold)
    static let button = Font.system(size: 14, weight: .bold)
    static let buttonSemibold = Font.system(size: 14, weight: .semibold)
    static let eyebrow = Font.system(size: 12, weight: .semibold)
    static let sectionHeader = Font.system(size: 12, weight: .semibold)
    static let chip = Font.system(size: 12, weight: .bold)
    static let segment = Font.system(size: 13, weight: .bold)
    static let controlLabel = Font.system(size: 11, weight: .bold)
    static let controlLabelSmall = Font.system(size: 10, weight: .bold)
    static let badge = Font.system(size: 10, weight: .bold)
    static let mono12 = Font.system(size: 12, design: .monospaced)
    static let mono11 = Font.system(size: 11, design: .monospaced)
    static let mono10 = Font.system(size: 10, design: .monospaced)
    static let mono9 = Font.system(size: 9, design: .monospaced)
    static let mono8Bold = Font.system(size: 8, weight: .bold, design: .monospaced)
    static let mono14 = Font.system(size: 14, design: .monospaced)
}
