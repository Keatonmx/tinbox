//
//  ControlGeometry.swift
//  Tinbox
//
//  Sizes from the design (portrait / landscape) and the one function that maps
//  a ControlLayout to on-screen frames. Both the SwiftUI visuals and the UIKit
//  touch layer use it, so they can never disagree.
//

import SwiftUI

struct ControlMetrics {
    let isLandscape: Bool

    var shoulder: CGSize { isLandscape ? CGSize(width: 92, height: 32) : CGSize(width: 96, height: 34) }
    var dpad: CGFloat { isLandscape ? 140 : 150 }
    var dpadArm: CGFloat { isLandscape ? 48 : 50 }
    var dpadRadius: CGFloat { isLandscape ? 13 : 14 }
    var face: CGFloat { isLandscape ? 62 : 66 }
    var ff: CGFloat { 44 }
    var pill: CGSize { isLandscape ? CGSize(width: 80, height: 30) : CGSize(width: 84, height: 34) }
    var pillFont: CGFloat { isLandscape ? 10 : 11 }
    var faceFont: CGFloat { isLandscape ? 20 : 22 }
    var shoulderFont: CGFloat { isLandscape ? 13 : 14 }

    func baseSize(of control: ControlID) -> CGSize {
        switch control {
        case .dpad: return CGSize(width: dpad, height: dpad)
        case .a, .b: return CGSize(width: face, height: face)
        case .l, .r: return shoulder
        case .select, .start, .menu: return pill
        case .fastForward: return CGSize(width: ff, height: ff)
        }
    }
}

enum ControlGeometry {
    /// Frames for every control given the container size.
    static func frames(layout: ControlLayout, metrics: ControlMetrics, in size: CGSize,
                       showFastForward: Bool, showShoulders: Bool = true) -> [ControlID: CGRect] {
        var result: [ControlID: CGRect] = [:]
        // Nothing sensible can be placed before the area has a real size
        // (SwiftUI's first layout pass can propose zero).
        guard size.width.isFinite, size.height.isFinite, size.width >= 100, size.height >= 100 else { return result }
        for control in ControlID.allCases {
            if control == .fastForward && !showFastForward { continue }
            if (control == .l || control == .r) && !showShoulders { continue }   // Game Boy has no shoulders
            let placement = layout[control]
            let base = metrics.baseSize(of: control)
            let scale = CGFloat(placement.scale)
            let w = base.width * scale
            let h = base.height * scale
            let cx = CGFloat(placement.x) * size.width
            let cy = CGFloat(placement.y) * size.height
            result[control] = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
        }
        return result
    }

    /// Key bits for a touch on the d-pad, relative to its centre.
    static func dpadKeys(dx: CGFloat, dy: CGFloat, size: CGFloat) -> GBAKeyMask {
        var mask: GBAKeyMask = []
        let dead = size * 0.09
        let ax = abs(dx), ay = abs(dy)
        // A direction is active when its component exceeds the dead zone and the
        // touch lies within 67.5° of that axis (22.5° diagonal overlap).
        if ax > dead && ax * 2.414 > ay { mask.insert(dx > 0 ? .right : .left) }
        if ay > dead && ay * 2.414 > ax { mask.insert(dy > 0 ? .down : .up) }
        return mask
    }
}
