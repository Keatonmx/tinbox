//
//  SettingsSheetMain.swift
//  Tinbox
//
//  The Settings sheet. Three tiers: everyday sections open by default
//  (Playback · Video · Controls · Appearance); Library (files), Connections
//  (accounts & services) and Advanced (one-time choices) collapsed by default.
//  Per-game overrides live in a sub-sheet so the page never doubles in height.
//

import SwiftUI

struct SettingsSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: EmulatorSession
    @Environment(\.theme) private var theme

    private var settings: Binding<AppSettings> { $model.settings }
    private var inGame: Bool { model.screen == .game }

    enum Section: String, CaseIterable {
        case thisGame = "This game"
        case playback = "Playback"
        case video = "Video"
        case controls = "Controls"
        case appearance = "Appearance"
        case library = "Library"
        case connections = "Connections"
        case advanced = "Advanced"
        case about = "About"
    }

    var body: some View {
        BottomSheet(maxHeightFraction: 0.84, onDismiss: { model.closeSheet() }) {
            SheetHeader(title: "Settings") {
                SecondaryPill(title: "Done") { model.closeSheet() }
            }
            HuggingScrollView {
                VStack(spacing: 0) {
                    if inGame { thisGame }
                    section(.playback) { playback }
                    section(.video) { video }
                    section(.controls) { controls }
                    section(.appearance) { appearance }
                    section(.library) { library }
                    section(.connections) { connections }
                    section(.advanced) { advanced }
                    section(.about) { about }
                }
            }
        }
    }

    private func section<Content: View>(_ s: Section, @ViewBuilder content: () -> Content) -> some View {
        CollapsibleSection(title: s.rawValue,
                           collapsed: model.isSectionCollapsed(s.rawValue),
                           onToggle: { model.toggleSectionCollapsed(s.rawValue) }) {
            content()
        }
    }

    // MARK: This game — one row; details in GameOverridesSheet

    private var thisGame: some View {
        Card(bottomSpacing: 14) {
            NavRow(title: model.currentGame?.title ?? "This game",
                   subtitle: model.gameData.overrides.enabled ? overrideSummary : "Uses the settings below",
                   detail: model.gameData.overrides.enabled ? "Custom" : nil,
                   showsSeparator: false) {
                model.openSheet(.gameOverrides)
            }
        }
        .padding(.top, 4)
    }

    private var overrideSummary: String {
        let o = model.gameData.overrides
        var parts: [String] = []
        if let v = o.scaling { parts.append(v.rawValue) }
        if let v = o.landscapeScaling { parts.append("Landscape \(v.rawValue)") }
        if let v = o.filter { parts.append(v.rawValue) }
        if o.turboA == true || o.turboB == true { parts.append("Turbo") }
        if let v = o.controlOpacity { parts.append("\(Int((v * 100).rounded()))% buttons") }
        return parts.isEmpty ? "Custom settings on · nothing changed yet" : parts.joined(separator: " · ")
    }

    // MARK: Appearance

    private var appearance: some View {
        Card(bottomSpacing: 8) {
            NavRow(title: "Theme", subtitle: model.settings.theme.tagline, detail: model.settings.theme.rawValue) {
                model.openSheet(.themes)
            }
            NavRow(title: "Controller skin", detail: model.settings.skin.rawValue, showsSeparator: false) {
                model.openSheet(.skins)
            }
        }
    }

    // MARK: Playback

    private var playback: some View {
        Card(bottomSpacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Fast-forward speed").font(Typography.row).foregroundColor(.white)
                    Spacer()
                    Text(SpeedSteps.label(model.settings.ffSpeed)).font(Typography.detail).foregroundColor(Palette.text40)
                }
                SpeedChips(current: model.settings.ffSpeed) { model.setSpeed($0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            RowSeparator()
            SettingsRow(title: "Rewind", subtitle: model.settings.rewindEnabled ? "History length" : "Rewind 10 s in the Quick Menu",
                        showsSeparator: false, gap: 10) {
                HStack(spacing: 10) {
                    if model.settings.rewindEnabled {
                        SegmentedPill(options: RewindLength.options, label: { "\($0) s" }, selection: settings.rewindSeconds,
                                      fontSize: 12, horizontalPadding: 9)
                    }
                    TinboxToggle(isOn: settings.rewindEnabled)
                }
            }
        }
    }

    // MARK: Video

    private var video: some View {
        Card(bottomSpacing: 8) {
            SettingsRow(title: "Portrait screen") {
                SegmentedPill(options: DisplayScaling.portraitOptions, label: { $0.rawValue }, selection: settings.scaling,
                              fontSize: 12, horizontalPadding: 9)
            }
            SettingsRow(title: "Landscape screen", subtitle: landscapeSubtitle) {
                SegmentedPill(options: DisplayScaling.landscapeOptions, label: { $0.rawValue }, selection: settings.landscapeScaling)
            }
            SettingsRow(title: "Screen filter", showsSeparator: false) {
                SegmentedPill(options: ScreenFilter.options, label: { $0.rawValue }, selection: settings.filter, fontSize: 12, horizontalPadding: 10)
            }
        }
    }

    private var landscapeSubtitle: String {
        switch model.settings.landscapeScaling {
        case .fit: return "True proportions"
        case .wide: return "Slightly stretched, smaller bars"
        default: return "Fills the screen, stretched"
        }
    }

    // MARK: Controls

    private var controls: some View {
        Card(bottomSpacing: 8) {
            NavRow(title: "Edit button layout", subtitle: inGame ? "Drag to move · pinch to resize" : "Open a game first") {
                guard inGame else { model.showToast("Open a game first"); return }
                model.activeSheet = nil
                model.isLayoutEditing = true
            }
            NavRow(title: "Layout profiles", detail: model.currentGame?.layoutProfile ?? LayoutProfile.defaultName) {
                model.openSheet(.layoutProfiles)
            }
            SettingsRow(title: "Extra buttons", subtitle: "The » speed scrubber and a rotate button", gap: 14) {
                HStack(spacing: 14) {
                    HStack(spacing: 6) {
                        Text("»").font(Typography.segment).foregroundColor(Palette.textSecondary)
                        TinboxToggle(isOn: settings.showFastForwardButton)
                    }
                    HStack(spacing: 6) {
                        RotateGlyph(primary: Palette.textSecondary, secondary: Palette.textSecondary)
                        TinboxToggle(isOn: settings.showRotateButton)
                    }
                }
            }
            NavRow(title: "Bluetooth controller", detail: session.controllerConnected ? ControllerManager.shared.controllerName : "None") {
                model.openSheet(.controllers)
            }
            SettingsRow(title: "Turbo A / B", gap: 14) {
                HStack(spacing: 14) {
                    HStack(spacing: 6) {
                        Text("A").font(Typography.segment).foregroundColor(Palette.textSecondary)
                        TinboxToggle(isOn: settings.turboA)
                    }
                    HStack(spacing: 6) {
                        Text("B").font(Typography.segment).foregroundColor(Palette.textSecondary)
                        TinboxToggle(isOn: settings.turboB)
                    }
                }
            }
            SettingsRow(title: "Press glow", subtitle: "How buttons light up when touched") {
                SegmentedPill(options: PressGlow.allCases, label: { $0.rawValue }, selection: settings.pressGlow)
            }
            SettingsRow(title: "Button opacity", subtitle: "Landscape · \(Int((model.settings.controlOpacity * 100).rounded()))%") {
                Slider(value: settings.controlOpacity, in: 0.3...1.0, step: 0.05).tint(theme.accent).frame(width: 150)
            }
            SettingsRow(title: "Motion & rumble cartridges", subtitle: "Tilt, solar and rumble games use the phone's sensors") {
                TinboxToggle(isOn: settings.sensorsEnabled)
            }
            SettingsRow(title: "Button haptics", subtitle: "A light tap from the on-screen controls (game rumble is the row above)", showsSeparator: false) {
                TinboxToggle(isOn: settings.hapticsEnabled)
            }
        }
    }

    // MARK: Library (files)

    private var library: some View {
        Card(bottomSpacing: 8) {
            NavRow(title: "ROM folder", subtitle: "Shown in the Files app", detail: ROMFolderAccess.shared.displayName) {
                model.openSheet(.romFolder)
            }
            SettingsRow(title: "Box art", subtitle: "Downloads covers for games without one") {
                TinboxToggle(isOn: settings.fetchBoxArt)
            }
            NavRow(title: "Back up saves & states", subtitle: "Deleting the app deletes its saves — keep a copy") {
                model.exportBackup()
            }
            NavRow(title: "Restore a backup…", showsSeparator: false) {
                model.importKind = .backup
            }
        }
    }

    // MARK: Connections (accounts & services)

    // Cloud saves (iCloud / Google Drive) are implemented in CloudSync.swift
    // and belong in this section once the app has the entitlements they need.
    private var connections: some View {
        Card(bottomSpacing: 8) {
            NavRow(title: "RetroAchievements",
                   subtitle: RetroAchievementsService.shared.user == nil ? "Sign in to see your progress" : "Viewing progress · unlocking comes later",
                   detail: RetroAchievementsService.shared.userChipText,
                   showsSeparator: false) {
                model.openSheet(.retroAchievements)
            }
        }
    }

    // MARK: Advanced (one-time choices)

    private var advanced: some View {
        Card(bottomSpacing: 8) {
            SettingsRow(title: "Volume", subtitle: "\(model.settings.volume)%") {
                Slider(value: Binding(get: { Double(model.settings.volume) }, set: { model.settings.volume = Int($0.rounded()) }),
                       in: 0...100, step: 5).tint(theme.accent).frame(width: 150)
            }
            SettingsRow(title: "Keep my music playing", subtitle: "Game sound mixes over Music, Spotify, etc.") {
                TinboxToggle(isOn: settings.backgroundAudioMixing)
            }
            SettingsRow(title: "GBA BIOS", subtitle: bootSubtitle, showsSeparator: true) {
                SegmentedPill(options: BootMode.allCases, label: { $0 == .hle ? "Built-in" : "My file" },
                              selection: Binding(get: { model.settings.bootMode }, set: { pickBoot($0) }))
            }
            if hasBIOSFile {
                NavRow(title: "Replace BIOS file…", subtitle: model.settings.biosFileName ?? "gba_bios.bin", showsChevron: false) {
                    model.importKind = .bios
                }
                NavRow(title: "Remove BIOS file", titleColor: Palette.destructive, showsChevron: false) {
                    model.removeBIOSFile()
                }
            }
            SettingsRow(title: "Time Capsule", subtitle: model.settings.timeCapsuleEnabled ? "Automatic snapshots while you play" : "No automatic snapshots · capture manually in game", showsSeparator: false, gap: 10) {
                HStack(spacing: 10) {
                    if model.settings.timeCapsuleEnabled {
                        SegmentedPill(options: CapsuleInterval.options, label: { "\($0) m" }, selection: settings.timeCapsuleMinutes,
                                      fontSize: 12, horizontalPadding: 9)
                    }
                    TinboxToggle(isOn: settings.timeCapsuleEnabled)
                }
            }
        }
    }

    // MARK: About (very bottom)

    private var about: some View {
        Card(bottomSpacing: 0) {
            NavRow(title: "About Tinbox", subtitle: "Version, licences, privacy", detail: "Tinbox \(AppInfo.versionString)", showsSeparator: false) {
                model.openSheet(.about)
            }
        }
    }

    private var hasBIOSFile: Bool {
        let name = model.settings.biosFileName ?? "gba_bios.bin"
        return FileManager.default.fileExists(atPath: FileLocations.bios.appendingPathComponent(name).path)
    }

    private var bootSubtitle: String {
        if model.settings.bootMode == .biosFile, model.settings.biosFileName != nil {
            return "Using your file · applies next time a game starts"
        }
        if hasBIOSFile { return "Built-in (your file is kept for when you switch)" }
        return "Built-in works for almost every game"
    }

    private func pickBoot(_ mode: BootMode) {
        switch mode {
        case .hle:
            model.settings.bootMode = .hle
        case .biosFile:
            let existing = FileLocations.bios.appendingPathComponent(model.settings.biosFileName ?? "gba_bios.bin")
            if FileManager.default.fileExists(atPath: existing.path) {
                model.settings.biosFileName = existing.lastPathComponent
                model.settings.bootMode = .biosFile
            } else {
                model.importKind = .bios
            }
        }
    }
}

