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

    private enum Section: String, CaseIterable {
        case appearance = "Appearance"
        case playback = "Playback"
        case video = "Video"
        case controls = "Controls"
        case sync = "Sync & Extras"
        case general = "General"
    }

    var body: some View {
        BottomSheet(maxHeightFraction: 0.84, onDismiss: { model.closeSheet() }) {
            SheetHeader(title: "Settings") {
                SecondaryPill(title: "Done") { model.closeSheet() }
            }
            HuggingScrollView {
                VStack(spacing: 0) {
                    section(.appearance) { appearance }
                    section(.playback) { playback }
                    section(.video) { video }
                    section(.controls) { controls }
                    section(.sync) { syncAndExtras }
                    section(.general) { general }
                }
            }
        }
    }

    private func section<Content: View>(_ s: Section, @ViewBuilder content: () -> Content) -> some View {
        CollapsibleSection(title: s.rawValue,
                           collapsed: model.settings.collapsedSections.contains(s.rawValue),
                           onToggle: { model.toggleSectionCollapsed(s.rawValue) }) {
            content()
        }
    }

    // MARK: Appearance

    private var appearance: some View {
        Card(bottomSpacing: 8) {
            NavRow(title: "Theme", subtitle: model.settings.theme.tagline, detail: model.settings.theme.rawValue) {
                model.openSheet(.themes)
            }
            NavRow(title: "Controller skin", subtitle: "Colours of the on-screen buttons", detail: model.settings.skin.rawValue, showsSeparator: false) {
                model.openSheet(.skins)
            }
        }
    }

    // MARK: Playback

    private var playback: some View {
        Card(bottomSpacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Fast-forward speed · \(SpeedSteps.label(model.settings.ffSpeed))").font(Typography.row).foregroundColor(.white)
                Text("Used by the Quick Menu toggle and when you hold » and slide right")
                    .font(Typography.rowSubtitle).foregroundColor(Palette.textTertiary)
                SpeedSlider(speed: model.settings.ffSpeed) { model.setSpeed($0) }
                SpeedChips(current: model.settings.ffSpeed) { model.setSpeed($0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            RowSeparator()
            SettingsRow(title: "Volume", subtitle: "\(model.settings.volume)%") {
                Slider(value: Binding(get: { Double(model.settings.volume) }, set: { model.settings.volume = Int($0.rounded()) }),
                       in: 0...100, step: 5).tint(theme.accent).frame(width: 150)
            }
            SettingsRow(title: "Show » button in game", subtitle: "Hold and slide it to rewind or fast-forward") {
                TinboxToggle(isOn: settings.showFFButton)
            }
            SettingsRow(title: "Rewind", subtitle: "Keeps the last \(model.settings.rewindSeconds) seconds so you can undo mistakes") {
                TinboxToggle(isOn: settings.rewindEnabled)
            }
            SettingsRow(title: "Keep my music playing", subtitle: "Game sound mixes over Music, Spotify, etc.", showsSeparator: false) {
                TinboxToggle(isOn: settings.backgroundAudioMixing)
            }
        }
    }

    // MARK: Video

    private var video: some View {
        Card(bottomSpacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Portrait screen size").font(Typography.row).foregroundColor(.white)
                Text("Pixel-perfect is sharpest · Fit uses the full width")
                    .font(Typography.rowSubtitle).foregroundColor(Palette.textTertiary)
                SegmentedPill(options: DisplayScaling.portraitOptions, label: { $0.rawValue }, selection: settings.scaling)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            RowSeparator()
            SettingsRow(title: "Landscape screen", subtitle: landscapeSubtitle) {
                SegmentedPill(options: DisplayScaling.landscapeOptions, label: { $0.rawValue },
                              selection: settings.landscapeScaling)
            }
            SettingsRow(title: "Screen filter") {
                SegmentedPill(options: ScreenFilter.allCases, label: { $0.rawValue }, selection: settings.filter, fontSize: 12, horizontalPadding: 10)
            }
            SettingsRow(title: "BIOS", subtitle: bootSubtitle, showsSeparator: false) {
                SegmentedPill(options: BootMode.allCases, label: { $0 == .hle ? "Built-in" : "My file" },
                              selection: Binding(get: { model.settings.bootMode }, set: { pickBoot($0) }))
            }
        }
    }

    private var landscapeSubtitle: String {
        switch model.settings.landscapeScaling {
        case .fit: return "True proportions · bars at the sides"
        case .wide: return "Slightly stretched (10 %) · smaller bars"
        default: return "Fills the screen · noticeably stretched"
        }
    }

    private var bootSubtitle: String {
        if model.settings.bootMode == .biosFile, let name = model.settings.biosFileName {
            return "Using \(name) · applies next time a game starts"
        }
        return "Built-in works for almost every game · no file needed"
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
        Card(bottomSpacing: 8) {
            NavRow(title: "Edit button layout", subtitle: inGame ? "Drag to move · pinch to resize" : "Open a game first, then come back here") {
                guard inGame else { model.showToast("Open a game first"); return }
                model.activeSheet = nil
                model.isLayoutEditing = true
            }
            NavRow(title: "Bluetooth controller", detail: session.controllerConnected ? ControllerManager.shared.controllerName : "None connected") {
                model.openSheet(.controllers)
            }
            SettingsRow(title: "Turbo", subtitle: "Holding A or B presses it repeatedly", gap: 14) {
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
            SettingsRow(title: "Landscape button opacity", subtitle: "\(Int((model.settings.controlOpacity * 100).rounded()))%") {
                Slider(value: settings.controlOpacity, in: 0.3...1.0, step: 0.05).tint(theme.accent).frame(width: 150)
            }
            NavRow(title: "Layout profiles", subtitle: "Different button layouts for different games",
                   detail: model.currentGame?.layoutProfile ?? LayoutProfile.defaultName, showsSeparator: false) {
                model.openSheet(.layoutProfiles)
            }
        }
    }

    // MARK: Sync & extras

    private var syncAndExtras: some View {
        Card(bottomSpacing: 8) {
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
            SettingsRow(title: "Motion & rumble cartridges", subtitle: "Tilt, solar and rumble games use the phone's sensors", showsSeparator: false) {
                TinboxToggle(isOn: settings.sensorsEnabled)
            }
        }
    }

    // MARK: General

    private var general: some View {
        Card(bottomSpacing: 0) {
            NavRow(title: "ROM folder", subtitle: "Where your games live · shown in the Files app",
                   detail: ROMFolderAccess.shared.displayName) {
                model.openSheet(.romFolder)
            }
            SettingsRow(title: "When importing a ROM", subtitle: model.settings.importMode == .move ? "The file moves into the ROM folder" : "The file is copied; the original stays") {
                SegmentedPill(options: ImportMode.allCases, label: { $0.rawValue }, selection: settings.importMode)
            }
            SettingsRow(title: "Haptic feedback", subtitle: "A light tap when you press a button") {
                TinboxToggle(isOn: settings.hapticsEnabled)
            }
            NavRow(title: "Back up saves & states…", subtitle: "Zips them for Files, iCloud Drive or AirDrop · deleting the app deletes its saves") {
                model.exportBackup()
            }
            NavRow(title: "Restore a backup…", subtitle: "Merges a Tinbox backup zip back in") {
                model.importKind = .backup
            }
            SettingsRow(title: "Saving", subtitle: "In-game saves, the Auto slot on exit and an emergency snapshot on interruptions are always on") {
                Text("On").font(Typography.detail).foregroundColor(Palette.text40)
            }
            SettingsRow(title: "About", showsSeparator: false) {
                Text("Tinbox 1.0 · Redfern's Outpost").font(Typography.detail).foregroundColor(Palette.text40)
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
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
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

// MARK: - Themes

struct ThemesSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        BottomSheet(maxHeightFraction: 0.84, onDismiss: { model.openSheet(.settings) }) {
            SheetHeader(title: "Theme", onBack: { model.openSheet(.settings) }, bottomSpacing: 14) { EmptyView() }
            HuggingScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(ThemeName.allCases) { name in
                        ThemeSwatch(name: name, tokens: ThemeTokens.tokens(for: name), selected: name == model.settings.theme) {
                            ButtonHaptics.shared.tap()
                            model.settings.theme = name
                            model.showToast("\(name.rawValue) theme")
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }
}

/// Miniature of the in-game screen in the theme's colours.
private struct ThemeSwatch: View {
    @Environment(\.theme) private var current
    let name: ThemeName
    let tokens: ThemeTokens
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(tokens.well)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Palette.hairline08, lineWidth: 0.5))
                            .frame(height: 34)
                        HStack(spacing: 6) {
                            Capsule().fill(tokens.secondaryButton).frame(width: 26, height: 10)
                            Capsule().fill(tokens.tint).overlay(Capsule().stroke(tokens.tintBorder, lineWidth: 1)).frame(width: 26, height: 10)
                            Capsule().fill(tokens.secondaryButton).frame(width: 26, height: 10)
                        }
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3).fill(tokens.card).frame(width: 22, height: 22)
                            Spacer()
                            Circle().fill(tokens.accent).frame(width: 14, height: 14)
                            Circle().fill(tokens.card).frame(width: 14, height: 14)
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(tokens.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(selected ? current.accent : Palette.hairline10, lineWidth: selected ? 2 : 0.5))
                    if selected {
                        Circle().fill(current.accent).frame(width: 18, height: 18)
                            .overlay(Text("✓").font(.system(size: 11, weight: .heavy)).foregroundColor(.white))
                            .padding(6)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(name.rawValue).font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                    Text(name.tagline).font(.system(size: 11)).foregroundColor(Palette.textTertiary)
                }
            }
        }
        .buttonStyle(FadePressStyle(opacity: 0.75))
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
                SettingsRow(title: "Hardcore mode", subtitle: "Disables save states & cheats for leaderboards") {
                    TinboxToggle(isOn: Binding(get: { model.settings.raHardcore }, set: { model.setHardcore($0) }))
                }
                SettingsRow(title: "Progress tracking", subtitle: "Viewing only for now: unlocking needs the rcheevos runtime, and hardcore requires RetroAchievements to approve the emulator", showsSeparator: false) {
                    EmptyView()
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
