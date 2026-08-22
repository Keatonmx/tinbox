//
//  SettingsSheet.swift
//  Tinbox
//
//  Appearance · Playback · Video · Controls · Sync & Extras · General.
//

import SwiftUI

struct SettingsSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: EmulatorSession
    @Environment(\.theme) private var theme

    private var settings: Binding<AppSettings> { $model.settings }
    private var inGame: Bool { model.screen == .game }

    var body: some View {
        BottomSheet(maxHeightFraction: 0.84, onDismiss: { model.closeSheet() }) {
            SheetHeader(title: "Settings") {
                SecondaryPill(title: "Done") { model.closeSheet() }
            }
            HuggingScrollView {
                VStack(spacing: 0) {
                    appearance
                    playback
                    video
                    controls
                    syncAndExtras
                    general
                }
                .padding(.horizontal, 0)
            }
        }
    }

    // MARK: Appearance

    private var appearance: some View {
        Group {
            SectionHeader(title: "Appearance")
            Card(bottomSpacing: 14) {
                SettingsRow(title: "Theme", subtitle: "Outpost is the Redfern's earth-tone look", showsSeparator: false) {
                    SegmentedPill(options: ThemeName.allCases, label: { $0.rawValue }, selection: settings.theme)
                }
            }
        }
    }

    // MARK: Playback

    private var playback: some View {
        Group {
            SectionHeader(title: "Playback")
            Card(bottomSpacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Speed presets · \(SpeedSteps.label(model.settings.ffSpeed))").font(Typography.row).foregroundColor(.white)
                    SpeedSlider(speed: model.settings.ffSpeed) { model.setSpeed($0) }
                    SpeedChips(current: model.settings.ffSpeed) { model.setSpeed($0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                RowSeparator()
                SettingsRow(title: "Show FF button in game") {
                    TinboxToggle(isOn: settings.showFFButton)
                }
                SettingsRow(title: "Rewind buffer", subtitle: "Keeps the last \(model.settings.rewindSeconds) s in memory") {
                    TinboxToggle(isOn: settings.rewindEnabled)
                }
                SettingsRow(title: "Auto-suspend save", subtitle: "Emergency state on calls or app switch") {
                    TinboxToggle(isOn: settings.autoSuspendSave)
                }
                SettingsRow(title: "Background audio mixing", subtitle: "Your music keeps playing over game SFX", showsSeparator: false) {
                    TinboxToggle(isOn: settings.backgroundAudioMixing)
                }
            }
        }
    }

    // MARK: Video

    private var video: some View {
        Group {
            SectionHeader(title: "Video")
            Card(bottomSpacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Display scaling").font(Typography.row).foregroundColor(.white)
                    SegmentedPill(options: DisplayScaling.allCases, label: { $0.rawValue }, selection: settings.scaling)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                RowSeparator()
                SettingsRow(title: "Screen filter") {
                    SegmentedPill(options: ScreenFilter.allCases, label: { $0.rawValue }, selection: settings.filter)
                }
                SettingsRow(title: "Boot", subtitle: bootSubtitle) {
                    SegmentedPill(options: BootMode.allCases, label: { $0.rawValue },
                                  selection: Binding(get: { model.settings.bootMode }, set: { pickBoot($0) }))
                }
                NavRow(title: "Controller skin", detail: model.settings.skin.rawValue, showsSeparator: false) {
                    model.openSheet(.skins)
                }
            }
        }
    }

    private var bootSubtitle: String {
        if model.settings.bootMode == .biosFile, let name = model.settings.biosFileName {
            return "Using \(name) · applies on next launch"
        }
        return "HLE needs no BIOS file"
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

    // MARK: Controls

    private var controls: some View {
        Group {
            SectionHeader(title: "Controls")
            Card(bottomSpacing: 14) {
                NavRow(title: "Edit button layout", subtitle: inGame ? "Move and resize on-screen controls" : "Open a game to edit its layout") {
                    guard inGame else { model.showToast("Open a game first"); return }
                    model.activeSheet = nil
                    model.isLayoutEditing = true
                }
                NavRow(title: "Bluetooth controller", detail: session.controllerConnected ? ControllerManager.shared.controllerName : "None connected") {
                    model.openSheet(.controllers)
                }
                SettingsRow(title: "Turbo buttons", subtitle: "Rapid-fire A / B", gap: 14) {
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
                SettingsRow(title: "Landscape overlay opacity", subtitle: "\(Int((model.settings.controlOpacity * 100).rounded()))%") {
                    Slider(value: settings.controlOpacity, in: 0.3...1.0, step: 0.05).tint(theme.accent).frame(width: 150)
                }
                NavRow(title: "Layout profiles", subtitle: "Per-game button setups (RPG, platformer…)",
                       detail: model.currentGame?.layoutProfile ?? LayoutProfile.defaultName, showsSeparator: false) {
                    model.openSheet(.layoutProfiles)
                }
            }
        }
    }

    // MARK: Sync & extras

    private var syncAndExtras: some View {
        Group {
            SectionHeader(title: "Sync & Extras")
            Card(bottomSpacing: 14) {
                SettingsRow(title: "Cloud saves") {
                    SegmentedPill(options: CloudProvider.allCases, label: { $0.rawValue }, selection: settings.cloudProvider,
                                  fontSize: 12, horizontalPadding: 10)
                }
                NavRow(title: "Sync now", detail: model.lastSyncText, titleColor: theme.accentText, showsChevron: false) {
                    model.syncNow()
                }
                NavRow(title: "RetroAchievements", detail: RetroAchievementsService.shared.userChipText) {
                    model.openSheet(.retroAchievements)
                }
                NavRow(title: "Apply ROM patch…", subtitle: patchSubtitle) {
                    guard inGame else { model.showToast("Open a game first"); return }
                    model.importKind = .patch
                }
                SettingsRow(title: "Sensor cartridges", subtitle: "Tilt, solar & rumble — auto-detected", showsSeparator: false) {
                    TinboxToggle(isOn: settings.sensorsEnabled)
                }
            }
        }
    }

    private var patchSubtitle: String {
        if let patch = model.currentGame?.patchFileName { return "Active: \(patch)" }
        return "IPS / UPS — fan translations & hacks"
    }

    // MARK: General

    private var general: some View {
        Group {
            SectionHeader(title: "General")
            Card(bottomSpacing: 0) {
                SettingsRow(title: "Haptics on buttons") {
                    TinboxToggle(isOn: settings.hapticsEnabled)
                }
                SettingsRow(title: "Battery saves", subtitle: "Native .sav files, backed up automatically") {
                    Text("On").font(Typography.detail).foregroundColor(Palette.text40)
                }
                SettingsRow(title: "Auto-save on exit", subtitle: "Writes a state to the Auto slot") {
                    TinboxToggle(isOn: settings.autosaveOnExit)
                }
                SettingsRow(title: "About", showsSeparator: false) {
                    Text("Tinbox 1.0 · Redfern's Outpost").font(Typography.detail).foregroundColor(Palette.text40)
                }
            }
        }
    }
}

// MARK: - Controller skins

struct SkinsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        BottomSheet(onDismiss: { model.openSheet(.settings) }) {
            SheetHeader(title: "Controller Skins", onBack: { model.openSheet(.settings) }, bottomSpacing: 14) { EmptyView() }
            HStack(alignment: .top, spacing: 12) {
                ForEach(ControllerSkin.all, id: \.name) { skin in
                    let selected = skin.name == model.settings.skin
                    Button {
                        ButtonHaptics.shared.tap()
                        model.settings.skin = skin.name
                        model.showToast("\(skin.name.rawValue) skin applied")
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack(alignment: .topTrailing) {
                                HStack {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 4).fill(skin.padGradient).frame(width: 12, height: 34)
                                        RoundedRectangle(cornerRadius: 4).fill(skin.padGradient).frame(width: 34, height: 12)
                                    }
                                    .frame(width: 34, height: 34)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 6) {
                                        Circle().fill(skin.buttonGradient).frame(width: 20, height: 20)
                                        Circle().fill(skin.buttonGradient).frame(width: 20, height: 20).padding(.trailing, 14)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 92)
                                .frame(maxWidth: .infinity)
                                .background(theme.well)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(selected ? theme.accent : Palette.hairline10, lineWidth: selected ? 2 : 0.5))
                                if selected {
                                    Circle().fill(theme.accent).frame(width: 18, height: 18)
                                        .overlay(Text("✓").font(.system(size: 11, weight: .heavy)).foregroundColor(.white))
                                        .padding(6)
                                }
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(skin.name.rawValue).font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                                Text(skin.description).font(.system(size: 11)).foregroundColor(Palette.textTertiary)
                            }
                        }
                    }
                    .buttonStyle(FadePressStyle(opacity: 0.75))
                }
            }
            .padding(.bottom, 12)
            Card(bottomSpacing: 0) {
                SettingsRow(title: "Skin marketplace", subtitle: "Community handheld-style skins", showsSeparator: false, gap: 8) {
                    Text("Coming soon")
                        .font(Typography.chip)
                        .foregroundColor(theme.accentText)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(theme.tint)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }
}

