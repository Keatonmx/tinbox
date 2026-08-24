//
//  EmulatorSession.swift
//  Tinbox
//
//  Owns one GBAEmulatorCore and drives it from a dedicated thread with a
//  CADisplayLink pinned to 60 Hz. One `runFrame` per tick at 1×; the speed
//  accumulator runs more (fast-forward) or fewer (slow motion) frames per tick.
//
//  Thread safety: every call into the core goes through `EmulationRunner.lock`.
//  The Metal renderer never touches the core — it reads from `FrameStore`,
//  which the emulation thread publishes into after each frame.
//

import Foundation
import QuartzCore
import UIKit
import Combine

// MARK: - FrameStore

/// Latest completed frame, shared between the emulation thread (writer) and
/// the Metal renderer (reader).
final class FrameStore: @unchecked Sendable {
    private(set) var width: Int
    private(set) var height: Int
    private let lock = NSLock()
    private var pixels: UnsafeMutablePointer<UInt32>
    private var frameIndex: UInt64 = 0

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = .allocate(capacity: width * height)
        pixels.initialize(repeating: 0xFF000000, count: width * height)
    }

    deinit { pixels.deallocate() }

    /// Switches to a new frame size (GBA 240×160 ↔ GB 160×144). Reallocates
    /// under the lock so a concurrent reader never sees a mismatched buffer.
    func resize(width newWidth: Int, height newHeight: Int) {
        lock.lock()
        if newWidth != width || newHeight != height {
            pixels.deallocate()
            pixels = .allocate(capacity: newWidth * newHeight)
            pixels.initialize(repeating: 0xFF000000, count: newWidth * newHeight)
            width = newWidth
            height = newHeight
            frameIndex &+= 1
        }
        lock.unlock()
    }

    func publish(from source: UnsafePointer<UInt32>) {
        lock.lock()
        pixels.update(from: source, count: width * height)
        frameIndex &+= 1
        lock.unlock()
    }

    /// Calls `body` with the pixel buffer while holding the lock and returns the
    /// frame index so callers can skip redundant texture uploads.
    @discardableResult
    func read(_ body: (UnsafePointer<UInt32>, Int, Int) -> Void) -> UInt64 {
        lock.lock()
        body(pixels, width, height)
        let index = frameIndex
        lock.unlock()
        return index
    }

    var latestFrameIndex: UInt64 {
        lock.lock(); defer { lock.unlock() }
        return frameIndex
    }

    func snapshot() -> Data {
        lock.lock(); defer { lock.unlock() }
        return Data(bytes: pixels, count: width * height * 4)
    }
}

// MARK: - EmulationRunner (emulation thread side)

/// Everything the emulation thread touches. Not main-actor isolated on purpose.
final class EmulationRunner: NSObject, @unchecked Sendable {
    let core: GBAEmulatorCore
    let lock = NSLock()
    let frameStore: FrameStore
    let audio: AudioEngine
    let haptics = RumbleHaptics()

    // Written from the main thread, read on the emulation thread. Individual
    // word-sized writes; torn reads are harmless here.
    var running = false
    var paused = false
    /// Speed chosen in the menu (1 when fast-forward is off).
    var speed: Double = 1
    /// Momentary speed while the » button is held and slid right (0 = none).
    var holdSpeed: Double = 0
    /// Live rewind rate while the » button is held and slid left (snapshots per tick, 0 = none).
    var holdRewind: Double = 0
    var touchKeys: GBAKeyMask = []
    var controllerKeys: GBAKeyMask = []
    var turboA = false
    var turboB = false

    private var accumulator: Double = 0
    private var frameTick: UInt64 = 0
    private var lastTimestamp: CFTimeInterval = 0
    private var wasSilent = false

    init(core: GBAEmulatorCore, frameStore: FrameStore, audio: AudioEngine) {
        self.core = core
        self.frameStore = frameStore
        self.audio = audio
        super.init()
        core.delegate = self
    }

    func resetTiming() {
        accumulator = 0
        frameTick = 0
        lastTimestamp = 0
        touchKeys = []
        holdSpeed = 0
        holdRewind = 0
    }

    /// Serialised access to the core.
    @discardableResult
    func withCore<T>(_ body: (GBAEmulatorCore) throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body(core)
    }

    /// Effective speed right now (menu speed unless the scrubber overrides it).
    var effectiveSpeed: Double { holdSpeed > 0 ? holdSpeed : speed }

