//
//  LayoutEditorView.swift
//  Tinbox
//
//  "Edit button layout": overlays the in-game controls area. Drag a control to
//  move it, pinch to scale it (0.7×–1.6×). Saved per orientation into the
//  current layout profile.
//

import SwiftUI

struct LayoutEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    let metrics: ControlMetrics
    let size: CGSize
    @Binding var layout: ControlLayout
    let onDone: () -> Void

    @State private var selected: ControlID?
    @State private var dragStart: ControlPlacement?
    @State private var pinchStart: Double?

    var body: some View {
        let frames = ControlGeometry.frames(layout: layout, metrics: metrics, in: size, showFastForward: true)
        ZStack(alignment: .topLeading) {
            // Dotted guide so the editable region is obvious.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundColor(theme.accent.opacity(0.4))
                .frame(width: size.width, height: size.height)

            ForEach(ControlID.allCases) { control in
                if let frame = frames[control] {
                    ghost(control)
                        .frame(width: frame.width, height: frame.height)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(selected == control ? theme.accent : theme.accent.opacity(0.35),
                                        lineWidth: selected == control ? 2 : 1)
                        )
                        .position(x: frame.midX, y: frame.midY)
                        .gesture(dragGesture(for: control))
                        .simultaneousGesture(pinchGesture(for: control))
                }
            }

            VStack {
                Spacer()
                HStack(spacing: 10) {
                    SecondaryPill(title: "Reset") {
                        ButtonHaptics.shared.tap()
                        layout = metrics.isLandscape ? .landscapeDefault : .portraitDefault
                    }
                    Spacer()
                    Text(selected.map { "\($0.label) · \(Int((layout[$0].scale * 100).rounded()))%" } ?? "Drag to move · pinch to resize")
                        .font(Typography.meta)
                        .foregroundColor(Palette.textTertiary)
                    Spacer()
                    AccentPill(title: "Done") {
                        ButtonHaptics.shared.tap()
                        onDone()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func ghost(_ control: ControlID) -> some View {
        let base = metrics.baseSize(of: control)
        Group {
            switch control {
            case .dpad: DPadView(metrics: metrics, pressed: false)
            case .a: FaceButtonView(label: "A", metrics: metrics, pressed: false)
            case .b: FaceButtonView(label: "B", metrics: metrics, pressed: false)
            case .l: ShoulderPillView(label: "L", metrics: metrics, pressed: false)
            case .r: ShoulderPillView(label: "R", metrics: metrics, pressed: false)
            case .select: BottomPillView(label: "SELECT", metrics: metrics, pressed: false)
            case .start: BottomPillView(label: "START", metrics: metrics, pressed: false)
            case .menu: BottomPillView(label: "MENU", metrics: metrics, pressed: false, accent: true)
            case .fastForward: FastForwardButtonView(active: false, pressed: false)
            }
        }
        .frame(width: base.width, height: base.height)
        .scaleEffect(CGFloat(layout[control].scale))
        .opacity(0.9)
        .contentShape(Rectangle())
    }

    private func dragGesture(for control: ControlID) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = layout[control]
                    selected = control
                }
                guard let start = dragStart, size.width > 0, size.height > 0 else { return }
                var p = layout[control]
                p.x = min(1, max(0, start.x + Double(value.translation.width / size.width)))
                p.y = min(1, max(0, start.y + Double(value.translation.height / size.height)))
                layout[control] = p
            }
            .onEnded { _ in dragStart = nil }
    }

    private func pinchGesture(for control: ControlID) -> some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                if pinchStart == nil {
                    pinchStart = layout[control].scale
                    selected = control
                }
                guard let start = pinchStart else { return }
                var p = layout[control]
                p.scale = min(1.6, max(0.7, start * Double(scale)))
                layout[control] = p
            }
            .onEnded { _ in pinchStart = nil }
    }
}
