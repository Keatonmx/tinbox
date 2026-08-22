//
//  GameView.swift
//  Tinbox
//
//  In-game screen. Picks the portrait or landscape layout from the rotate
//  button state and the real interface orientation.
//

import SwiftUI

struct GameContainerView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: EmulatorSession

    var body: some View {
        GeometryReader { geo in
            // Layout follows the real geometry; the rotate buttons only request
            // an orientation change (see OrientationLock / AppDelegate).
            let landscape = geo.size.width > geo.size.height
            if landscape {
                LandscapeGameView(size: geo.size, safeArea: geo.safeAreaInsets)
                    .ignoresSafeArea()
            } else {
                PortraitGameView(safeArea: geo.safeAreaInsets)
            }
        }
    }
}

// MARK: - Portrait

struct PortraitGameView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: EmulatorSession
    @Environment(\.theme) private var theme
    let safeArea: EdgeInsets
    @State private var editingLayout: ControlLayout = .portraitDefault

    private let metrics = ControlMetrics(isLandscape: false)

    var body: some View {
        VStack(spacing: 0) {
            topBar
            screenBand
            controlsArea
        }
        .background(theme.bg.ignoresSafeArea())
        .onChange(of: model.isLayoutEditing) { editing in
            if editing { editingLayout = model.currentProfile.portrait }
        }
    }

    private var topBar: some View {
        HStack {
            CircleIconButton(size: 40, action: { model.exitGame() }) {
                ChevronShape(direction: .left)
                    .stroke(Palette.text80, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .frame(width: 10, height: 17)
            }
            Spacer()
            Text(model.currentGame?.title ?? "Game")
                .font(Typography.cardTitle)
                .tracking(-0.2)
                .foregroundColor(.white)
                .lineLimit(1)
            Spacer()
            HStack(spacing: 8) {
                if session.cartridgeHardware.contains(.solar) {
                    CircleIconButton(size: 40, action: { model.showBrightnessOverlay.toggle() }) {
                        Image(systemName: "sun.max.fill").font(.system(size: 15, weight: .semibold))
                            .foregroundColor(model.showBrightnessOverlay ? theme.accent : Palette.text70)
                    }
                }
                CircleIconButton(size: 40, action: { rotate() }) {
                    RotateGlyph(primary: Palette.text70, secondary: theme.accent)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var screenBand: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
            EmulatorScreen(frameStore: session.frameStore,
                           scaling: model.settings.scaling,
                           filter: model.settings.filter,
                           paused: false)
                .aspectRatio(3.0 / 2.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Palette.hairline06, lineWidth: 1))
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            if session.isFastForward {
                FFBadge(label: SpeedSteps.label(session.ffSpeed))
                    .padding(.top, 20)
                    .padding(.trailing, 22)
            }
        }
        .padding(.top, 6)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var controlsArea: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                if model.isLayoutEditing {
                    LayoutEditorView(metrics: metrics, size: geo.size, layout: $editingLayout) {
                        model.saveLayout(portrait: editingLayout, landscape: nil)
                        model.isLayoutEditing = false
                        session.resume()
                        model.showToast("Layout saved")
                    }
                } else {
                    TouchControlsView(layout: model.currentProfile.portrait,
                                      metrics: metrics,
                                      size: geo.size,
                                      showFastForward: model.settings.showFFButton,
                                      onKeys: { session.setTouchKeys($0) },
                                      onMenu: { model.openSheet(.quickMenu) },
                                      onFastForward: { model.toggleFastForward() })
                }
                if model.showBrightnessOverlay {
                    BrightnessOverlay().padding(.top, 44)
                }
            }
        }
        .padding(.top, 14)
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private func rotate() {
        model.forceLandscape = true
        OrientationLock.set(mask: .landscape, rotateTo: .landscapeRight)
    }
}

struct RotateGlyph: View {
    let primary: Color
    let secondary: Color
    @Environment(\.theme) private var theme
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 2).stroke(primary, lineWidth: 1.5).frame(width: 10, height: 12)
            RoundedRectangle(cornerRadius: 2).fill(theme.bg)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(secondary, lineWidth: 1.5))
                .frame(width: 9, height: 7)
                .offset(x: 7, y: 5)
        }
        .frame(width: 18, height: 14)
    }
}

