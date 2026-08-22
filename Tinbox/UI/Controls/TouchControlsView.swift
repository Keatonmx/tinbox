//
//  TouchControlsView.swift
//  Tinbox
//
//  Lays out the drawn controls from a ControlLayout and puts a transparent
//  UIKit multi-touch layer on top. The touch layer turns touches into a
//  GBAKeyMask (several buttons at once, sliding between A/B, 8-way d-pad)
//  and reports pressed controls back so the visuals can react.
//

import SwiftUI
import UIKit

struct TouchControlsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: EmulatorSession
    let layout: ControlLayout
    let metrics: ControlMetrics
    let size: CGSize
    let showFastForward: Bool
    let onKeys: (GBAKeyMask) -> Void
    let onMenu: () -> Void
    let onFastForward: () -> Void

    @State private var pressed: Set<ControlID> = []
    @State private var dpadHighlight: GBAKeyMask = []

    var body: some View {
        let frames = ControlGeometry.frames(layout: layout, metrics: metrics, in: size, showFastForward: showFastForward)
        ZStack(alignment: .topLeading) {
            ForEach(ControlID.allCases) { control in
                if let frame = frames[control] {
                    controlView(control)
                        .frame(width: frame.width, height: frame.height)
                        .scaleEffect(CGFloat(layout[control].scale), anchor: .center)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
            MultiTouchInputView(frames: frames,
                                dpadSize: metrics.dpad * CGFloat(layout[.dpad].scale),
                                onKeys: { keys, highlight in
                                    onKeys(keys)
                                    dpadHighlight = highlight
                                },
                                onPressed: { pressed = $0 },
                                onTap: { control in
                                    switch control {
                                    case .menu: onMenu()
                                    case .fastForward: onFastForward()
                                    default: break
                                    }
                                })
                .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func controlView(_ control: ControlID) -> some View {
        // The visual is drawn at base size and scaled by the placement scale so
        // strokes/labels scale with it.
        let base = metrics.baseSize(of: control)
        Group {
            switch control {
            case .dpad:
                DPadView(metrics: metrics, pressed: pressed.contains(.dpad), highlight: dpadHighlight)
            case .a:
                FaceButtonView(label: "A", metrics: metrics, pressed: pressed.contains(.a), turbo: session.turboA)
            case .b:
                FaceButtonView(label: "B", metrics: metrics, pressed: pressed.contains(.b), turbo: session.turboB)
            case .l:
                ShoulderPillView(label: "L", metrics: metrics, pressed: pressed.contains(.l))
            case .r:
                ShoulderPillView(label: "R", metrics: metrics, pressed: pressed.contains(.r))
            case .select:
                BottomPillView(label: "SELECT", metrics: metrics, pressed: pressed.contains(.select))
            case .start:
                BottomPillView(label: "START", metrics: metrics, pressed: pressed.contains(.start))
            case .menu:
                BottomPillView(label: "MENU", metrics: metrics, pressed: pressed.contains(.menu), accent: true)
            case .fastForward:
                FastForwardButtonView(active: session.isFastForward, pressed: pressed.contains(.fastForward))
            }
        }
        .frame(width: base.width, height: base.height)
    }
}

// MARK: - UIKit multi-touch layer

struct MultiTouchInputView: UIViewRepresentable {
    let frames: [ControlID: CGRect]
    let dpadSize: CGFloat
    let onKeys: (GBAKeyMask, GBAKeyMask) -> Void
    let onPressed: (Set<ControlID>) -> Void
    let onTap: (ControlID) -> Void

    func makeUIView(context: Context) -> TouchLayerView {
        let view = TouchLayerView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        update(view)
        return view
    }

    func updateUIView(_ view: TouchLayerView, context: Context) {
        update(view)
    }

    private func update(_ view: TouchLayerView) {
        view.frames = frames
        view.dpadSize = dpadSize
        view.onKeys = onKeys
        view.onPressed = onPressed
        view.onTap = onTap
    }
}

final class TouchLayerView: UIView {
    var frames: [ControlID: CGRect] = [:]
    var dpadSize: CGFloat = 150
    var onKeys: ((GBAKeyMask, GBAKeyMask) -> Void)?
    var onPressed: ((Set<ControlID>) -> Void)?
    var onTap: ((ControlID) -> Void)?

    private var touchControls: [ObjectIdentifier: ControlID] = [:]
    private var lastKeys: GBAKeyMask = []
    private var lastPressed: Set<ControlID> = []

    /// Extra slop around each control so a finger that drifts slightly keeps the button held.
    private let slop: CGFloat = 14

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            if let hit = control(at: point, slop: 0) {
                touchControls[ObjectIdentifier(touch)] = hit
                ButtonHaptics.shared.tap()
                if hit == .fastForward { onTap?(.fastForward) }
            }
        }
        recompute(touches: event?.allTouches ?? touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            let point = touch.location(in: self)
            let current = touchControls[id]
            // A touch that started on the d-pad stays on it (sliding between directions).
            if current == .dpad { continue }
            // Rolling from one face button onto another.
            if let next = control(at: point, slop: slop), next != current, next != .dpad, next != .menu, next != .fastForward {
                touchControls[id] = next
                ButtonHaptics.shared.tap()
            } else if current != nil, control(at: point, slop: slop) == nil {
                touchControls[id] = nil
            }
        }
        recompute(touches: event?.allTouches ?? touches)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            if touchControls[id] == .menu, let frame = frames[.menu], frame.insetBy(dx: -slop, dy: -slop).contains(touch.location(in: self)) {
                onTap?(.menu)
            }
            touchControls[id] = nil
        }
        recompute(touches: (event?.allTouches ?? []).subtracting(touches))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { touchControls[ObjectIdentifier(touch)] = nil }
        recompute(touches: (event?.allTouches ?? []).subtracting(touches))
    }

    private func control(at point: CGPoint, slop: CGFloat) -> ControlID? {
        // Face buttons and d-pad first (they overlap the slop of pills less).
        let order: [ControlID] = [.a, .b, .dpad, .fastForward, .menu, .select, .start, .l, .r]
        for control in order {
            guard let frame = frames[control] else { continue }
            if control == .a || control == .b || control == .fastForward {
                let r = frame.width / 2 + slop
                let c = CGPoint(x: frame.midX, y: frame.midY)
                if hypot(point.x - c.x, point.y - c.y) <= r { return control }
            } else if frame.insetBy(dx: -slop, dy: -slop).contains(point) {
                return control
            }
        }
        return nil
    }

    private func recompute(touches: Set<UITouch>) {
        var keys: GBAKeyMask = []
        var dpadHighlight: GBAKeyMask = []
        var pressed: Set<ControlID> = []
        let live = Set(touches.filter { $0.phase != .ended && $0.phase != .cancelled }.map { ObjectIdentifier($0) })
        touchControls = touchControls.filter { live.contains($0.key) }

        for touch in touches {
            guard let control = touchControls[ObjectIdentifier(touch)] else { continue }
            pressed.insert(control)
            switch control {
            case .a: keys.insert(.a)
            case .b: keys.insert(.b)
            case .l: keys.insert(.l)
            case .r: keys.insert(.r)
            case .select: keys.insert(.select)
            case .start: keys.insert(.start)
            case .dpad:
                if let frame = frames[.dpad] {
                    let p = touch.location(in: self)
                    let d = ControlGeometry.dpadKeys(dx: p.x - frame.midX, dy: p.y - frame.midY, size: dpadSize)
                    keys.formUnion(d)
                    dpadHighlight.formUnion(d)
                }
            case .menu, .fastForward:
                break
            }
        }
        if keys != lastKeys {
            lastKeys = keys
            onKeys?(keys, dpadHighlight)
        }
        if pressed != lastPressed {
            lastPressed = pressed
            onPressed?(pressed)
        }
    }
}
