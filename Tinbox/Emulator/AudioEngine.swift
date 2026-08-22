//
//  AudioEngine.swift
//  Tinbox
//
//  AVAudioEngine graph:  source node (32768 Hz stereo int16) → varispeed → mixer
//
//  The emulation thread pushes every frame's samples into a ring buffer; the
//  audio thread pulls from it. Two things keep that glitch-free:
//
//  • Priming — after any reset the output stays silent until ~60 ms of audio
//    has accumulated, so normal scheduling jitter never drains the buffer.
//  • Dynamic rate control — the GBA makes audio at 59.73 fps while the display
//    link runs at 60, so production outruns consumption by ~0.45 %. Rather
//    than dropping chunks, the varispeed rate is nudged (±2 % max, inaudible)
//    to hold the buffer at its target fill level.
//

import AVFoundation
import os

/// Interleaved stereo int16 ring buffer (counts are in frames).
final class AudioRingBuffer: @unchecked Sendable {
    let capacityFrames: Int
    /// Playback stays silent until this many frames are buffered after a reset.
    let primeFrames: Int
    private let storage: UnsafeMutablePointer<Int16>
    private var head: Int = 0   // frames written (producer)
    private var tail: Int = 0   // frames read (consumer)
    private var primed = false
    private let lock = os_unfair_lock_t.allocate(capacity: 1)
    private(set) var underruns = 0

    init(capacityFrames: Int, primeFrames: Int) {
        self.capacityFrames = capacityFrames
        self.primeFrames = primeFrames
        storage = .allocate(capacity: capacityFrames * 2)
        storage.initialize(repeating: 0, count: capacityFrames * 2)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        storage.deallocate()
        lock.deallocate()
    }

    var availableFrames: Int {
        os_unfair_lock_lock(lock); defer { os_unfair_lock_unlock(lock) }
        return head - tail
    }

    func clear() {
        os_unfair_lock_lock(lock)
        head = 0
        tail = 0
        primed = false
        os_unfair_lock_unlock(lock)
    }

    /// Producer. `fill` receives a contiguous destination and its capacity in
    /// frames and returns how many frames it wrote; called again if the free
    /// region wraps. Frames that do not fit are dropped (the caller drains the
    /// core anyway, so nothing piles up on the emulator side).
    func write(maxFrames: Int, _ fill: (UnsafeMutablePointer<Int16>, Int) -> Int) {
        os_unfair_lock_lock(lock)
        var free = capacityFrames - (head - tail)
        os_unfair_lock_unlock(lock)
        var remaining = min(maxFrames, free)
        while remaining > 0 {
            let writeIndex = head % capacityFrames
            let contiguous = min(remaining, capacityFrames - writeIndex)
            let written = fill(storage + writeIndex * 2, contiguous)
            if written <= 0 { break }
            os_unfair_lock_lock(lock)
            head += written
            free = capacityFrames - (head - tail)
            os_unfair_lock_unlock(lock)
            remaining = min(remaining - written, free)
        }
    }

    /// Consumer (audio thread). Fills `frames` frames into `out`; silence while
    /// priming or on underrun.
    func read(into out: UnsafeMutablePointer<Int16>, frames: Int) {
        os_unfair_lock_lock(lock)
        let available = head - tail
        if !primed {
            if available >= primeFrames {
                primed = true
            } else {
                os_unfair_lock_unlock(lock)
                out.update(repeating: 0, count: frames * 2)
                return
            }
        }
        if available < frames {
            // Underrun: output what we have, then re-prime so the next glitch
            // doesn't follow immediately.
            underruns += 1
            primed = false
        }
        os_unfair_lock_unlock(lock)

        let toCopy = min(frames, available)
        var copied = 0
        while copied < toCopy {
            let readIndex = tail % capacityFrames
            let contiguous = min(toCopy - copied, capacityFrames - readIndex)
            (out + copied * 2).update(from: storage + readIndex * 2, count: contiguous * 2)
            copied += contiguous
            os_unfair_lock_lock(lock)
            tail += contiguous
            os_unfair_lock_unlock(lock)
        }
        if copied < frames {
            (out + copied * 2).update(repeating: 0, count: (frames - copied) * 2)
        }
    }
}

final class AudioEngine: @unchecked Sendable {
    let sampleRate: Double
    let ring: AudioRingBuffer
    /// Buffer fill the rate controller steers towards (frames).
    let targetFrames: Int
    private let engine = AVAudioEngine()
    private let varispeed = AVAudioUnitVarispeed()
    private var sourceNode: AVAudioSourceNode?
    private var mixWithOthers = false
    private var isRunning = false
    private var rateUpdateCounter = 0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        targetFrames = Int(sampleRate * 0.06)                                   // 60 ms
        ring = AudioRingBuffer(capacityFrames: Int(sampleRate * 0.5),          // 500 ms headroom
                               primeFrames: targetFrames)
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 2, interleaved: true)!
        let ring = self.ring
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let buffer = abl.first, let data = buffer.mData else { return noErr }
            ring.read(into: data.assumingMemoryBound(to: Int16.self), frames: Int(frameCount))
            return noErr
        }
        sourceNode = node
        engine.attach(node)
        engine.attach(varispeed)
        engine.connect(node, to: varispeed, format: format)
        engine.connect(varispeed, to: engine.mainMixerNode, format: nil)
        engine.mainMixerNode.outputVolume = 1
        varispeed.rate = 1
        configureSession(mixWithOthers: false)

        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            if type == .ended, self.isRunning {
                self.ring.clear()
                try? self.engine.start()
            }
        }
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, self.isRunning else { return }
            self.ring.clear()
            try? self.engine.start()
        }
    }

    /// Called by the emulation thread after each emulated frame. Steers the
    /// playback rate so the buffer hovers around `targetFrames`.
    func updateRateControl() {
        rateUpdateCounter += 1
        guard rateUpdateCounter % 4 == 0 else { return }
        let fill = ring.availableFrames
        let error = Double(fill - targetFrames) / Double(targetFrames)   // -1 … +∞
        let rate = 1.0 + max(-1.0, min(1.0, error)) * 0.02                // ±2 % max
        varispeed.rate = Float(rate)
    }

    private func configureSession(mixWithOthers: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            if mixWithOthers {
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            } else {
                try session.setCategory(.playback, mode: .default, options: [])
            }
            try session.setPreferredSampleRate(48_000)
            try session.setPreferredIOBufferDuration(0.01)
        } catch {
            NSLog("AVAudioSession configuration failed: \(error)")
        }
        self.mixWithOthers = mixWithOthers
    }

    func setMixWithOthers(_ mix: Bool) {
        guard mix != mixWithOthers else { return }
        configureSession(mixWithOthers: mix)
        if isRunning {
            engine.stop()
            ring.clear()
            try? engine.start()
        }
    }

    func start(mixWithOthers: Bool) {
        if mixWithOthers != self.mixWithOthers {
            configureSession(mixWithOthers: mixWithOthers)
        }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning {
                ring.clear()
                varispeed.rate = 1
                try engine.start()
            }
            isRunning = true
        } catch {
            NSLog("AVAudioEngine failed to start: \(error)")
        }
    }

    func pause() {
        isRunning = false
        engine.pause()
        ring.clear()
    }

    func stop() {
        isRunning = false
        engine.stop()
        ring.clear()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