/// Solar-sensor brightness slider (Boktai). Level 0 = dark, 10 = direct sun.
struct BrightnessOverlay: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: EmulatorSession
    @Environment(\.theme) private var theme
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sun.min").foregroundColor(Palette.textSecondary)
            Slider(value: Binding(get: { Double(session.luminanceLevel) },
                                  set: { session.luminanceLevel = Int($0.rounded()) }),
                   in: 0...10, step: 1)
                .tint(theme.accent)
            Image(systemName: "sun.max.fill").foregroundColor(Palette.textSecondary)
            Text("\(session.luminanceLevel)").font(Typography.chip).foregroundColor(theme.accentText).frame(width: 18)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(theme.sheet.opacity(0.95))
        .overlay(Capsule().stroke(Palette.hairline12, lineWidth: 0.5))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.4), radius: 10, y: 6)
        .padding(.horizontal, 8)
    }
}

// MARK: - Landscape

struct LandscapeGameView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: EmulatorSession
    @Environment(\.theme) private var theme
    let size: CGSize
    let safeArea: EdgeInsets
    @State private var editingLayout: ControlLayout = .landscapeDefault

    private let metrics = ControlMetrics(isLandscape: true)

    var body: some View {
        ZStack(alignment: .top) {
            Color.black
            EmulatorScreen(frameStore: session.frameStore,
                           scaling: model.settings.scaling,
                           filter: model.settings.filter,
                           paused: false)

            // Overlay controls at the configured opacity.
            Group {
                if model.isLayoutEditing {
                    LayoutEditorView(metrics: metrics, size: size, layout: $editingLayout) {
                        model.saveLayout(portrait: nil, landscape: editingLayout)
                        model.isLayoutEditing = false
                        session.resume()
                        model.showToast("Layout saved")
                    }
                } else {
                    TouchControlsView(layout: model.currentProfile.landscape,
                                      metrics: metrics,
                                      size: size,
                                      showFastForward: model.settings.showFFButton,
                                      onKeys: { session.setTouchKeys($0) },
                                      onMenu: { model.openSheet(.quickMenu) },
                                      onFastForward: { model.toggleFastForward() })
                        .opacity(model.settings.controlOpacity)
                }
            }

            if session.isFastForward {
                FFBadge(label: SpeedSteps.label(session.ffSpeed))
                    .padding(.top, max(24, safeArea.top + 6))
            }

            HStack {
                if session.cartridgeHardware.contains(.solar) {
                    landscapeCircle(action: { model.showBrightnessOverlay.toggle() }) {
                        Image(systemName: "sun.max.fill").font(.system(size: 15, weight: .semibold))
                            .foregroundColor(model.showBrightnessOverlay ? theme.accent : Palette.text70)
                    }
                }
                landscapeCircle(action: { rotateBack() }) {
                    RotateGlyph(primary: theme.accent, secondary: Palette.text70)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, max(20, safeArea.top + 4))
            .padding(.trailing, max(20, safeArea.trailing + 8))

            if model.showBrightnessOverlay {
                BrightnessOverlay().padding(.top, 70).frame(maxWidth: 360)
            }
        }
        .frame(width: size.width, height: size.height)
        .onChange(of: model.isLayoutEditing) { editing in
            if editing { editingLayout = model.currentProfile.landscape }
        }
    }

    private func landscapeCircle<Icon: View>(action: @escaping () -> Void, @ViewBuilder icon: () -> Icon) -> some View {
        Button {
            ButtonHaptics.shared.tap()
            action()
        } label: {
            ZStack {
                Circle().fill(Color(rgba: 28, 28, 30, 0.85))
                Circle().stroke(Palette.hairline12, lineWidth: 0.5)
                icon()
            }
            .frame(width: 40, height: 40)
        }
        .buttonStyle(ScalePressStyle())
    }

    private func rotateBack() {
        model.forceLandscape = false
        OrientationLock.set(mask: .allButUpsideDown, rotateTo: .portrait)
    }
}