// MARK: - Per-game overrides sub-sheet

struct GameOverridesSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        BottomSheet(maxHeightFraction: 0.84, onDismiss: { model.openSheet(.settings) }) {
            SheetHeader(title: model.currentGame?.title ?? "This game", onBack: { model.openSheet(.settings) }) { EmptyView() }
            HuggingScrollView {
                VStack(spacing: 0) {
                    Card {
                        SettingsRow(title: "Custom settings for this game",
                                    subtitle: "Overrides the global settings only while this game is open",
                                    showsSeparator: false) {
                            TinboxToggle(isOn: Binding(get: { model.gameData.overrides.enabled },
                                                       set: { v in model.updateOverrides { $0.enabled = v } }))
                        }
                    }
                    if model.gameData.overrides.enabled {
                        Card(bottomSpacing: 12) {
                            SettingsRow(title: "Portrait screen") {
                                SegmentedPill(options: DisplayScaling.portraitOptions, label: { $0.rawValue },
                                              selection: Binding(get: { model.effective.scaling }, set: { v in model.updateOverrides { $0.scaling = v } }),
                                              fontSize: 12, horizontalPadding: 9)
                            }
                            SettingsRow(title: "Landscape screen") {
                                SegmentedPill(options: DisplayScaling.landscapeOptions, label: { $0.rawValue },
                                              selection: Binding(get: { model.effective.landscapeScaling }, set: { v in model.updateOverrides { $0.landscapeScaling = v } }))
                            }
                            SettingsRow(title: "Screen filter") {
                                SegmentedPill(options: ScreenFilter.options, label: { $0.rawValue },
                                              selection: Binding(get: { model.effective.filter }, set: { v in model.updateOverrides { $0.filter = v } }),
                                              fontSize: 12, horizontalPadding: 9)
                            }
                            SettingsRow(title: "Turbo A / B", gap: 14) {
                                HStack(spacing: 14) {
                                    HStack(spacing: 6) {
                                        Text("A").font(Typography.segment).foregroundColor(Palette.textSecondary)
                                        TinboxToggle(isOn: Binding(get: { model.effective.turboA }, set: { v in model.updateOverrides { $0.turboA = v } }))
                                    }
                                    HStack(spacing: 6) {
                                        Text("B").font(Typography.segment).foregroundColor(Palette.textSecondary)
                                        TinboxToggle(isOn: Binding(get: { model.effective.turboB }, set: { v in model.updateOverrides { $0.turboB = v } }))
                                    }
                                }
                            }
                            SettingsRow(title: "Button opacity", subtitle: "Landscape · \(Int((model.effective.controlOpacity * 100).rounded()))%", showsSeparator: false) {
                                Slider(value: Binding(get: { model.effective.controlOpacity }, set: { v in model.updateOverrides { $0.controlOpacity = v } }),
                                       in: 0.3...1.0, step: 0.05).tint(theme.accent).frame(width: 150)
                            }
                        }
                        Button {
                            ButtonHaptics.shared.tap()
                            model.updateOverrides { $0 = GameOverrides() }
                            model.showToast("Back to global settings")
                        } label: {
                            Text("Reset to global settings")
                                .font(Typography.rowSemibold)
                                .foregroundColor(Palette.destructive)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 54)
                                .background(theme.card)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(ExitPressStyle())
                    }
                }
            }
        }
    }
}
