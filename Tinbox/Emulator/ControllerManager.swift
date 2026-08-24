//
//  ControllerManager.swift
//  Tinbox
//
//  GameController framework: standard mapping for Xbox / PlayStation / MFi.
//  A = A, B = B, L1/R1 = L/R, menu = Start, options = Select, d-pad and left
//  stick = d-pad. Publishes the combined key mask whenever it changes.
//

import Foundation
import GameController
import Combine

final class ControllerManager: ObservableObject {
    static let shared = ControllerManager()

    @Published private(set) var isConnected = false
    @Published private(set) var controllerName: String = "None connected"

    /// Called on whatever thread GameController delivers on.
    var onKeysChanged: ((GBAKeyMask) -> Void)?
    /// Fired when the controller's menu/home button should open the Quick Menu.
    var onMenuPressed: (() -> Void)?

    /// User remapping (Settings › Bluetooth controller). Missing keys fall
    /// back to the defaults below; "off" disables an element.
    var bindings: [String: String] = [:]
    static let defaultBindings: [String: String] = [
        "a": "a", "b": "b", "x": "a", "y": "b",
        "l1": "l", "r1": "r", "l2": "l", "r2": "r",
        "options": "select", "menu": "start",
    ]

    private var current: GCController?
    private var keys: GBAKeyMask = [] {
        didSet { if keys != oldValue { onKeysChanged?(keys) } }
    }

    private func target(_ physical: String) -> GBAKeyMask? {
        switch bindings[physical] ?? ControllerManager.defaultBindings[physical] ?? "off" {
        case "a": return .a
        case "b": return .b
        case "l": return .l
        case "r": return .r
        case "select": return .select
        case "start": return .start
        default: return nil
        }
    }

    private init() {
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            if let controller = note.object as? GCController { self?.attach(controller) }
        }
        NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            guard let self, let controller = note.object as? GCController, controller == self.current else { return }
            self.current = nil
            self.keys = []
            self.isConnected = false
            self.controllerName = "None connected"
            if let next = GCController.controllers().first { self.attach(next) }
        }
        if let controller = GCController.controllers().first {
            attach(controller)
        }
    }

    /// Starts Bluetooth discovery (iOS shows the system pairing UI for new devices).
    func startDiscovery() {
        GCController.startWirelessControllerDiscovery {}
    }

    private func attach(_ controller: GCController) {
        current = controller
        isConnected = true
        controllerName = controller.vendorName ?? "Controller"
        controller.playerIndex = .index1

        guard let gamepad = controller.extendedGamepad else { return }
        gamepad.valueChangedHandler = { [weak self] pad, _ in
            self?.readKeys(from: pad)
        }
        gamepad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.onMenuPressed?() }
        }
        if #available(iOS 14.0, *), let home = gamepad.buttonHome {
            home.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { self?.onMenuPressed?() }
            }
        }
    }

    private func readKeys(from pad: GCExtendedGamepad) {
        var mask: GBAKeyMask = []
        // Face buttons: keep the physical layout (bottom = A, right = B on GBA
        // matches Nintendo; on Xbox/PS layouts bottom is A/Cross, right is B/Circle).
        if pad.buttonA.isPressed, let k = target("a") { mask.insert(k) }
        if pad.buttonB.isPressed, let k = target("b") { mask.insert(k) }
        if pad.buttonX.isPressed, let k = target("x") { mask.insert(k) }
        if pad.buttonY.isPressed, let k = target("y") { mask.insert(k) }
        if pad.leftShoulder.isPressed, let k = target("l1") { mask.insert(k) }
        if pad.rightShoulder.isPressed, let k = target("r1") { mask.insert(k) }
        if pad.leftTrigger.isPressed, let k = target("l2") { mask.insert(k) }
        if pad.rightTrigger.isPressed, let k = target("r2") { mask.insert(k) }
        if pad.buttonOptions?.isPressed == true, let k = target("options") { mask.insert(k) }
        if pad.buttonMenu.isPressed, let k = target("menu") { mask.insert(k) }

        let dpad = pad.dpad
        let stick = pad.leftThumbstick
        let dead: Float = 0.45
        if dpad.up.isPressed || stick.yAxis.value > dead { mask.insert(.up) }
        if dpad.down.isPressed || stick.yAxis.value < -dead { mask.insert(.down) }
        if dpad.left.isPressed || stick.xAxis.value < -dead { mask.insert(.left) }
        if dpad.right.isPressed || stick.xAxis.value > dead { mask.insert(.right) }
        keys = mask
    }
}
