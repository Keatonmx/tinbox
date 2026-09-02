//
//  SettingsSheet.swift
//  Tinbox
//
//  Secondary sheets reached from Settings: Controller skins, Themes,
//  RetroAchievements (+ sign-in), Layout profiles, Bluetooth controllers.
//  The Settings page itself is in SettingsSheetMain.swift.
//

import SwiftUI

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
                                .background(theme.wellStyle)
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
            .padding(.bottom, 4)
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
                    ForEach(ThemeName.allCases.filter { $0 != .saX || model.settings.secretThemeUnlocked }) { name in
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
                    .background(theme.cardStyle)
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
            .background(theme.cardStyle)
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
            .background(theme.wellStyle)
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
                .background(theme.cardStyle)
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
        BottomSheet(maxHeightFraction: 0.88, onDismiss: { model.openSheet(.settings) }) {
            SheetHeader(title: "Bluetooth Controller", onBack: { model.openSheet(.settings) }) {
                TintPill(title: "Scan") {
                    ControllerManager.shared.startDiscovery()
                    model.showToast("Scanning for controllers…")
                }
            }
            HuggingScrollView {
                VStack(spacing: 0) {
                    Card {
                        SettingsRow(title: "Status", subtitle: session.controllerConnected ? "Touch controls hide while connected" : "Pair in iOS Settings › Bluetooth, then return here", showsSeparator: false) {
                            Text(session.controllerConnected ? ControllerManager.shared.controllerName : "None connected")
                                .font(Typography.detail).foregroundColor(session.controllerConnected ? theme.accentText : Palette.text40)
                        }
                    }
                    SectionHeader(title: "Button mapping")
                    ControllerRemapCard()
                    Text("D-pad and left stick always steer. The Home button (or holding Menu on MFi pads) opens the Quick Menu.")
                        .font(Typography.meta)
                        .foregroundColor(Palette.text40)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.top, 10)
                }
            }
        }
    }
}
