//
//  RevisionXEggs.swift
//  Tinbox
//
//  The easter-egg batch: little nods to the games this thing exists for.
//  All flavour text lives in EggText with a single `sanitized` switch — if
//  App Store review ever objects to a reference, flip it and every egg keeps
//  working with generic wording.
//

import SwiftUI
import AVFoundation

// MARK: - Flavour text (single kill-switch)

enum EggText {
    /// Flip to true for a reference-free App Store submission build.
    static let sanitized = false

    static var saving: String { "SAVING… DON'T TURN OFF THE POWER" }
    static var hurryUp: String { "HURRY UP!" }
    static var secretTheme: String { sanitized ? "X" : "SA-X" }
    static var secretToast: String { sanitized ? "Hidden theme unlocked" : "SA-X has found you · new theme unlocked" }
    static var glitchCaption: String { sanitized ? "" : "MISSINGNO." }
    static var abruptExit: String { sanitized ? "ERR · last session ended abruptly. Your spot was saved."
                                              : "Resetti would be very upset right now. Your spot was saved." }
}

// MARK: - Synthesized retro chirp (no bundled assets)

/// Plays the bundled unlock sound (EasterEggClick5.mp3); falls back to a
/// synthesized square-wave arpeggio. Used only by easter eggs; the rest of
/// the UI stays silent on purpose.
enum RetroChirp {
    private static var player: AVAudioPlayer?

    static func play() {
        let url: URL
        if let bundled = Bundle.main.url(forResource: "EasterEggClick5", withExtension: "mp3") {
            url = bundled
        } else {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("tinbox-chirp.wav")
            if !FileManager.default.fileExists(atPath: tmp.path) {
                try? makeWAV().write(to: tmp)
            }
            url = tmp
        }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = 0.7
        player?.play()
    }

    private static func makeWAV() -> Data {
        let rate = 22_050
        let notes: [(hz: Double, s: Double)] = [(659.3, 0.07), (830.6, 0.07), (1108.7, 0.07), (1318.5, 0.16)]
        var samples: [Int16] = []
        for note in notes {
            let n = Int(Double(rate) * note.s)
            for i in 0..<n {
                let t = Double(i) / Double(rate)
                let square: Double = sin(2 * .pi * note.hz * t) >= 0 ? 1 : -1
                let env = min(1, Double(n - i) / (Double(rate) * 0.02))   // declick
                samples.append(Int16(square * env * 0.24 * 32767))
            }
        }
        var data = Data()
        func put(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func put16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let byteCount = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); put(36 + byteCount)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); put(16); put16(1); put16(1)
        put(UInt32(rate)); put(UInt32(rate * 2)); put16(2); put16(16)
        data.append(contentsOf: Array("data".utf8)); put(byteCount)
        samples.withUnsafeBufferPointer { data.append(UnsafeBufferPointer(start: UnsafeRawPointer($0.baseAddress!).assumingMemoryBound(to: UInt8.self), count: samples.count * 2)) }
        return data
    }
}

// MARK: - In-game screen overlays (save flash, Zzz, boost streaks)

/// One overlay for the screen band: battery-save flash, paused Zzz, FF streaks.
struct EggScreenOverlays: View {
    @EnvironmentObject private var session: EmulatorSession
    @State private var savingVisible = false
    @State private var dotOn = false
    @State private var streaks = false
    @State private var zzz = false

