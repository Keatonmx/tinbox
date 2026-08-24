//
//  GameView.swift
//  Tinbox
//
//  In-game screen. Picks the portrait or landscape layout from the real
//  interface orientation; the rotate buttons only request a rotation.
//

import SwiftUI

struct GameContainerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        // The reader respects the safe area so its insets are SwiftUI's own
        // (reading them from the key window was unreliable: zero whenever a
        // picker or alert window was key, which shifted the layout around).
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let full = CGSize(width: geo.size.width + insets.leading + insets.trailing,
                              height: geo.size.height + insets.top + insets.bottom)
            if full.width > full.height {
                // Landscape is full-bleed: draw at the real screen size, shifted
                // back over the insets.
                LandscapeGameView(size: full, safeArea: insets)
                    .frame(width: full.width, height: full.height)
                    .offset(x: -insets.leading, y: -insets.top)
            } else {
                PortraitGameView()
            }
        }
    }
}

// MARK: - Portrait

struct PortraitGameView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: EmulatorSession
    @Environment(\.theme) private var theme
    @State private var editingLayout: ControlLayout = .portraitDefault
    /// Boot flourish: the cartridge slides in, then the screen flips down like
    /// the tin's lid. First render is closed; onAppear either snaps or animates.
    @State private var lidOpen = false
    @State private var cartOffset: CGFloat = -240
    @State private var cartOpacity: Double = 1
    @State private var cartVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                if model.settings.showFastForwardButton {
                    TopBarFastForwardBubble()
                }
                if model.settings.showRotateButton {
                    CircleIconButton(size: 40, action: { rotate() }) {
                        RotateGlyph(primary: Palette.text70, secondary: theme.accent)
                    }
                }
            }
            // Balances the back button so the title stays centred when the
            // optional bubbles are hidden.
            .frame(minWidth: 40, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var screenBand: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
            EmulatorScreen(frameStore: session.frameStore,
                           scaling: model.effective.scaling,
                           filter: model.effective.filter,
                           paused: false)
                .aspectRatio(session.videoAspect, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Palette.hairline06, lineWidth: 1))
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            if let label = session.speedBadgeLabel {
                FFBadge(label: label)
                    .padding(.top, 20)
                    .padding(.trailing, 22)
            }
        }
        .overlay(alignment: .topLeading) {
            SpeedrunOverlay().padding(.top, 18).padding(.leading, 18)
        }
        .overlay(EggScreenOverlays())
        .padding(.top, 6)
        .fixedSize(horizontal: false, vertical: true)
        // Lid-open: hinged at the bottom like the icon's clamshell.
        .rotation3DEffect(.degrees(lidOpen ? 0 : -72), axis: (x: 1, y: 0, z: 0),
                          anchor: .bottom, perspective: 0.55)
        .opacity(lidOpen ? 1 : 0.4)
        // The cartridge rides on top (unrotated), sliding down into the band.
        .overlay(alignment: .top) {
            if cartVisible, let game = model.currentGame {
                CartridgeView(game: game)
                    .frame(width: 170)
                    .offset(y: cartOffset)
                    .opacity(cartOpacity)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            #if DEBUG
            // CI: freeze the boot mid-insert so a screenshot can check the cart.
            if CommandLine.arguments.contains("-tinbox-cart") {
                cartVisible = true
                cartOpacity = 1
                cartOffset = -60
                return
            }
            #endif
            if session.lidShown || !model.settings.bootAnimationEnabled || reduceMotion {
                lidOpen = true          // off, Reduce Motion, rotation or menu return
                session.lidShown = true
            } else {
                session.lidShown = true
                cartVisible = true
                cartOpacity = 1
                withAnimation(.easeIn(duration: 0.5)) { cartOffset = 30 }
                // Fades out just as it seats, then the lid springs open.
                withAnimation(.easeOut(duration: 0.22).delay(0.38)) { cartOpacity = 0 }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.55)) {
                    lidOpen = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    cartVisible = false
                    cartOffset = -240
                }
            }
        }
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
                    // Portrait keeps » in the top bar, next to the rotate bubble.
                    TouchControlsView(layout: model.currentProfile.portrait,
                                      metrics: metrics,
                                      size: geo.size,
                                      showFastForward: false,
                                      showShoulders: session.platform != .gb,
                                      onKeys: { session.setTouchKeys($0) },
                                      onMenu: { model.openSheet(.quickMenu) },
                                      onFastForwardTap: { model.showFastForwardHint() },
                                      onFastForwardDoubleTap: { model.toggleFastForward() },
                                      onScrub: { session.setScrub(offset: $0) })
                }
                if model.showBrightnessOverlay {
                    BrightnessOverlay().padding(.top, 44)
                }
                DarkRoomCue().padding(.top, 6)
            }
        }
        .padding(.top, 14)
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private func rotate() {
        // Request only — physical rotation keeps working afterwards.
        OrientationLock.set(mask: .allButUpsideDown, rotateTo: .landscapeRight)
    }
}

