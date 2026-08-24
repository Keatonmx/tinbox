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
    static var letterGreeting: String { sanitized ? "Dear Player," : "Dear Villager," }
    static var letterBody: String { sanitized ? "The last session ended abruptly. Your spot was saved."
                                              : "I am very upset right now… but your spot was saved." }
    static var letterSignature: String { sanitized ? "From Tinbox" : "From Resetti" }
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
                    .font(.system(size: 17, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
                    .shadow(color: .black, radius: 0, x: 1.5, y: 1.5)
                    .opacity(dotOn ? 1 : 0.55)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(12)
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

// MARK: - The letter (abrupt-exit recovery)

/// Animal Crossing stationery: torn spiral edge, greeting, body, signature.
/// Shown on the next boot after the app died mid-session. Tap to dismiss.
struct ResettiLetter: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(EggText.letterGreeting)
                .padding(.top, 26)
            Text(EggText.letterBody)
                .padding(.top, 30)
                .padding(.trailing, 26)
                .lineSpacing(4)
            Text(EggText.letterSignature)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 34)
                .padding(.trailing, 26)
                .padding(.bottom, 26)
        }
        .font(.system(size: 16, weight: .semibold, design: .rounded))
        .foregroundColor(Color(hex: 0x6E6E73))
        .padding(.leading, 52)
        .frame(maxWidth: 380, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xFCFBF7), Color(hex: 0xF1F0EC)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        // Torn spiral holes punched out of the left margin.
        .overlay(alignment: .leading) {
            VStack(spacing: 18) {
                ForEach(0..<7, id: \.self) { i in
                    Circle()
                        .frame(width: 13, height: 13)
                        .offset(x: i % 2 == 0 ? 0 : -3)
                }
            }
            .padding(.leading, 14)
            .blendMode(.destinationOut)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.45), radius: 16, y: 10)
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Animal Crossing style system bubble

/// The dialogue bubble from the reference: striped border, dotted dark blob,
/// green name tag, continue triangle. Tap to dismiss.
struct SystemBubble: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Striped border blob.
            RoundedRectangle(cornerRadius: 46, style: .continuous)
                .fill(.clear)
                .background(StripePattern().clipShape(RoundedRectangle(cornerRadius: 46, style: .continuous)))
            // Dark dotted interior.
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(Color(hex: 0x3E3E44))
                .overlay(DotPattern().clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous)))
                .padding(9)
            Text(text)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineSpacing(3)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 26)
                .padding(.top, 30)
                .padding(.bottom, 30)
            // Continue triangle.
            Triangle()
                .fill(Color(hex: 0xF2DCAF))
                .frame(width: 14, height: 10)
                .rotationEffect(.degrees(180))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(22)
        }
        .frame(maxWidth: 380)
        .fixedSize(horizontal: false, vertical: true)
        // Green name tag riding the top edge (black text, pale ring, like the
        // reference asset).
        .overlay(alignment: .topLeading) {
            Text("System")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(.black.opacity(0.82))
                .padding(.horizontal, 22)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(LinearGradient(colors: [Color(hex: 0x4FE03F), Color(hex: 0x2FC42B)],
                                                  startPoint: .top, endPoint: .bottom)))
                .overlay(Capsule().stroke(Color(hex: 0xFBF4E4), lineWidth: 3))
                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                .offset(x: 10, y: -16)
        }
        .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }
}

/// Diagonal cream candy stripes (the bubble's border).
private struct StripePattern: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 16
            var x: CGFloat = -size.height
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0xFBF4E4)))
            while x < size.width + size.height {
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + size.height, y: 0))
                p.addLine(to: CGPoint(x: x + size.height + step * 0.55, y: 0))
                p.addLine(to: CGPoint(x: x + step * 0.55, y: size.height))
                p.closeSubpath()
                ctx.fill(p, with: .color(Color(hex: 0xF0D9A8)))
                x += step
            }
        }
    }
}

/// The faint polka-dot grid inside the bubble.
private struct DotPattern: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 15
            var row = 0
            var y: CGFloat = 6
            while y < size.height {
                var x: CGFloat = row % 2 == 0 ? 6 : 6 + step / 2
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 3.4, height: 3.4)),
                             with: .color(Color(hex: 0x35353B)))
                    x += step
                }
                y += step
                row += 1
            }
        }
    }
}

// MARK: - Glitch texture for the empty-library import tile

/// Deterministic MissingNo.-style glitch: banded horizontal runs in the
/// sprite's lavender/purple/peach/black palette. `lShape` carves out the
/// top-left quadrant like the real sprite; `palette` can be hue-tinted so
/// every coverless game glitches in its own colour.
struct GlitchTexture: View {
    var palette: [Color] = GlitchTexture.missingNo
    var lShape = false
    var seed: UInt64 = 0x1F3B

    /// The sprite's colours: pale lavender, purple, peach, near-black.
    static let missingNo: [Color] = [
        Color(hex: 0xF4ECF6), Color(hex: 0x9187B0), Color(hex: 0xEFB58A), Color(hex: 0x18121A),
    ]

    /// Same DNA, tinted by a game's hue (light, mid, signature peach, black).
    static func tinted(hue: Double) -> [Color] {
        [Color(hue: hue / 360, saturation: 0.10, brightness: 0.94),
         Color(hue: hue / 360, saturation: 0.32, brightness: 0.60),
         Color(hex: 0xEFB58A),
         Color(hex: 0x18121A)]
    }

    var body: some View {
        Canvas { ctx, size in
            var s = seed
            func rand() -> CGFloat {
                s = s &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat((s >> 33) & 0xFFFF) / 65_535
            }
            let cols = 14
            let cw = size.width / CGFloat(cols)
            let rows = max(1, Int(size.height / cw))
            let ch = size.height / CGFloat(rows)
            for r in 0..<rows {
                var c = 0
                while c < cols {
                    let run = 1 + Int(rand() * 3)
                    let v = rand()
                    // Weighted like the sprite: mostly light, then purple,
                    // peach bands, rare black dashes.
                    let color: Color = v < 0.44 ? palette[0] : v < 0.76 ? palette[1] : v < 0.90 ? palette[2] : palette[3]
                    for i in 0..<run where c + i < cols {
                        let col = c + i
                        // The inverted-L: top-left quadrant stays empty.
                        if lShape, col < cols * 2 / 5, r < rows * 5 / 11 { continue }
                        ctx.fill(Path(CGRect(x: CGFloat(col) * cw, y: CGFloat(r) * ch,
                                             width: cw + 0.5, height: ch + 0.5)),
                                 with: .color(color))
                    }
                    c += run
                }
            }
        }
        .allowsHitTesting(false)
    }
}
