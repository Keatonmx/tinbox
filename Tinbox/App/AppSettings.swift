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

/// Speed steps shown on the slider, in order. Below 1× is slow motion.
enum SpeedSteps {
    static let all: [Double] = [0.25, 0.5, 1, 2, 3, 4, 8, 10, 16, 25, 50, 100]
    static let presets: [Double] = [0.25, 0.5, 2, 4, 10, 100]

    static func label(_ speed: Double) -> String {
        if speed == speed.rounded() {
            return "\(Int(speed))×"
        }
        return "\(speed)×"
    }

    static func index(of speed: Double) -> Int {
        all.firstIndex(of: speed) ?? all.enumerated().min { abs($0.element - speed) < abs($1.element - speed) }?.offset ?? 4
    }
}

struct AppSettings: Codable, Equatable {
    // Appearance
    var theme: ThemeName = .modern
    var skin: ControllerSkinName = .modern

    // Playback
    /// Speed used while fast-forward is engaged (0.25…100). 3× by default.
    var ffSpeed: Double = 3
    var showFFButton: Bool = true
    var rewindEnabled: Bool = true
    var rewindSeconds: Int = 30
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
    /// 0.30…1.00 — landscape overlay opacity.
    var controlOpacity: Double = 0.65
    var sensorsEnabled: Bool = true

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
    /// Settings sections the user has collapsed.
    var collapsedSections: [String] = []
    var hasSeenFastForwardHint: Bool = false

    init() {}

    // Tolerant decoding: fields added in later versions fall back to their
    // defaults instead of throwing the whole settings blob away.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        theme = try c.decodeIfPresent(ThemeName.self, forKey: .theme) ?? d.theme
        skin = try c.decodeIfPresent(ControllerSkinName.self, forKey: .skin) ?? d.skin
        ffSpeed = try c.decodeIfPresent(Double.self, forKey: .ffSpeed) ?? d.ffSpeed
        showFFButton = try c.decodeIfPresent(Bool.self, forKey: .showFFButton) ?? d.showFFButton
        rewindEnabled = try c.decodeIfPresent(Bool.self, forKey: .rewindEnabled) ?? d.rewindEnabled
        rewindSeconds = try c.decodeIfPresent(Int.self, forKey: .rewindSeconds) ?? d.rewindSeconds
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
        controlOpacity = try c.decodeIfPresent(Double.self, forKey: .controlOpacity) ?? d.controlOpacity
        sensorsEnabled = try c.decodeIfPresent(Bool.self, forKey: .sensorsEnabled) ?? d.sensorsEnabled
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
        collapsedSections = try c.decodeIfPresent([String].self, forKey: .collapsedSections) ?? d.collapsedSections
        hasSeenFastForwardHint = try c.decodeIfPresent(Bool.self, forKey: .hasSeenFastForwardHint) ?? d.hasSeenFastForwardHint
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