    var body: some View {
        ZStack {
            // F-Zero boost streaks along the edges when fast-forward engages.
            if streaks {
                BoostStreaks()
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
            // "SAVING…" flash whenever the game writes its battery save.
            if savingVisible {
                HStack(spacing: 5) {
                    Circle().fill(dotOn ? Color(hex: 0x58CC52) : Color(hex: 0x2A5C28))
                        .frame(width: 6, height: 6)
                    Text(EggText.saving)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.92))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.black.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(14)
                .transition(.opacity)
                .allowsHitTesting(false)
            }
            // Sleeping while paused in a menu.
            if zzz {
                Text("Zzz…")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                    .opacity(dotOn ? 0.9 : 0.4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(14)
                    .allowsHitTesting(false)
            }
        }
        .onReceive(Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()) { _ in
            if savingVisible || zzz { dotOn.toggle() }
        }
        .onChange(of: session.saveFlash) { _ in
            withAnimation(.easeIn(duration: 0.1)) { savingVisible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation(.easeOut(duration: 0.4)) { savingVisible = false }
            }
        }
        .onChange(of: session.isPaused) { paused in
            withAnimation(.easeInOut(duration: 0.3)) { zzz = paused && session.isRunning }
        }
        .onChange(of: session.isFastForward) { on in
            guard on else { return }
            withAnimation(.easeOut(duration: 0.12)) { streaks = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation(.easeIn(duration: 0.25)) { streaks = false }
            }
        }
    }
}

/// Horizontal blue speed lines near the top and bottom edges.
private struct BoostStreaks: View {
    @State private var offset: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ForEach(0..<6, id: \.self) { i in
                Capsule()
                    .fill(LinearGradient(colors: [.clear, Color(hex: 0x59B7FF).opacity(0.85), .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: w * 0.4, height: 2)
                    .position(x: w * (offset + CGFloat(i) * 0.18),
                              y: i % 2 == 0 ? geo.size.height * (0.06 + CGFloat(i) * 0.03)
                                            : geo.size.height * (0.94 - CGFloat(i) * 0.03))
            }
        }
        .onAppear {
            offset = -0.6
            withAnimation(.easeOut(duration: 0.55)) { offset = 1.4 }
        }
    }
}

// MARK: - Ambient eggs (battery warning, midnight mode)

/// Lives at the root: watches the battery and the clock.
struct EggAmbient: View {
    @State private var hurryVisible = false
    @State private var hurryShown = false
    @State private var midnight = false
    @State private var batFlying = false

    var body: some View {
        ZStack {
            if midnight {
                Color(hex: 0x8B0000).opacity(0.07)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                if batFlying { PixelBat() }
            }
            if hurryVisible {
                Text(EggText.hurryUp)
                    .font(.system(size: 30, weight: .black, design: .monospaced))
                    .foregroundColor(Color(hex: 0xFFD23F))
                    .shadow(color: .black, radius: 0, x: 3, y: 3)
                    .rotationEffect(.degrees(-4))
                    .transition(.scale(scale: 2.2).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            checkBattery()
            let hour = Calendar.current.component(.hour, from: Date())
            if hour == 0 {
                midnight = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { batFlying = true }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            checkBattery()
        }
    }

    private func checkBattery() {
        let level = UIDevice.current.batteryLevel
        guard !hurryShown, level > 0, level <= 0.10, UIDevice.current.batteryState == .unplugged else { return }
        hurryShown = true
        withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) { hurryVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeOut(duration: 0.3)) { hurryVisible = false }
        }
    }
}

/// A tiny bat that flaps once across the top of the screen after midnight.
private struct PixelBat: View {
    @State private var x: CGFloat = -0.1
    @State private var flap = false

    var body: some View {
        GeometryReader { geo in
            batShape
                .position(x: geo.size.width * x,
                          y: geo.safeAreaInsets.top + 30 + sin(x * 14) * 8)
                .onAppear {
                    withAnimation(.linear(duration: 4.5)) { x = 1.12 }
                }
                .onReceive(Timer.publish(every: 0.14, on: .main, in: .common).autoconnect()) { _ in
                    flap.toggle()
                }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var batShape: some View {
        HStack(spacing: 1) {
            Triangle().fill(Color(hex: 0x4A1E2A))
                .frame(width: 8, height: flap ? 4 : 7)
                .rotationEffect(.degrees(flap ? -18 : 6))
            RoundedRectangle(cornerRadius: 1.5).fill(Color(hex: 0x3A1620)).frame(width: 5, height: 5)
            Triangle().fill(Color(hex: 0x4A1E2A))
                .frame(width: 8, height: flap ? 4 : 7)
                .rotationEffect(.degrees(flap ? 18 : -6))
        }
        .opacity(0.8)
    }
}

// MARK: - Glitch texture for the empty-library import tile

/// Deterministic pseudo-random glitch blocks, MissingNo. style.
struct GlitchTexture: View {
    var body: some View {
        Canvas { ctx, size in
            var seed: UInt64 = 0x1F3B
            func rand() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat((seed >> 33) & 0xFFFF) / 65_535
            }
            let cols = 12, rows = 9
            let cw = size.width / CGFloat(cols)
            let ch = size.height / CGFloat(rows)
            for r in 0..<rows {
                for c in 0..<cols {
                    let v = rand()
                    guard v > 0.55 else { continue }
                    let shade = v > 0.9 ? 0.30 : (v > 0.75 ? 0.16 : 0.08)
                    ctx.fill(Path(CGRect(x: CGFloat(c) * cw, y: CGFloat(r) * ch,
                                         width: cw * (v > 0.8 ? 2 : 1), height: ch)),
                             with: .color(.white.opacity(shade)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
