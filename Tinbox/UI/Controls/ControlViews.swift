//
//  ControlViews.swift
//  Tinbox
//
//  The drawn controls. They are purely visual: touches are handled by
//  MultiTouchInputView so several buttons can be held at once.
//

import SwiftUI

/// Visual press state: translateY(1px), slight dip, and a *lightening* — on a
/// dark theme a pressed control should read as lit, not sunk to black.
private struct PressedLook: ViewModifier {
    let pressed: Bool
    var scale: CGFloat = 1
    func body(content: Content) -> some View {
        content
            .offset(y: pressed ? 1 : 0)
            .scaleEffect(pressed ? scale : 1)
            .brightness(pressed ? 0.07 : 0)
            .animation(.easeOut(duration: 0.06), value: pressed)
    }
}

struct DPadView: View {
    @Environment(\.skin) private var skin
    let metrics: ControlMetrics
    let pressed: Bool
    var highlight: GBAKeyMask = []

    var body: some View {
        let size = metrics.dpad
        let arm = metrics.dpadArm
        let radius = metrics.dpadRadius
        let verticalActive = highlight.contains(.up) || highlight.contains(.down)
        let horizontalActive = highlight.contains(.left) || highlight.contains(.right)
        ZStack {
            // Vertical arm
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(skin.padGradient)
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.white.opacity(verticalActive ? 0.18 : 0)))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Palette.hairline10, lineWidth: 0.5))
                .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1).padding(.horizontal, radius) }
                .shadow(color: .black.opacity(0.4), radius: 4, y: 3)
                .frame(width: arm, height: size)
            // Horizontal arm
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(skin.padGradient)
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.white.opacity(horizontalActive ? 0.18 : 0)))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Palette.hairline10, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.4), radius: 4, y: 3)
                .frame(width: size, height: arm)
            // Arrows at 30% white
            Group {
                Triangle().fill(Color.white.opacity(highlight.contains(.up) ? 0.9 : 0.3)).frame(width: 12, height: 9)
                    .position(x: size / 2, y: 11 + 4.5)
                Triangle().fill(Color.white.opacity(highlight.contains(.down) ? 0.9 : 0.3)).frame(width: 12, height: 9)
                    .rotationEffect(.degrees(180))
                    .position(x: size / 2, y: size - 11 - 4.5)
                Triangle().fill(Color.white.opacity(highlight.contains(.left) ? 0.9 : 0.3)).frame(width: 12, height: 9)
                    .rotationEffect(.degrees(-90))
                    .position(x: 11 + 4.5, y: size / 2)
                Triangle().fill(Color.white.opacity(highlight.contains(.right) ? 0.9 : 0.3)).frame(width: 12, height: 9)
                    .rotationEffect(.degrees(90))
                    .position(x: size - 11 - 4.5, y: size / 2)
            }
            // Recessed centre dot
            Circle()
                .fill(Color.black.opacity(0.25))
                .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1).blur(radius: 1).mask(Circle()))
                .frame(width: 24, height: 24)
        }
        .frame(width: size, height: size)
        // No PressedLook here: the pad body stays constant and only the pressed
        // direction's arm + arrow light up (whole-pad darkening made the idle
        // arms vanish into the background).
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

struct FaceButtonView: View {
    @Environment(\.skin) private var skin
    @Environment(\.theme) private var theme
    let label: String
    let metrics: ControlMetrics
    let pressed: Bool
    var turbo = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(skin.buttonGradient)
                .overlay(Circle().stroke(Palette.hairline14, lineWidth: 0.5))
                .overlay(alignment: .top) {
                    Circle().stroke(Color.white.opacity(0.16), lineWidth: 1.5).padding(1).mask(
                        LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
                }
                .shadow(color: .black.opacity(0.45), radius: 5, y: 4)
                .overlay(
                    Text(label)
                        .font(.system(size: metrics.faceFont, weight: .bold))
                        .foregroundColor(Palette.text85))
                .frame(width: metrics.face, height: metrics.face)
            if turbo {
                Circle().fill(theme.accent)
                    .overlay(Circle().stroke(theme.bg, lineWidth: 2))
                    .frame(width: 12, height: 12)
                    .offset(x: 4, y: -4)
            }
        }
        .modifier(PressedLook(pressed: pressed, scale: 0.96))
    }
}

