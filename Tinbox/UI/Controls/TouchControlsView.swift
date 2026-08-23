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

/// Press state lives in an object so taps re-render only the individual
/// control views, never the container that positions them.
final class ControlPressState: ObservableObject {
    @Published var pressed: Set<ControlID> = []
    @Published var dpadHighlight: GBAKeyMask = []
}

struct TouchControlsView: View {
    let layout: ControlLayout
    let metrics: ControlMetrics
    let size: CGSize
    let showFastForward: Bool
    /// False for Game Boy games (no L/R).
    var showShoulders: Bool = true
    let onKeys: (GBAKeyMask) -> Void
    let onMenu: () -> Void
    /// Quick tap on » (no slide) — shows the hint; a double tap toggles permanent fast-forward.
    let onFastForwardTap: () -> Void
    let onFastForwardDoubleTap: () -> Void
    /// Hold-and-slide on »: horizontal offset in points, nil on release.
    let onScrub: (CGFloat?) -> Void

    @StateObject private var press = ControlPressState()
    /// Last size that looked like a real controls area. Mid-relayout SwiftUI can
    /// propose a degenerate size for a frame or two; positioning from a fraction
    /// of such a height squeezed every control into a band at the top of the
    /// screen. Positions therefore always come from the latched size.
    @State private var stableSize: CGSize = .zero

    private static func isPlausible(_ s: CGSize) -> Bool {
        s.width.isFinite && s.height.isFinite && s.width >= 200 && s.height >= 250
    }

    var body: some View {
        let effective = TouchControlsView.isPlausible(size) ? size : stableSize
        let frames = ControlGeometry.frames(layout: layout, metrics: metrics, in: effective,
                                            showFastForward: showFastForward, showShoulders: showShoulders)
        ZStack(alignment: .topLeading) {
            ForEach(ControlID.allCases) { control in
                if let frame = frames[control] {
                    ControlSlot(control: control, metrics: metrics, press: press)
                        .frame(width: frame.width, height: frame.height)
                        .scaleEffect(CGFloat(layout[control].scale), anchor: .center)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
            MultiTouchInputView(frames: frames,
                                dpadSize: metrics.dpad * CGFloat(layout[.dpad].scale),
                                onKeys: { [press] keys, highlight in
                                    onKeys(keys)
                                    if press.dpadHighlight != highlight { press.dpadHighlight = highlight }
                                },
                                onPressed: { [press] in press.pressed = $0 },
                                onTap: { control in
                                    switch control {
                                    case .menu: onMenu()
                                    case .fastForward: onFastForwardTap()
                                    default: break
                                    }
                                },
                                onDoubleTap: { control in
                                    if control == .fastForward { onFastForwardDoubleTap() }
                                },
                                onScrub: onScrub)
                .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height)
        .onChange(of: size) { s in
            if TouchControlsView.isPlausible(s) { stableSize = s }
        }
        .onAppear {
            if TouchControlsView.isPlausible(size) { stableSize = size }
        }
        .onAppear {
            #if DEBUG
            // CI: `-tinbox-tapstorm` churns the pressed state like rapid tapping.
            guard CommandLine.arguments.contains("-tinbox-tapstorm") else { return }
            Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [press] _ in
                press.pressed = press.pressed.isEmpty ? [.a, .dpad] : []
                press.dpadHighlight = press.pressed.isEmpty ? [] : [.right]
            }
            #endif
        }
    }
}

/// One control, drawn at its base size; observes press state and the session
/// on its own so the positioning container above never re-renders on input.
private struct ControlSlot: View {
    @EnvironmentObject private var session: EmulatorSession
    let control: ControlID
    let metrics: ControlMetrics
    @ObservedObject var press: ControlPressState

    var body: some View {
        let base = metrics.baseSize(of: control)
        let pressed = press.pressed
        Group {
            switch control {
            case .dpad:
                DPadView(metrics: metrics, pressed: pressed.contains(.dpad), highlight: press.dpadHighlight)
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
                FastForwardButtonView(active: session.isFastForward,
                                      pressed: pressed.contains(.fastForward),
                                      scrubLabel: pressed.contains(.fastForward) ? (session.scrub.label ?? "◀ rewind · fast-forward ▶") : nil)
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
    let onDoubleTap: (ControlID) -> Void
    let onScrub: (CGFloat?) -> Void

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
        view.onDoubleTap = onDoubleTap
        view.onScrub = onScrub
    }
}

final class TouchLayerView: UIView {
    var frames: [ControlID: CGRect] = [:]
    var dpadSize: CGFloat = 150
    var onKeys: ((GBAKeyMask, GBAKeyMask) -> Void)?
    var onPressed: ((Set<ControlID>) -> Void)?
    var onTap: ((ControlID) -> Void)?
    var onDoubleTap: ((ControlID) -> Void)?
    var onScrub: ((CGFloat?) -> Void)?
    private var lastQuickTapTime: TimeInterval = 0

    private var touchControls: [ObjectIdentifier: ControlID] = [:]
    /// The touch currently holding the » scrubber, where it started and when.
    private var scrubTouch: ObjectIdentifier?
    private var scrubStart = CGPoint.zero
    private var scrubStartTime: TimeInterval = 0
    private var scrubMoved = false
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
                if hit == .fastForward, scrubTouch == nil {
                    scrubTouch = ObjectIdentifier(touch)
                    scrubStart = point
                    scrubStartTime = touch.timestamp
                    scrubMoved = false
                    onScrub?(0)
                }
            }
        }
        recompute(touches: event?.allTouches ?? touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            let point = touch.location(in: self)
            let current = touchControls[id]
            // The » scrubber: report horizontal travel, never hand off to another control.
            if id == scrubTouch {
                let dx = point.x - scrubStart.x
                if abs(dx) > 8 { scrubMoved = true }
                onScrub?(dx)
                continue
            }
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
            if id == scrubTouch {
                let quickTap = !scrubMoved && (touch.timestamp - scrubStartTime) < 0.3
                endScrub()
                if quickTap {
                    if touch.timestamp - lastQuickTapTime < 0.35 {
                        lastQuickTapTime = 0
                        onDoubleTap?(.fastForward)
                    } else {
                        lastQuickTapTime = touch.timestamp
                        onTap?(.fastForward)
                    }
                }
            }
            touchControls[id] = nil
        }
        recompute(touches: (event?.allTouches ?? []).subtracting(touches))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if ObjectIdentifier(touch) == scrubTouch { endScrub() }
            touchControls[ObjectIdentifier(touch)] = nil
        }
        recompute(touches: (event?.allTouches ?? []).subtracting(touches))
    }

    private func endScrub() {
        scrubTouch = nil
        onScrub?(nil)
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
            // Direction changed while sliding on the d-pad → soft tick.
            let directions: GBAKeyMask = [.up, .down, .left, .right]
            let oldDir = GBAKeyMask(rawValue: lastKeys.rawValue & directions.rawValue)
            let newDir = GBAKeyMask(rawValue: keys.rawValue & directions.rawValue)
            if !newDir.isEmpty, newDir != oldDir, !oldDir.isEmpty {
                ButtonHaptics.shared.tick()
            }
            lastKeys = keys
            onKeys?(keys, dpadHighlight)
        }
        if pressed != lastPressed {
            lastPressed = pressed
            onPressed?(pressed)
        }
    }
}
