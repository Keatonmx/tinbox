//
//  Sensors.swift
//  Tinbox
//
//  CoreMotion → mGBA tilt/gyro peripherals (Yoshi Topsy-Turvy, WarioWare
//  Twisted, Koro Koro Puzzle). The solar sensor (Boktai) is driven by the
//  brightness slider overlay in the game view, not by the ambient light sensor.
//

import Foundation
import CoreMotion

final class SensorBridge {
    /// tiltX, tiltY in g (−1…1), gyroZ normalised (−1…1 ≈ ±1 turn/s).
    var onTilt: ((Float, Float, Float) -> Void)?

    private let motion = CMMotionManager()
    private let queue = OperationQueue()
    private(set) var isActive = false

    init() {
        queue.name = "com.redfernsoutpost.tinbox.motion"
        queue.maxConcurrentOperationCount = 1
    }

    func start() {
        guard !isActive, motion.isDeviceMotionAvailable else { return }
        isActive = true
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            // Gravity vector gives tilt; holding the phone flat == neutral.
            let g = data.gravity
            let tiltX = Float(g.x)           // roll left/right
            let tiltY = Float(-g.y)          // pitch forward/back
            // Rotation around the screen normal, in turns per second.
            let gyroZ = Float(data.rotationRate.z / (2 * Double.pi))
            self.onTilt?(tiltX, tiltY, gyroZ)
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        motion.stopDeviceMotionUpdates()
        onTilt?(0, 0, 0)
    }
}