struct ShoulderPillView: View {
    let label: String
    let metrics: ControlMetrics
    let pressed: Bool

    var body: some View {
        Capsule()
            .fill(LinearGradient(colors: [Palette.shoulderTop, Palette.shoulderBottom], startPoint: .top, endPoint: .bottom))
            .overlay(Capsule().stroke(Palette.hairline10, lineWidth: 0.5))
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1).padding(.horizontal, 14) }
            .shadow(color: .black.opacity(0.35), radius: 2.5, y: 2)
            .overlay(Text(label).font(.system(size: metrics.shoulderFont, weight: .bold)).foregroundColor(Palette.text75))
            .frame(width: metrics.shoulder.width, height: metrics.shoulder.height)
            .modifier(PressedLook(pressed: pressed))
    }
}

struct BottomPillView: View {
    @Environment(\.skin) private var skin
    @Environment(\.theme) private var theme
    let label: String
    let metrics: ControlMetrics
    let pressed: Bool
    var accent = false

    var body: some View {
        Group {
            if accent {
                Capsule()
                    .fill(metrics.isLandscape ? AnyShapeStyle(skin.padGradient) : AnyShapeStyle(theme.tint))
                    // Landscape overlays sit on bright game pixels: keep a solid base under the tint.
                    .overlay(Capsule().fill(metrics.isLandscape ? theme.tint2 : Color.clear))
                    .overlay(Capsule().stroke(metrics.isLandscape ? theme.tintBorder2 : theme.tintBorder, lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                    .overlay(
                        Text(label).font(.system(size: metrics.pillFont, weight: .bold)).tracking(1)
                            .foregroundColor(metrics.isLandscape ? theme.accentText2 : theme.accentText))
            } else {
                Capsule()
                    .fill(skin.padGradient)
                    .overlay(Capsule().stroke(Palette.hairline10, lineWidth: 0.5))
                    .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1).padding(.horizontal, 14) }
                    .shadow(color: .black.opacity(0.35), radius: 2.5, y: 2)
                    .overlay(
                        Text(label).font(.system(size: metrics.pillFont, weight: .bold)).tracking(1)
                            .foregroundColor(metrics.isLandscape ? Palette.text65 : Palette.textSecondary))
            }
        }
        .frame(width: metrics.pill.width, height: metrics.pill.height)
        .modifier(PressedLook(pressed: pressed))
    }
}

struct FastForwardButtonView: View {
    @Environment(\.theme) private var theme
    let active: Bool
    let pressed: Bool
    /// Shown above the button while it is held (hint or current scrub speed).
    var scrubLabel: String? = nil

    var body: some View {
        Circle()
            .fill(active ? AnyShapeStyle(theme.accent)
                         : AnyShapeStyle(LinearGradient(colors: [Palette.shoulderTop, Palette.shoulderBottom], startPoint: .top, endPoint: .bottom)))
            .overlay(Circle().stroke(Palette.hairline12, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
            .overlay(Text("»").font(.system(size: 17, weight: .heavy)).foregroundColor(active ? .white : Palette.textSecondary))
            .frame(width: 44, height: 44)
            .scaleEffect(pressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.06), value: pressed)
            .overlay(alignment: .top) {
                if let scrubLabel {
                    Text(scrubLabel)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(theme.badge)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                        .offset(y: -40)
                        .transition(.opacity)
                }
            }
    }
}

struct FFBadge: View {
    @Environment(\.theme) private var theme
    let label: String
    var body: some View {
        Text("» \(label)")
            .font(.system(size: 12, weight: .bold))
            .tracking(0.5)
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(theme.badge)
            .clipShape(Capsule())
    }
}

extension Palette {
    static let text65 = Color(rgba: 235, 235, 245, 0.65)
}
