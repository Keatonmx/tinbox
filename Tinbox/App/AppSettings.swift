//
//  AppSettings.swift
//  Tinbox
//
//  All user settings, persisted as one Codable blob in UserDefaults.
//

import Foundation

enum DisplayScaling: String, CaseIterable, Codable, Identifiable {
    case pixelPerfect = "Pixel-perfect"
    case fit = "Fit"
    /// Landscape only: fills the height and stretches just 10 % wider than 3:2.
    case wide = "Wide"
    case stretch = "Fill"
    var id: String { rawValue }

    static let portraitOptions: [DisplayScaling] = [.pixelPerfect, .fit, .stretch]
    static let landscapeOptions: [DisplayScaling] = [.fit, .wide, .stretch]
}

enum ImportMode: String, CaseIterable, Codable, Identifiable {
    case move = "Move"
    case copy = "Copy"
    var id: String { rawValue }
}

enum LibrarySort: String, CaseIterable, Codable, Identifiable {
    case recent = "Recent"
    case title = "A–Z"
    case size = "Size"
    var id: String { rawValue }
}

/// Rewind history lengths offered in Settings (seconds).
enum RewindLength {
    static let options = [30, 60, 120]
}

/// Time Capsule snapshot cadences offered in Settings (minutes of play).
enum CapsuleInterval {
    static let options = [2, 5, 10]
}

/// Game-clock (RTC) forward shifts offered in Settings, in seconds.
enum RTCOffset {
    static let options = [0, 21_600, 86_400, 259_200, 604_800]
    static func label(_ seconds: Int) -> String {
        switch seconds {
        case 0: return "Off"
        case 21_600: return "+6 h"
        case 86_400: return "+1 d"
        case 259_200: return "+3 d"
        default: return "+7 d"
        }
    }
}

enum ScreenFilter: String, CaseIterable, Codable, Identifiable {
    case none = "None"
    case crt = "CRT"
    case grid = "Grid"
    /// Legacy option (Scale2x); kept so old settings still decode.
    case hq2x = "HQ2x"
    /// Edge-directed upscaler (xBR-lv2).
    case xbr = "xBR"
    var id: String { rawValue }

    /// What the pickers offer.
    static let options: [ScreenFilter] = [.none, .crt, .grid, .xbr]

    /// Index passed to the Metal fragment shader.
    var shaderIndex: Int32 {
        switch self {
        case .none: return 0
        case .crt: return 1
        case .grid: return 2
        case .hq2x: return 3
        case .xbr: return 4
        }
    }
}

/// How a touched control lights up: a white wash, or the theme's accent colour.
enum PressGlow: String, CaseIterable, Codable, Identifiable {
    case white = "White"
    case accent = "Accent"
    var id: String { rawValue }
}

enum BootMode: String, CaseIterable, Codable, Identifiable {
    case hle = "HLE"
    case biosFile = "BIOS file"
    var id: String { rawValue }
}

enum CloudProvider: String, CaseIterable, Codable, Identifiable {
    case off = "Off"
    case iCloud = "iCloud"
    case googleDrive = "Google Drive"
    var id: String { rawValue }
}

/// Fast-forward presets (chips in Settings and the Quick Menu). 0.5× is slow
/// motion; 100× is "as fast as the phone can go".
enum SpeedSteps {
    static let presets: [Double] = [0.5, 2, 3, 4, 10, 100]

    static func label(_ speed: Double) -> String {
        if speed >= 100 { return "Max" }
        if speed == speed.rounded() {
            return "\(Int(speed))×"
        }
        return "\(speed)×"
    }
}

struct AppSettings: Codable, Equatable {
    // Appearance (fresh installs boot in the icon's own look)
    var theme: ThemeName = .tin
    var skin: ControllerSkinName = .surplus

    // Playback
    /// Speed used while fast-forward is engaged (0.25…100). 3× by default.
    var ffSpeed: Double = 3
    /// Extra on-screen buttons, both off by default (new keys so the old
    /// always-on » setting doesn't carry over). Fast-forward is still in the
    /// Quick Menu; rotation follows the phone unless its orientation lock is on.
    var showFastForwardButton: Bool = false
    var showRotateButton: Bool = false
    var rewindEnabled: Bool = true
    var rewindSeconds: Int = 30
    /// Time Capsule: automatic playthrough snapshots while you play.
    var timeCapsuleEnabled: Bool = true
    var timeCapsuleMinutes: Int = 5
    /// The cartridge-insert + lid-open flourish when a game boots.
    var bootAnimationEnabled: Bool = true
    /// Seconds added to the in-game real-time clock (berry farming etc.).
    var rtcOffsetSeconds: Int = 0
    /// Bluetooth pad bindings: physical element id to GBA action id.
    /// Missing keys fall back to ControllerManager.defaultBindings.
    var controllerBindings: [String: String] = [:]
    var autoSuspendSave: Bool = true
    var backgroundAudioMixing: Bool = false

