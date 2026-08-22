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

    private var current: GCController?
    private var keys: GBAKeyMask = [] {
        didSet { if keys != oldValue { onKeysChanged?(keys) } }
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
        if pad.buttonA.isPressed { mask.insert(.a) }
        if pad.buttonB.isPressed { mask.insert(.b) }
        if pad.buttonX.isPressed { mask.insert(.a) }   // turbo-friendly alias
        if pad.buttonY.isPressed { mask.insert(.b) }
        if pad.leftShoulder.isPressed || pad.leftTrigger.isPressed { mask.insert(.l) }
        if pad.rightShoulder.isPressed || pad.rightTrigger.isPressed { mask.insert(.r) }
        if pad.buttonOptions?.isPressed == true { mask.insert(.select) }
        if pad.buttonMenu.isPressed { mask.insert(.start) }

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