/// The » bubble in the portrait top bar: hold and slide to scrub, double-tap to
/// toggle permanent fast-forward, single tap shows the hint.
struct TopBarFastForwardBubble: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: EmulatorSession
    @Environment(\.theme) private var theme
    @State private var holding = false
    @State private var startTime: Date?
    @State private var moved = false
    @State private var lastTap: Date = .distantPast

    var body: some View {
        ZStack {
            Circle().fill(session.isFastForward ? AnyShapeStyle(theme.accent) : AnyShapeStyle(theme.chip))
            Circle().stroke(Palette.hairline08, lineWidth: 0.5)
            Text("»").font(.system(size: 17, weight: .heavy))
                .foregroundColor(session.isFastForward ? .white : Palette.text70)
        }
        .frame(width: 40, height: 40)
        .scaleEffect(holding ? 0.92 : 1)
        .overlay(alignment: .bottom) {
            if holding, let label = session.scrub.label ?? (holding ? "◀ rewind · fast-forward ▶" : nil) {
                Text(label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .fixedSize()
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(theme.badge)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                    .offset(y: 40)
                    .allowsHitTesting(false)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !holding {
                        holding = true
                        startTime = Date()
                        moved = false
                        ButtonHaptics.shared.tap()
                    }
                    if abs(value.translation.width) > 8 { moved = true }
                    session.setScrub(offset: value.translation.width)
                }
                .onEnded { _ in
                    let quick = !moved && (startTime.map { Date().timeIntervalSince($0) } ?? 1) < 0.3
                    holding = false
                    session.setScrub(offset: nil)
                    guard quick else { return }
                    if Date().timeIntervalSince(lastTap) < 0.35 {
                        lastTap = .distantPast
                        model.toggleFastForward()
                    } else {
                        lastTap = Date()
                        model.showFastForwardHint()
                    }
                }
        )
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
            // Sun follows the room via screen brightness (needs iOS auto-brightness).
            Button {
                ButtonHaptics.shared.tap()
                model.settings.autoSunEnabled.toggle()
                if model.settings.autoSunEnabled {
                    session.syncAutoSun()
                    model.showToast("Sun follows your surroundings (best with auto-brightness on)")
                }
            } label: {
                Text("Auto")
                    .font(Typography.chip)
                    .foregroundColor(model.settings.autoSunEnabled ? theme.accentText : Palette.textSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(model.settings.autoSunEnabled ? theme.tint : Color.clear)
                    .overlay(Capsule().stroke(model.settings.autoSunEnabled ? theme.tintBorder : Palette.hairline12, lineWidth: 1))
                    .clipShape(Capsule())
            }
            .buttonStyle(FadePressStyle())
            Image(systemName: "sun.min").foregroundColor(Palette.textSecondary)
            Slider(value: Binding(get: { Double(session.luminanceLevel) },
                                  set: { let level = Int($0.rounded())
                                         // Detent click per sun level.
                                         if level != session.luminanceLevel { ButtonHaptics.shared.tick() }
                                         session.luminanceLevel = level
                                         model.settings.autoSunEnabled = false }),
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
    /// Full screen size (safe area ignored).
    let size: CGSize
    let safeArea: EdgeInsets
    @State private var editingLayout: ControlLayout = .landscapeDefault

    private let metrics = ControlMetrics(isLandscape: true)

    /// Controls live inside the safe insets so nothing sits under the Dynamic
    /// Island, the rounded corners or the home indicator.
    private var controlsRect: CGRect {
        CGRect(x: safeArea.leading,
               y: 0,
               width: size.width - safeArea.leading - safeArea.trailing,
               height: size.height - safeArea.bottom)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            EmulatorScreen(frameStore: session.frameStore,
                           scaling: model.effective.landscapeScaling,
                           filter: model.effective.filter,
                           paused: false)
                .frame(width: size.width, height: size.height)

            // Overlay controls at the configured opacity.
            Group {
                if model.isLayoutEditing {
                    LayoutEditorView(metrics: metrics, size: controlsRect.size, layout: $editingLayout) {
                        model.saveLayout(portrait: nil, landscape: editingLayout)
                        model.isLayoutEditing = false
                        session.resume()
                        model.showToast("Layout saved")
                    }
                } else {
                    TouchControlsView(layout: model.currentProfile.landscape,
                                      metrics: metrics,
                                      size: controlsRect.size,
                                      showFastForward: model.settings.showFastForwardButton,
                                      showShoulders: session.platform != .gb,
                                      onKeys: { session.setTouchKeys($0) },
                                      onMenu: { model.openSheet(.quickMenu) },
                                      onFastForwardTap: { model.showFastForwardHint() },
                                      onFastForwardDoubleTap: { model.toggleFastForward() },
                                      onScrub: { session.setScrub(offset: $0) })
                        .opacity(model.effective.controlOpacity)
                }
            }
            .frame(width: controlsRect.width, height: controlsRect.height)
            .offset(x: controlsRect.minX, y: controlsRect.minY)

            // Speed badge sits left of the top-centre MENU pill.
            if let label = session.speedBadgeLabel {
                FFBadge(label: label)
                    .position(x: size.width * 0.5 - 110, y: max(24, safeArea.top + 6) + 12)
            }

            // Round buttons top-right.
            HStack(spacing: 8) {
                if session.cartridgeHardware.contains(.solar) {
                    landscapeCircle(action: { model.showBrightnessOverlay.toggle() }) {
                        Image(systemName: "sun.max.fill").font(.system(size: 15, weight: .semibold))
                            .foregroundColor(model.showBrightnessOverlay ? theme.accent : Palette.text70)
                    }
                }
                if model.settings.showRotateButton {
                    landscapeCircle(action: { rotateBack() }) {
                        RotateGlyph(primary: theme.accent, secondary: Palette.text70)
                    }
                }
            }
            .frame(width: size.width - max(20, safeArea.trailing + 8), alignment: .trailing)
            .padding(.top, max(14, safeArea.top + 4))

            if model.showBrightnessOverlay {
                BrightnessOverlay()
                    .frame(width: min(360, size.width * 0.5))
                    .position(x: size.width / 2, y: 90)
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
        OrientationLock.set(mask: .allButUpsideDown, rotateTo: .portrait)
    }
}