    /// Called on the emulation thread at 60 Hz with the display link timestamp.
    func tick(timestamp: CFTimeInterval) {
        guard running, !paused else { lastTimestamp = 0; return }

        // Live rewind while the scrubber is held to the left.
        if holdRewind > 0 {
            lock.lock()
            // Rewind snapshots are taken every 2 frames, so 2 frames per step.
            if core.rewind(frames: UInt(max(1, holdRewind) * 2)) {
                frameStore.publish(from: core.videoBuffer)
            }
            core.clearAudio()
            lock.unlock()
            audio.reset()
            wasSilent = true
            lastTimestamp = 0
            return
        }

        // Pace against real time so a dropped display-link frame is caught up
        // rather than slowing the game; at a steady 60 Hz this is exactly one
        // frame per tick. Audio drift (59.73 vs 60 Hz) is absorbed by the
        // audio engine's rate control, not here.
        let elapsed = lastTimestamp > 0 ? min(timestamp - lastTimestamp, 0.05) : (1.0 / 60.0)
        lastTimestamp = timestamp
        let currentSpeed = effectiveSpeed
        accumulator += elapsed * 60.0 * currentSpeed

        // Audio is only meaningful at 1×.
        let silent = currentSpeed != 1
        if silent != wasSilent {
            audio.reset()
            wasSilent = silent
        }

        let budgetEnd = CACurrentMediaTime() + 0.0145
        var framesRun = 0
        lock.lock()
        while accumulator >= 1 {
            var keys = GBAKeyMask(rawValue: touchKeys.rawValue | controllerKeys.rawValue)
            frameTick &+= 1
            // Turbo: ~15 presses/s (4-frame period) while the button is held.
            let turboPhase = (frameTick / 2) % 2 == 1
            if turboA, keys.contains(.a), turboPhase { keys.remove(.a) }
            if turboB, keys.contains(.b), turboPhase { keys.remove(.b) }
            core.setKeys(keys)
            core.runFrame()
            accumulator -= 1
            framesRun += 1
            if silent {
                core.clearAudio()
            } else {
                drainAudioLocked()
            }
            if CACurrentMediaTime() > budgetEnd {
                // Can't keep up with the requested speed this tick; cap the backlog.
                accumulator = min(accumulator, 1)
                break
            }
        }
        if framesRun > 0 {
            frameStore.publish(from: core.videoBuffer)
        }
        lock.unlock()
    }

    /// Moves whatever the core produced this frame into the audio ring buffer.
    private func drainAudioLocked() {
        audio.sourceRate = Double(core.audioSampleRate)
        let available = Int(core.availableAudioFrames())
        guard available > 0 else { return }
        audio.ring.write(maxFrames: available) { dst, capacity in
            Int(core.readAudioFrames(dst, count: UInt(capacity)))
        }
        // Whatever did not fit (buffer full) is discarded on the core side.
        if core.availableAudioFrames() > 0 {
            core.clearAudio()
        }
    }
}

extension EmulationRunner: GBAEmulatorCoreDelegate {
    func emulatorCore(_ core: GBAEmulatorCore, rumbleIntensity intensity: Float) {
        haptics.rumble(intensity: intensity)
    }

    func emulatorCoreDidUpdateSaveData(_ core: GBAEmulatorCore) {
        CloudSync.shared.markDirty()
    }
}

// MARK: - EmulatorSession (main thread API)

/// What the » scrubber is currently doing, for the on-screen badge.
enum ScrubState: Equatable {
    case none
    case fastForward(Double)
    case rewind(Double)

    var label: String? {
        switch self {
        case .none: return nil
        case .fastForward(let s): return "▶▶ \(SpeedSteps.label((s * 10).rounded() / 10))"
        case .rewind(let r): return "◀◀ \(SpeedSteps.label((r * 10).rounded() / 10))"
        }
    }
}

/// Main-thread only (not actor-annotated so plain closures can call it in Swift 5 mode).
final class EmulatorSession: ObservableObject {

    @Published private(set) var game: Game?
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    /// "Permanent" fast-forward from the Quick Menu / Settings.
    @Published var isFastForward = false { didSet { syncSpeed() } }
    @Published var ffSpeed: Double = 3 { didSet { syncSpeed() } }
    @Published var turboA = false { didSet { runner.turboA = turboA } }
    @Published var turboB = false { didSet { runner.turboB = turboB } }
    @Published private(set) var cartridgeHardware: TinboxCartHardware = []
    @Published private(set) var platform: TinboxPlatform = .gba
    /// Width ÷ height of the emulated screen (3:2 GBA, 10:9 GB).
    @Published private(set) var videoAspect: CGFloat = 1.5
    @Published private(set) var controllerConnected = false
    @Published var luminanceLevel: Int = 0 { didSet { runner.withCore { $0.applyLuminanceLevel(luminanceLevel) } } }
    /// Momentary state of the » scrubber.
    @Published private(set) var scrub: ScrubState = .none
    /// The boot "lid-open" animation plays once per game load (not on
    /// rotation or when a menu closes). Deliberately not published.
    var lidShown = false

