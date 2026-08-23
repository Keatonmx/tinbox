//
//  Haptics.swift
//  Tinbox
//
//  Light impact on every control touchDown (respecting the Haptics setting),
//  plus cartridge rumble mapped to Core Haptics when the game drives the
//  rumble pin (WarioWare Twisted, Drill Dozer).
//

import UIKit
import CoreHaptics

/// Main-thread only.
final class ButtonHaptics {
    static let shared = ButtonHaptics()
    var enabled = true
    private let generator = UIImpactFeedbackGenerator(style: .light)
    private let selection = UISelectionFeedbackGenerator()

    private init() {
        generator.prepare()
        selection.prepare()
    }

    func tap() {
        guard enabled else { return }
        generator.impactOccurred(intensity: 0.8)
        generator.prepare()
    }

    /// Softer tick for d-pad direction changes while a finger is held down.
    func tick() {
        guard enabled else { return }
        selection.selectionChanged()
        selection.prepare()
    }
}

/// Called from the emulation thread once per frame with the rumble duty cycle.
final class RumbleHaptics: @unchecked Sendable {
    var enabled = true
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var lastIntensity: Float = 0
    private let queue = DispatchQueue(label: "com.redfernsoutpost.tinbox.rumble")

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        queue.async { [weak self] in self?.setUpEngine() }
    }

    private func setUpEngine() {
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            engine.resetHandler = { [weak self] in
                self?.queue.async { self?.setUpEngine() }
            }
            let event = CHHapticEvent(eventType: .hapticContinuous,
                                      parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.0),
                                                   CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)],
                                      relativeTime: 0, duration: 100)
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = true
            self.engine = engine
            self.player = player
        } catch {
            engine = nil
            player = nil
        }
    }

    func rumble(intensity: Float) {
        guard enabled, player != nil else { return }
        let clamped = max(0, min(1, intensity))
        // Ignore tiny changes to keep the haptic queue quiet.
        if abs(clamped - lastIntensity) < 0.05 { return }
        lastIntensity = clamped
        queue.async { [weak self] in
            guard let self, let engine = self.engine, let player = self.player else { return }
            do {
                if clamped > 0.02 {
                    try engine.start()
                    let param = CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: clamped, relativeTime: 0)
                    try player.sendParameters([param], atTime: CHHapticTimeImmediate)
                    try player.start(atTime: CHHapticTimeImmediate)
                } else {
                    try player.stop(atTime: CHHapticTimeImmediate)
                }
            } catch {
                // Haptics are best-effort.
            }
        }
    }
}