    // Video
    var scaling: DisplayScaling = .pixelPerfect
    /// Landscape: Fit keeps the real 3:2 proportions; Wide/Fill stretch.
    var landscapeScaling: DisplayScaling = .fit
    /// 0…100 output volume.
    var volume: Int = 100
    var filter: ScreenFilter = .none
    var bootMode: BootMode = .hle
    /// File name inside Documents/BIOS (normally "gba_bios.bin").
    var biosFileName: String?

    // Controls
    var turboA: Bool = false
    var turboB: Bool = false
    var hapticsEnabled: Bool = true
    var pressGlow: PressGlow = .accent
    /// 0.30…1.00 — landscape overlay opacity.
    var controlOpacity: Double = 0.65
    var sensorsEnabled: Bool = true
    /// Solar games: the sun level follows the screen brightness (which tracks
    /// the ambient light sensor when iOS auto-brightness is on).
    var autoSunEnabled: Bool = false

    // Sync & extras
    var cloudProvider: CloudProvider = .off
    var lastCloudSync: Date?
    var raHardcore: Bool = false

    // General
    /// Always on — leaving a game writes the Auto slot. Kept for compatibility.
    var autosaveOnExit: Bool = true
    /// Importing a ROM moves it into the library folder (or copies it).
    var importMode: ImportMode = .move
    /// Security-scoped bookmark of a user-chosen ROM folder (nil == Tinbox › ROMs).
    var customROMFolderBookmark: Data?
    var customROMFolderName: String?
    /// External-folder games removed from the Library (the folder is rescanned).
    var hiddenGameIDs: [String] = []
    /// Download box art from libretro-thumbnails for games without a cover.
    var fetchBoxArt: Bool = true
    /// Library sort order.
    var librarySort: LibrarySort = .recent

    // Not user-facing: remembered state
    var lastPlayedGameID: String?
    /// Settings sections whose open/closed state the user flipped from the
    /// default (Library and Advanced start collapsed, the rest open).
    var toggledSections: [String] = []
    var hasSeenFastForwardHint: Bool = false
    /// One-time toast when the very first Time Capsule snapshot is captured.
    var hasSeenCapsuleHint: Bool = false
    /// The explainer card shows on the sheet's first open (then via the ? button).
    var hasSeenCapsuleIntro: Bool = false

    init() {}

