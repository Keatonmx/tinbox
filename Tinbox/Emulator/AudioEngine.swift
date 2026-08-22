//
//  AudioEngine.swift
//  Tinbox
//
//  AVAudioEngine + AVAudioSourceNode pulling 32768 Hz stereo int16 from a
//  lock-free single-producer / single-consumer ring buffer that the emulation
//  thread fills after every frame.
//

import AVFoundation
import os

/// Interleaved stereo int16 SPSC ring buffer (frames, not samples).
final class AudioRingBuffer: @unchecked Sendable {
    private let capacityFrames: Int
    private let storage: UnsafeMutablePointer<Int16>
    private var head: Int = 0   // write index (frames) — producer only
    private var tail: Int = 0   // read index (frames)  — consumer only
    private let lock = os_unfair_lock_t.allocate(capacity: 1)

    init(capacityFrames: Int) {
        self.capacityFrames = capacityFrames
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
        os_unfair_lock_unlock(lock)
    }

    /// Producer. `fill` receives a contiguous destination and its capacity in
    /// frames and returns how many frames it wrote. Called twice if the free
    /// region wraps.
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

    /// Consumer. Fills `frames` frames into `out`; zero-fills on underrun.
    func read(into out: UnsafeMutablePointer<Int16>, frames: Int) -> Int {
        os_unfair_lock_lock(lock)
        let available = head - tail
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
        return copied
    }
}

final class AudioEngine: @unchecked Sendable {
    let sampleRate: Double
    let ring: AudioRingBuffer
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var mixWithOthers = false
    private var isRunning = false

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        ring = AudioRingBuffer(capacityFrames: Int(sampleRate) / 4) // 250 ms of headroom
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 2, interleaved: true)!
        let ring = self.ring
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let buffer = abl.first, let data = buffer.mData else { return noErr }
            let out = data.assumingMemoryBound(to: Int16.self)
            _ = ring.read(into: out, frames: Int(frameCount))
            return noErr
        }
        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
        configureSession(mixWithOthers: false)

        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            if type == .ended, self.isRunning {
                try? self.engine.start()
            }
        }
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, self.isRunning else { return }
            try? self.engine.start()
        }
    }

    private func configureSession(mixWithOthers: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            if mixWithOthers {
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            } else {
                try session.setCategory(.playback, mode: .default, options: [])
            }
            try session.setPreferredIOBufferDuration(0.005)
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