    /// Effective speed (1 when fast-forward is off).
    var currentSpeed: Double { isFastForward ? ffSpeed : 1 }
    /// Badge text: scrubber state wins over the permanent FF badge.
    var speedBadgeLabel: String? {
        if let s = scrub.label { return s }
        return isFastForward ? "» \(SpeedSteps.label(ffSpeed))" : nil
    }

    let runner: EmulationRunner
    var frameStore: FrameStore { runner.frameStore }
    var audio: AudioEngine { runner.audio }
    let sensors = SensorBridge()
    private let thread: EmulationThread
    private var cancellables = Set<AnyCancellable>()

    var settings: AppSettings { didSet { applySettings() } }

    init(settings: AppSettings) {
        self.settings = settings
        FileLocations.createAll()
        guard let core = GBAEmulatorCore(saveDirectory: FileLocations.saves,
                                         stateDirectory: FileLocations.states,
                                         screenshotDirectory: FileLocations.screenshots) else {
            fatalError("libmgba failed to initialise")
        }
        let store = FrameStore(width: Int(core.videoWidth), height: Int(core.videoHeight))
        let audio = AudioEngine(sampleRate: Double(core.audioSampleRate))
        runner = EmulationRunner(core: core, frameStore: store, audio: audio)
        thread = EmulationThread()

        let runner = self.runner
        thread.tick = { timestamp in runner.tick(timestamp: timestamp) }
        thread.start()

        ControllerManager.shared.onKeysChanged = { [weak runner] mask in runner?.controllerKeys = mask }
        ControllerManager.shared.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in self?.controllerConnected = connected }
            .store(in: &cancellables)