// MARK: - RetroAchievements

struct RetroAchievementsSheet: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var ra = RetroAchievementsService.shared
    @Environment(\.theme) private var theme

    var body: some View {
        BottomSheet(maxHeightFraction: 0.76, onDismiss: { model.openSheet(.settings) }) {
            SheetHeader(title: "RetroAchievements", onBack: { model.openSheet(.settings) }) {
                Button {
                    ButtonHaptics.shared.tap()
                    if ra.user == nil { model.openSheet(.raLogin) }
                } label: {
                    Text(ra.userChipText)
                        .font(Typography.chip)
                        .foregroundColor(theme.accentText)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(theme.tint)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(FadePressStyle())
            }
            Card {
                SettingsRow(title: "Hardcore mode", subtitle: "Disables save states & cheats for leaderboards", showsSeparator: false) {
                    TinboxToggle(isOn: Binding(get: { model.settings.raHardcore }, set: { model.setHardcore($0) }))
                }
            }
            if ra.user == nil {
                Card(bottomSpacing: 0) {
                    NavRow(title: "Sign in to RetroAchievements", subtitle: "Track unlocks across your games", titleColor: theme.accentText, showsSeparator: false) {
                        model.openSheet(.raLogin)
                    }
                }
            } else {
                SectionHeader(title: sectionTitle)
                HuggingScrollView {
                    VStack(spacing: 0) {
                        if ra.isBusy {
                            ProgressView().tint(theme.accent).frame(maxWidth: .infinity).frame(minHeight: 58)
                        } else if ra.achievements.isEmpty {
                            Text(ra.lastError ?? (model.currentGame == nil ? "Open a game to see its achievements" : "No achievements found"))
                                .font(Typography.detail).foregroundColor(Palette.text40)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity).frame(minHeight: 58).padding(.horizontal, 16)
                        }
                        ForEach(Array(ra.achievements.enumerated()), id: \.element.id) { index, a in
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(a.earned ? theme.accent : Color.white.opacity(0.08))
                                    .frame(width: 34, height: 34)
                                    .overlay(Text(a.earned ? "✓" : "").font(.system(size: 15, weight: .heavy)).foregroundColor(.white))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(a.title).font(Typography.cardTitle).foregroundColor(.white)
                                    Text(a.description).font(Typography.rowSubtitle).foregroundColor(Color(rgba: 235, 235, 245, 0.5))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(a.points) pts").font(.system(size: 13, weight: .bold)).foregroundColor(theme.accentText)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .frame(minHeight: 58)
                            .opacity(a.earned ? 1 : 0.4)
                            if index < ra.achievements.count - 1 { RowSeparator() }
                        }
                        NavRow(title: "Sign out", titleColor: Palette.destructive, showsSeparator: false, showsChevron: false) {
                            Task { await ra.logout() }
                        }
                    }
                    .background(theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .task(id: model.currentGame?.id) {
            if let game = model.currentGame, ra.user != nil {
                await ra.loadAchievements(for: game, hardcore: model.settings.raHardcore)
            }
        }
    }

    private var sectionTitle: String {
        let earned = ra.achievements.filter(\.earned).count
        let name = model.currentGame?.title ?? "No game open"
        return ra.achievements.isEmpty ? name : "\(name) · \(earned) of \(ra.achievements.count)"
    }
}

struct RALoginSheet: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var ra = RetroAchievementsService.shared
    @Environment(\.theme) private var theme
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        BottomSheet(onDismiss: { model.openSheet(.retroAchievements) }) {
            SheetHeader(title: "Sign in", onBack: { model.openSheet(.retroAchievements) }) { EmptyView() }
            VStack(spacing: 10) {
                TextField("", text: $username, prompt: Text("Username").foregroundColor(Palette.textQuaternary))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .modifier(WellField())
                SecureField("", text: $password, prompt: Text("Password").foregroundColor(Palette.textQuaternary))
                    .modifier(WellField())
                if let error = ra.lastError {
                    Text(error).font(Typography.meta).foregroundColor(Palette.destructive)
                }
                HStack {
                    Text("Your password is sent only to retroachievements.org; Tinbox stores the returned token.")
                        .font(Typography.meta).foregroundColor(Palette.textTertiary)
                    Spacer()
                    AccentPill(title: ra.isBusy ? "Signing in…" : "Sign in") {
                        Task {
                            await ra.login(username: username, password: password)
                            if ra.user != nil { model.openSheet(.retroAchievements) }
                        }
                    }
                    .disabled(ra.isBusy || username.isEmpty || password.isEmpty)
                }
            }
            .padding(16)
            .background(theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

struct WellField: ViewModifier {
    @Environment(\.theme) private var theme
    func body(content: Content) -> some View {
        content
            .font(.system(size: 15))
            .foregroundColor(.white)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(theme.well)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Palette.hairline10, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Layout profiles

struct LayoutProfilesSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @State private var newName = ""

    var body: some View {
        BottomSheet(maxHeightFraction: 0.72, onDismiss: { model.openSheet(.settings) }) {
            SheetHeader(title: "Layout Profiles", onBack: { model.openSheet(.settings) }) { EmptyView() }
            Text(model.currentGame.map { "Profile for \($0.title)" } ?? "Open a game to assign a profile")
                .font(Typography.meta13).foregroundColor(Palette.text40)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).padding(.bottom, 8)
            HuggingScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(model.profiles.enumerated()), id: \.element.id) { index, profile in
                        let active = profile.name == (model.currentGame?.layoutProfile ?? LayoutProfile.defaultName)
                        NavRow(title: profile.name, detail: active ? "Active" : nil,
                               showsSeparator: index < model.profiles.count - 1, showsChevron: !active) {
                            model.assignProfile(profile.name)
                        }
                        .contextMenu {
                            if profile.name != LayoutProfile.defaultName {
                                Button(role: .destructive) { model.deleteProfile(profile.name) } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                }
                .background(theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.bottom, 12)
                HStack(spacing: 10) {
                    TextField("", text: $newName, prompt: Text("New profile from current layout").foregroundColor(Palette.textQuaternary))
                        .modifier(WellField())
                    AccentPill(title: "Add") {
                        ButtonHaptics.shared.tap()
                        model.createProfile(named: newName)
                        newName = ""
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || model.currentGame == nil)
                }
            }
        }
    }
}

// MARK: - Controllers

struct ControllersSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: EmulatorSession
    @Environment(\.theme) private var theme

    var body: some View {
        BottomSheet(onDismiss: { model.openSheet(.settings) }) {
            SheetHeader(title: "Bluetooth Controller", onBack: { model.openSheet(.settings) }) {
                TintPill(title: "Scan") {
                    ControllerManager.shared.startDiscovery()
                    model.showToast("Scanning for controllers…")
                }
            }
            Card {
                SettingsRow(title: "Status", subtitle: session.controllerConnected ? "Touch controls hide while connected" : "Pair in iOS Settings › Bluetooth, then return here", showsSeparator: false) {
                    Text(session.controllerConnected ? ControllerManager.shared.controllerName : "None connected")
                        .font(Typography.detail).foregroundColor(session.controllerConnected ? theme.accentText : Palette.text40)
                }
            }
            Card(bottomSpacing: 0) {
                mappingRow("A / B", "A / B (X / Y mirror them)")
                mappingRow("L / R", "Shoulders or triggers")
                mappingRow("Start / Select", "Menu / Options")
                mappingRow("D-pad", "D-pad or left stick")
                SettingsRow(title: "Quick Menu", subtitle: "Home button (or hold Menu on MFi)", showsSeparator: false) { EmptyView() }
            }
        }
    }

    private func mappingRow(_ title: String, _ detail: String) -> some View {
        SettingsRow(title: title) {
            Text(detail).font(Typography.detail).foregroundColor(Palette.text40)
        }
    }
}
