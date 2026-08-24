//
//  QuickMenuSheet.swift
//  Tinbox
//
//  Quick Menu (v3 IA): action tiles (Save / Load / Rewind), Speed card
//  (FF toggle + preset chips), navigation card, Exit.
//  Plus the compact landscape dialog (420pt, radius 26, four 64pt tiles).
//

import SwiftUI

struct QuickMenuSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: EmulatorSession
    @Environment(\.theme) private var theme

    var body: some View {
        BottomSheet(maxHeightFraction: 0.92, onDismiss: { model.closeSheet() }) {
            SheetHeader(title: "Quick Menu") {
                AccentPill(title: "Resume") { model.closeSheet() }
            }
            HuggingScrollView { VStack(spacing: 0) {

            // Action tiles
            HStack(spacing: 10) {
                actionTile(title: "Save", subtitle: "To Auto slot") { model.saveToAutoSlot() }
                actionTile(title: "Load", subtitle: model.latestStateDescription) { model.loadLatestState() }
                Button {
                    ButtonHaptics.shared.tap()
                    model.rewindTenSeconds()
                } label: {
                    VStack(spacing: 3) {
                        Text("↺ Rewind").font(.system(size: 15, weight: .bold)).foregroundColor(theme.accentText)
                        Text("Back 10 seconds").font(.system(size: 11)).foregroundColor(theme.accentText.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(theme.tint)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.tintBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(FadePressStyle(opacity: 0.75))
            }
            .padding(.bottom, 12)

            // Speed card
            Card {
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Fast-forward").font(Typography.row).foregroundColor(.white)
                            Text(fastForwardSubtitle)
                                .font(Typography.rowSubtitle).foregroundColor(Palette.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        TinboxToggle(isOn: Binding(get: { session.isFastForward },
                                                   set: { session.isFastForward = $0 }))
                    }
                    HStack {
                        SpeedChips(current: session.ffSpeed) { model.setSpeed($0) }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }

            // Navigation
            Card {
                NavRow(title: "All save states", detail: "\(model.gameData.slots.filter(\.isFilled).count) of \(SaveSlot.count) used") { model.openSheet(.saveStates) }
                NavRow(title: "Time Capsule", detail: capsuleDetail) { model.openSheet(.timeCapsule) }
                NavRow(title: "Cheats", detail: "\(model.activeCheatCount) active") { model.openSheet(.cheats) }
                NavRow(title: "Settings", showsSeparator: false) { model.openSheet(.settings) }
            }

            // Exit
            Button {
                ButtonHaptics.shared.tap()
                model.exitGame()
            } label: {
                Text("Exit Game")
                    .font(Typography.rowSemibold)
                    .foregroundColor(Palette.destructive)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 54)
                    .background(theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(ExitPressStyle())

            } }
        }
    }

    private var capsuleDetail: String {
        guard let id = model.currentGame?.id else { return "" }
        let n = TimeCapsuleStore.shared.count(for: id)
        return n == 1 ? "1 moment" : "\(n) moments"
    }

    private var fastForwardSubtitle: String {
        let speed = SpeedSteps.label(session.ffSpeed)
        if session.isFastForward { return "Running at \(speed) until you turn this off" }
        return model.settings.showFastForwardButton ? "Turn on for \(speed) · or hold » in game" : "Turn on for \(speed)"
    }

    private func actionTile(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button {
            ButtonHaptics.shared.tap()
            action()
        } label: {
            VStack(spacing: 3) {
                Text(title).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                Text(subtitle).tileSubtitle().foregroundColor(Palette.textTertiary).padding(.horizontal, 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(theme.card)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.hairline08, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(FadePressStyle(opacity: 0.75))
    }
}

private extension View {
    func tileSubtitle() -> some View { self.font(.system(size: 11)).lineLimit(1).minimumScaleFactor(0.8) }
}

struct ExitPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(configuration.isPressed ? Palette.destructive.opacity(0.12) : Color.clear))
    }
}

// MARK: - Landscape compact dialog

struct LandscapeQuickMenu: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: EmulatorSession
    @Environment(\.theme) private var theme
    /// Switches to the full bottom sheet ("More…").
    let onMore: () -> Void

    var body: some View {
        ZStack {
            Palette.backdrop.ignoresSafeArea().onTapGesture { model.closeSheet() }
            VStack(spacing: 12) {
                HStack {
                    Text("Quick Menu").font(Typography.dialogTitle).foregroundColor(.white)
                    Spacer()
                    AccentPill(title: "Resume", compact: true) { model.closeSheet() }
                }
                HStack(spacing: 10) {
                    tile(glyph: "»", label: "FF \(SpeedSteps.label(session.ffSpeed))",
                         color: session.isFastForward ? theme.accentText2 : Palette.text85,
                         background: session.isFastForward ? theme.tint2 : theme.card,
                         glyphSize: 18, glyphWeight: .heavy) {
                        model.toggleFastForward()
                    }
                    tile(glyph: "▼", label: "Save", color: Palette.text85, background: theme.card) {
                        model.saveToAutoSlot()
                    }
                    tile(glyph: "▲", label: "Load", color: Palette.text85, background: theme.card) {
                        model.loadLatestState()
                    }
                    tile(glyph: "⋯", label: "More", color: Palette.text85, background: theme.card) {
                        onMore()
                    }
                    tile(glyph: "×", label: "Exit", color: Palette.destructive,
                         background: Palette.destructive.opacity(0.12), border: Palette.destructive.opacity(0.4)) {
                        model.exitGame()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(width: 480)
            .background(theme.sheet)
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Palette.hairline10, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 20)
        }
    }

    private func tile(glyph: String, label: String, color: Color, background: Color, border: Color = Palette.hairline10,
                      glyphSize: CGFloat = 16, glyphWeight: Font.Weight = .regular,
                      action: @escaping () -> Void) -> some View {
        Button {
            ButtonHaptics.shared.tap()
            action()
        } label: {
            VStack(spacing: 3) {
                Text(glyph).font(.system(size: glyphSize, weight: glyphWeight)).foregroundColor(color)
                Text(label).font(.system(size: 12, weight: .semibold)).foregroundColor(color)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(background)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(border, lineWidth: border == Palette.hairline10 ? 0.5 : 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(FadePressStyle(opacity: 0.8))
    }
}