        sensors.onTilt = { [weak self] x, y, z in
            guard let self, self.settings.sensorsEnabled else { return }
            self.runner.withCore { $0.setTilt(x: x, y: y, gyroZ: z) }
        }
        applySettings()
    }

    // MARK: Lifecycle

    func load(_ game: Game, cheats: [Cheat]) throws {
        stop()
        lidShown = false
        try runner.withCore { core in
            try core.loadROM(at: game.romURL)
        }

        // Patch (IPS/UPS/BPS) is applied in memory on every boot; the ROM file stays pristine.
        if let patch = game.patchFileName {
            let url = FileLocations.patches.appendingPathComponent(patch)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = runner.withCore { $0.applyPatch(at: url) }
            }
        }

        self.game = game
        let (hardware, platform, width, height) = runner.withCore {
            ($0.cartridgeHardware, $0.platform, Int($0.videoWidth), Int($0.videoHeight))
        }
        cartridgeHardware = hardware
        self.platform = platform
        frameStore.resize(width: width, height: height)
        videoAspect = CGFloat(width) / CGFloat(height)
        applyCheats(cheats)
        applySettings()
        runner.resetTiming()
        scrub = .none
        if settings.sensorsEnabled, cartridgeHardware.contains(.tilt) || cartridgeHardware.contains(.gyro) {
            sensors.start()
        }
    }

    func start() {
        guard game != nil else { return }
        isRunning = true
        isPaused = false
        runner.paused = false
        runner.running = true
        audio.start(mixWithOthers: settings.backgroundAudioMixing)
        syncSpeed()
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        isPaused = true
        runner.paused = true
        setScrub(offset: nil)
        audio.pause()
    }

    func resume() {
        guard isRunning, isPaused else { return }
        isPaused = false
        runner.withCore { $0.clearAudio() }
        audio.reset()
        runner.paused = false
        audio.start(mixWithOthers: settings.backgroundAudioMixing)
    }

    /// Stops emulation and unloads the ROM (the core flushes the battery save).
    func stop() {
        runner.running = false
        runner.paused = false
        isRunning = false
        isPaused = false
        isFastForward = false
        scrub = .none
        audio.stop()
        sensors.stop()
        runner.withCore { $0.unloadROM() }
        game = nil
        cartridgeHardware = []
    }

    // MARK: Input

    func setTouchKeys(_ mask: GBAKeyMask) {
        runner.touchKeys = mask
    }

    /// Hold-and-slide on the » button. `offset` is the horizontal drag in points
    /// (nil when released): right = momentary fast-forward up to the menu speed,
    /// left = live rewind. Release returns to the permanent setting.
    func setScrub(offset: CGFloat?) {
        guard let offset else {
            if runner.holdSpeed != 0 || runner.holdRewind != 0 {
                runner.holdSpeed = 0
                runner.holdRewind = 0
                runner.withCore { $0.clearAudio() }
                audio.reset()
            }
            if scrub != .none { scrub = .none }
            return
        }
        let dead: CGFloat = 10
        let span: CGFloat = 90
        if offset > dead {
            let t = Double(min(1, (offset - dead) / span))
            let top = max(2, ffSpeed)
            let speed = 1 + t * (top - 1)
            runner.holdRewind = 0
            runner.holdSpeed = speed
            scrub = .fastForward(speed)
        } else if offset < -dead, settings.rewindEnabled, !settings.raHardcore {
            let t = Double(min(1, (-offset - dead) / span))
            let rate = 0.5 + t * 3.5           // 0.5× … 4× rewind
            runner.holdSpeed = 0
            runner.holdRewind = rate
            scrub = .rewind(rate)
        } else {
            runner.holdSpeed = 0
            runner.holdRewind = 0
            if scrub != .none { scrub = .none }
        }
    }

    // MARK: Save states

    /// Writes slot `index` (0 == Auto) plus a PNG thumbnail next to it.
    func saveState(slot index: Int) -> Bool {
        guard let game else { return false }
        let url = FileLocations.stateFile(gameID: game.id, slot: index)
        let (ok, pixels) = runner.withCore { core -> (Bool, Data) in
            (core.saveState(to: url), core.copyFramebuffer())
        }
        if ok {
            let w = frameStore.width, h = frameStore.height, id = game.id
            DispatchQueue.global(qos: .utility).async {
                GameLibraryStore.shared.writeThumbnail(pixels, width: w, height: h, gameID: id, slot: index)
            }
        }
        return ok
    }

    func loadState(slot index: Int) -> Bool {
        guard let game else { return false }
        return loadState(from: FileLocations.stateFile(gameID: game.id, slot: index))
    }

    func loadState(from url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let ok = runner.withCore { $0.loadState(from: url) }
        if ok { audio.reset() }
        return ok
    }

    /// Emergency state written on resign-active / incoming call.
    func writeSuspendState() {
        guard let game, isRunning else { return }
        _ = runner.withCore { $0.saveState(to: FileLocations.suspendState(gameID: game.id)) }
    }

    func flushSaveData() {
        runner.withCore { $0.flushSaveData() }
    }

    // MARK: Rewind

    func rewind(seconds: Double) -> Bool {
        let frames = UInt(max(1, seconds * 60))
        let ok = runner.withCore { $0.rewind(frames: frames) }
        if ok { audio.reset() }
        return ok
    }

    // MARK: Cheats

    func applyCheats(_ cheats: [Cheat]) {
        guard game != nil else { return }
        let payload: [[String: Any]] = cheats.map {
            ["name": $0.name, "code": $0.code, "type": $0.type.rawValue, "enabled": $0.enabled]
        }
        runner.withCore { _ = $0.setCheats(payload) }
    }

    func setCheat(at index: Int, enabled: Bool) {
        runner.withCore { $0.setCheat(at: UInt(index), enabled: enabled) }
    }

    // MARK: Settings → core

    private func applySettings() {
        if ffSpeed != settings.ffSpeed { ffSpeed = settings.ffSpeed }
        if turboA != settings.turboA { turboA = settings.turboA }
        if turboB != settings.turboB { turboB = settings.turboB }
        runner.haptics.enabled = settings.hapticsEnabled
        runner.withCore { core in
            core.setRewind(enabled: settings.rewindEnabled, seconds: UInt(settings.rewindSeconds), frameInterval: 2)
            if settings.bootMode == .biosFile, let name = settings.biosFileName {
                _ = core.setBIOSFile(FileLocations.bios.appendingPathComponent(name))
            } else {
                _ = core.setBIOSFile(nil)
            }
        }
        if !settings.sensorsEnabled { sensors.stop() }
        audio.setMixWithOthers(settings.backgroundAudioMixing)
        audio.volume = Float(settings.volume) / 100
    }

    private func syncSpeed() {
        runner.speed = currentSpeed
    }
}

// MARK: - Emulation thread

/// A thread whose run loop hosts the CADisplayLink that paces emulation.
final class EmulationThread: Thread {
    var tick: ((CFTimeInterval) -> Void)?
    private var displayLink: CADisplayLink?

    override init() {
        super.init()
        name = "com.redfernsoutpost.tinbox.emulation"
        qualityOfService = .userInteractive
    }

    override func main() {
        let link = CADisplayLink(target: self, selector: #selector(onDisplayLink(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        link.add(to: .current, forMode: .common)
        displayLink = link
        while !isCancelled {
            RunLoop.current.run(mode: .default, before: .distantFuture)
        }
        link.invalidate()
    }

    @objc private func onDisplayLink(_ link: CADisplayLink) {
        tick?(link.timestamp)
    }
}