    // Tolerant decoding: fields added in later versions fall back to their
    // defaults instead of throwing the whole settings blob away.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        theme = try c.decodeIfPresent(ThemeName.self, forKey: .theme) ?? d.theme
        skin = try c.decodeIfPresent(ControllerSkinName.self, forKey: .skin) ?? d.skin
        ffSpeed = try c.decodeIfPresent(Double.self, forKey: .ffSpeed) ?? d.ffSpeed
        showFastForwardButton = try c.decodeIfPresent(Bool.self, forKey: .showFastForwardButton) ?? d.showFastForwardButton
        showRotateButton = try c.decodeIfPresent(Bool.self, forKey: .showRotateButton) ?? d.showRotateButton
        rewindEnabled = try c.decodeIfPresent(Bool.self, forKey: .rewindEnabled) ?? d.rewindEnabled
        rewindSeconds = try c.decodeIfPresent(Int.self, forKey: .rewindSeconds) ?? d.rewindSeconds
        timeCapsuleEnabled = try c.decodeIfPresent(Bool.self, forKey: .timeCapsuleEnabled) ?? d.timeCapsuleEnabled
        timeCapsuleMinutes = try c.decodeIfPresent(Int.self, forKey: .timeCapsuleMinutes) ?? d.timeCapsuleMinutes
        bootAnimationEnabled = try c.decodeIfPresent(Bool.self, forKey: .bootAnimationEnabled) ?? d.bootAnimationEnabled
        rtcOffsetSeconds = try c.decodeIfPresent(Int.self, forKey: .rtcOffsetSeconds) ?? d.rtcOffsetSeconds
        controllerBindings = try c.decodeIfPresent([String: String].self, forKey: .controllerBindings) ?? d.controllerBindings
        autoSuspendSave = true
        backgroundAudioMixing = try c.decodeIfPresent(Bool.self, forKey: .backgroundAudioMixing) ?? d.backgroundAudioMixing
        scaling = try c.decodeIfPresent(DisplayScaling.self, forKey: .scaling) ?? d.scaling
        landscapeScaling = try c.decodeIfPresent(DisplayScaling.self, forKey: .landscapeScaling) ?? d.landscapeScaling
        filter = try c.decodeIfPresent(ScreenFilter.self, forKey: .filter) ?? d.filter
        bootMode = try c.decodeIfPresent(BootMode.self, forKey: .bootMode) ?? d.bootMode
        biosFileName = try c.decodeIfPresent(String.self, forKey: .biosFileName)
        turboA = try c.decodeIfPresent(Bool.self, forKey: .turboA) ?? d.turboA
        turboB = try c.decodeIfPresent(Bool.self, forKey: .turboB) ?? d.turboB
        hapticsEnabled = try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? d.hapticsEnabled
        pressGlow = try c.decodeIfPresent(PressGlow.self, forKey: .pressGlow) ?? d.pressGlow
        controlOpacity = try c.decodeIfPresent(Double.self, forKey: .controlOpacity) ?? d.controlOpacity
        sensorsEnabled = try c.decodeIfPresent(Bool.self, forKey: .sensorsEnabled) ?? d.sensorsEnabled
        autoSunEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoSunEnabled) ?? d.autoSunEnabled
        cloudProvider = try c.decodeIfPresent(CloudProvider.self, forKey: .cloudProvider) ?? d.cloudProvider
        lastCloudSync = try c.decodeIfPresent(Date.self, forKey: .lastCloudSync)
        raHardcore = try c.decodeIfPresent(Bool.self, forKey: .raHardcore) ?? d.raHardcore
        autosaveOnExit = true
        importMode = try c.decodeIfPresent(ImportMode.self, forKey: .importMode) ?? d.importMode
        customROMFolderBookmark = try c.decodeIfPresent(Data.self, forKey: .customROMFolderBookmark)
        customROMFolderName = try c.decodeIfPresent(String.self, forKey: .customROMFolderName)
        hiddenGameIDs = try c.decodeIfPresent([String].self, forKey: .hiddenGameIDs) ?? []
        fetchBoxArt = try c.decodeIfPresent(Bool.self, forKey: .fetchBoxArt) ?? d.fetchBoxArt
        librarySort = try c.decodeIfPresent(LibrarySort.self, forKey: .librarySort) ?? d.librarySort
        volume = try c.decodeIfPresent(Int.self, forKey: .volume) ?? d.volume
        lastPlayedGameID = try c.decodeIfPresent(String.self, forKey: .lastPlayedGameID)
        toggledSections = try c.decodeIfPresent([String].self, forKey: .toggledSections) ?? d.toggledSections
        hasSeenFastForwardHint = try c.decodeIfPresent(Bool.self, forKey: .hasSeenFastForwardHint) ?? d.hasSeenFastForwardHint
        hasSeenCapsuleHint = try c.decodeIfPresent(Bool.self, forKey: .hasSeenCapsuleHint) ?? d.hasSeenCapsuleHint
        hasSeenCapsuleIntro = try c.decodeIfPresent(Bool.self, forKey: .hasSeenCapsuleIntro) ?? d.hasSeenCapsuleIntro
    }
}

final class SettingsStore {
    static let shared = SettingsStore()
    private let key = "tinbox.settings.v1"
    private let defaults = UserDefaults.standard

    func load() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    func save(_ settings: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }

    // Layout profiles live next to settings (small, user-editable).
    private let profilesKey = "tinbox.layoutProfiles.v2"   // v2: new landscape default positions

    func loadProfiles() -> [LayoutProfile] {
        guard let data = defaults.data(forKey: profilesKey),
              let profiles = try? JSONDecoder().decode([LayoutProfile].self, from: data),
              !profiles.isEmpty else {
            return [.default]
        }
        return profiles.map { $0.sanitized() }
    }

    func saveProfiles(_ profiles: [LayoutProfile]) {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: profilesKey)
        }
    }
}
