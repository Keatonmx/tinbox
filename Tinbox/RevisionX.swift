//
//  RevisionX.swift
//  Tinbox
//
//  Revision "X": the feature batch of 2026-08-24, kept in one file.
//    1. Postcard   — renders a shareable framed screenshot of a Time Capsule
//                    moment (pixel-perfect upscale, tin styling, title, date).
//    2. DarkRoomCue — an RPG-style dialog box that appears once when Auto sun
//                    is on but the room is pitch black, pointing at the slider.
//  (The RTC clock-shift and ProMotion changes live in the core bridge and
//  Info.plist; they cannot be Swift.)
//

import SwiftUI
import UIKit
import AVFoundation
import PhotosUI
import CryptoKit

// MARK: - Glass theme backdrop

/// Behind the library when the Glass theme is active: the most recent game's
/// cover, blown up and heavily blurred, so the frosted panels have something
/// to refract. Falls back to soft colour blobs when no art exists.
struct GlassBackdrop: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let game = model.currentGame ?? model.recentGame,
               let cover = GameLibraryStore.shared.coverImage(for: game) {
                GeometryReader { geo in
                    Image(uiImage: cover)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .blur(radius: 55, opaque: true)
                        .saturation(1.35)
                        .overlay(Color.black.opacity(0.28))
                }
            } else {
                // No art anywhere: colour blobs drifting on a slow cycle so the
                // glass always has something alive behind it.
                TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate / 14
                    ZStack {
                        Color(hex: 0x0B0E14)
                        RadialGradient(colors: [Color(hex: 0x2E5C8A).opacity(0.6), .clear],
                                       center: .topLeading, startRadius: 0, endRadius: 500)
                            .offset(x: sin(t) * 70, y: cos(t * 0.7) * 50)
                        RadialGradient(colors: [Color(hex: 0x5A3E8A).opacity(0.5), .clear],
                                       center: .bottomTrailing, startRadius: 0, endRadius: 540)
                            .offset(x: cos(t * 0.9) * 60, y: sin(t * 0.6) * 70)
                        RadialGradient(colors: [Color(hex: 0x1F7A6A).opacity(0.4), .clear],
                                       center: .bottom, startRadius: 0, endRadius: 440)
                            .offset(x: sin(t * 1.2) * 80, y: cos(t) * 30)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Duplicate ROM detection

enum ROMDuplicates {
    /// Title of the library game whose ROM file is byte-identical to `url`,
    /// or nil. Size is compared first so hashing only happens on candidates;
    /// hacks and other revisions differ in content and never match.
    static func existingCopy(of url: URL, in games: [Game]) -> String? {
        // ROMs are picked "open in place": without claiming access every read
        // fails silently and no file ever looks like a duplicate.
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        let sameSize = games.filter { $0.fileSize == Int64(size) }
        guard !sameSize.isEmpty, let incoming = hash(url) else { return nil }
        for game in sameSize where hash(game.romURL) == incoming {
            return game.title
        }
        return nil
    }

    private static func hash(_ url: URL) -> SHA256Digest? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data)
    }
}

// MARK: - 1. Postcards

enum Postcard {
    /// Composes a 1600×1300 postcard PNG and writes it to a temp file the
    /// share sheet can hand out.
    static func make(from imageURL: URL, game: Game, date: Date, playHours: Double?) -> URL? {
        guard let shot = UIImage(contentsOfFile: imageURL.path) else { return nil }
        let canvas = CGSize(width: 1600, height: 1300)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)

        let image = renderer.image { ctx in
            let c = ctx.cgContext
            // Tin background.
            UIColor(red: 0x10 / 255, green: 0x12 / 255, blue: 0x0B / 255, alpha: 1).setFill()
            c.fill(CGRect(origin: .zero, size: canvas))

            // Screenshot: pixel-perfect (nearest neighbour) upscale.
            let scale = min(1360 / shot.size.width, 880 / shot.size.height)
            let shotSize = CGSize(width: shot.size.width * scale, height: shot.size.height * scale)
            let shotRect = CGRect(x: (canvas.width - shotSize.width) / 2, y: 100,
                                  width: shotSize.width, height: shotSize.height)
            let clip = UIBezierPath(roundedRect: shotRect, cornerRadius: 24)
            c.saveGState()
            clip.addClip()
            c.interpolationQuality = .none
            shot.draw(in: shotRect)
            c.restoreGState()
            UIColor.white.withAlphaComponent(0.14).setStroke()
            clip.lineWidth = 3
            clip.stroke()

            // Stamp, title, meta.
            drawStamp(at: CGPoint(x: canvas.width / 2, y: shotRect.maxY + 52))
            let title = game.title as NSString
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 62, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: centered,
            ]
            title.draw(in: CGRect(x: 80, y: shotRect.maxY + 96, width: canvas.width - 160, height: 80), withAttributes: titleAttrs)

            let f = DateFormatter()
            f.dateStyle = .medium
            var meta = f.string(from: date)
            if let playHours, playHours >= 0.5 {
                meta += String(format: " · about %.0f h played", playHours.rounded())
            }
            (meta as NSString).draw(in: CGRect(x: 80, y: shotRect.maxY + 182, width: canvas.width - 160, height: 50),
                                    withAttributes: [
                                        .font: UIFont.systemFont(ofSize: 36, weight: .medium),
                                        .foregroundColor: UIColor(white: 0.92, alpha: 0.45),
                                        .paragraphStyle: centered,
                                    ])
        }

        guard let data = image.pngData() else { return nil }
        let name = "\(Game.makeID(fileName: game.fileName)) Postcard.png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? data.write(to: url, options: .atomic)
        return url
    }

    private static var centered: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        p.lineBreakMode = .byTruncatingTail
        return p
    }

    /// The TINBOX® stamp, centred at `point`.
    private static func drawStamp(at point: CGPoint) {
        let text = "T I N B O X" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 26, weight: .semibold),
            .foregroundColor: UIColor(white: 0.92, alpha: 0.45),
        ]
        let size = text.size(withAttributes: attrs)
        let box = CGRect(x: point.x - size.width / 2 - 22, y: point.y - size.height / 2 - 8,
                         width: size.width + 44, height: size.height + 16)
        let pill = UIBezierPath(roundedRect: box, cornerRadius: box.height / 2)
        UIColor(white: 0.92, alpha: 0.3).setStroke()
        pill.lineWidth = 2.5
        pill.stroke()
        text.draw(at: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), withAttributes: attrs)
        ("®" as NSString).draw(at: CGPoint(x: box.maxX - 16, y: box.minY + 2),
                               withAttributes: [.font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                                                .foregroundColor: UIColor(white: 0.92, alpha: 0.35)])
    }
}

// MARK: - Shrink-wrap sheen for cover art

/// The factory-sealed look: a soft diagonal gloss band, a couple of crease
/// highlights and a corner specular, laid over real covers only. Deterministic
/// per seed so a game's wrap never shimmers between renders.
struct PlasticWrap: View {
    private let bandX: CGFloat
    private let crease1: CGFloat
    private let crease2: CGFloat

    init(seed: UInt64 = 9) {
        var s = seed
        func rand() -> CGFloat {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((s >> 33) & 0xFFFF) / 65_535
        }
        bandX = 0.2 + rand() * 0.35
        crease1 = 0.15 + rand() * 0.3
        crease2 = 0.55 + rand() * 0.3
    }

    @ViewBuilder
    var body: some View {
        // A bundled texture wins outright (add PlasticWrapTexture to the asset
        // catalog and this picks it up); the Canvas below is the fallback.
        if UIImage(named: "PlasticWrapTexture") != nil {
            Image("PlasticWrapTexture")
                .resizable()
                .scaledToFill()
                .blendMode(.screen)
                .clipped()
                .allowsHitTesting(false)
        } else {
            drawnWrap
        }
    }

    private var drawnWrap: some View {
        // Anatomy from the reference texture: a dense crinkle fringe hugging
        // every edge, a handful of long thin streaks radiating inward, and
        // almost nothing in the middle.
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            var s = UInt64(bandX * 100_000) &+ UInt64(crease1 * 10_000) &+ UInt64(crease2 * 1_000)
            func rand() -> CGFloat {
                s = s &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat((s >> 33) & 0xFFFF) / 65_535
            }
            func stroke(_ path: Path, _ opacity: CGFloat, _ width: CGFloat) {
                ctx.stroke(path, with: .color(.white.opacity(opacity)),
                           style: StrokeStyle(lineWidth: width, lineCap: .round))
            }

            // Edge fringe: short angled crinkles along all four borders.
            let perEdge = 14
            for edge in 0..<4 {
                for _ in 0..<perEdge {
                    let t = rand()
                    let len = 4 + rand() * (min(w, h) * 0.10)
                    let jitter = (rand() - 0.5) * 10
                    var start: CGPoint
                    var end: CGPoint
                    switch edge {
                    case 0:  start = CGPoint(x: t * w, y: 1 + rand() * 3)
                             end = CGPoint(x: start.x + jitter, y: start.y + len)
                    case 1:  start = CGPoint(x: t * w, y: h - 1 - rand() * 3)
                             end = CGPoint(x: start.x + jitter, y: start.y - len)
                    case 2:  start = CGPoint(x: 1 + rand() * 3, y: t * h)
                             end = CGPoint(x: start.x + len, y: start.y + jitter)
                    default: start = CGPoint(x: w - 1 - rand() * 3, y: t * h)
                             end = CGPoint(x: start.x - len, y: start.y + jitter)
                    }
                    var p = Path()
                    p.move(to: start)
                    p.addLine(to: end)
                    stroke(p, 0.10 + rand() * 0.22, 0.8 + rand() * 0.7)
                }
            }

            // Long radiating streaks from corners and edge midpoints.
            let anchors: [CGPoint] = [
                CGPoint(x: 0, y: 0), CGPoint(x: w, y: 0),
                CGPoint(x: 0, y: h), CGPoint(x: w, y: h),
                CGPoint(x: w / 2, y: 0), CGPoint(x: w, y: h / 2),
            ]
            for anchor in anchors {
                let reach = 0.25 + rand() * 0.35
                let target = CGPoint(x: anchor.x + (w / 2 - anchor.x) * reach * 2,
                                     y: anchor.y + (h / 2 - anchor.y) * reach * 2)
                let bow = CGPoint(x: (anchor.x + target.x) / 2 + (rand() - 0.5) * 18,
                                  y: (anchor.y + target.y) / 2 + (rand() - 0.5) * 18)
                var p = Path()
                p.move(to: anchor)
                p.addQuadCurve(to: target, control: bow)
                // Soft halo under a thin bright core, like taut film catching light.
                stroke(p, 0.05, 3)
                stroke(p, 0.10 + rand() * 0.10, 1)
            }

            // The faintest overall sheen so the film reads as present.
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.025)))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Cover art from Photos

/// Out-of-process Photos picker for cover art. No permission prompt: the
/// picker runs in its own process and only the chosen image reaches the app.
struct CoverPhotoPicker: UIViewControllerRepresentable {
    let onPick: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (UIImage?) -> Void
        init(onPick: @escaping (UIImage?) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else {
                onPick(nil)
                return
            }
            provider.loadObject(ofClass: UIImage.self) { [onPick] object, _ in
                DispatchQueue.main.async { onPick(object as? UIImage) }
            }
        }
    }
}

extension UIImage {
    /// Caps the long edge (covers never need more than ~1024 px).
    func scaledDown(maxSide: CGFloat) -> UIImage {
        let side = max(size.width, size.height)
        guard side > maxSide, side > 0 else { return self }
        let scale = maxSide / side
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - 2. Dark-room cue (RPG dialog box)

/// Shown once per game session when Auto sun is on but the room reads as
/// pitch black, so a dark Boktai screen is explained rather than confusing.
/// Styled like a classic JRPG text box; appears for a few seconds, then fades.
struct DarkRoomCue: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: EmulatorSession
    @State private var visible = false
    @State private var shownOnce = false

    var body: some View {
        Group {
            if visible {
                dialogBox
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.brightnessDidChangeNotification)) { _ in
            check()
        }
        .onAppear { check() }
    }

    private var dialogBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("It's pitch black in here…")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
            Text("Tap ☀ and slide the sun to light the way.")
                .font(.system(size: 12, design: .monospaced))
                .opacity(0.85)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x1B2C66), Color(hex: 0x101D48)],
                                     startPoint: .top, endPoint: .bottom))
        )
        // The classic double border.
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white, lineWidth: 2.5))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.white.opacity(0.35), lineWidth: 1).padding(4))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
    }

    private func check() {
        guard !shownOnce,
              session.cartridgeHardware.contains(.solar),
              model.settings.autoSunEnabled,
              UIScreen.main.brightness < 0.04 else { return }
        shownOnce = true
        withAnimation(.easeOut(duration: 0.25)) { visible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            withAnimation(.easeIn(duration: 0.45)) { visible = false }
        }
    }
}

// MARK: - 3. Game Boy Camera feed

/// Feeds phone-camera frames to a Game Boy Camera cartridge. Idle (no capture
/// session, no permission prompt) unless the cart actually asks for frames.
/// The GB Camera ROM itself does the 4-shade dithering, exactly like hardware.
final class GBCameraFeed: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.redfernsoutpost.tinbox.gbcamera")
    private var sink: ((UnsafePointer<UInt16>, Int, Int) -> Void)?
    private var width = 128
    private var height = 112
    private var buffer: [UInt16] = []
    private var configured = false

    func start(width: Int, height: Int, sink: @escaping (UnsafePointer<UInt16>, Int, Int) -> Void) {
        guard width > 0, height > 0 else { return }
        self.width = width
        self.height = height
        self.sink = sink
        buffer = [UInt16](repeating: 0, count: width * height)
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.configureAndRun() }
            }
        default:
            break   // denied: the game sees black, same as a covered lens
        }
    }

    func stop() {
        queue.async { [self] in
            sink = nil
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureAndRun() {
        queue.async { [self] in
            if !configured {
                session.beginConfiguration()
                session.sessionPreset = .low
                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                   let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                    session.addInput(input)
                }
                let output = AVCaptureVideoDataOutput()
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: queue)
                if session.canAddOutput(output) { session.addOutput(output) }
                session.commitConfiguration()
                configured = true
            }
            if !session.isRunning { session.startRunning() }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard sink != nil, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels) else { return }
        let sw = CVPixelBufferGetWidth(pixels)
        let sh = CVPixelBufferGetHeight(pixels)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixels)
        let src = base.assumingMemoryBound(to: UInt8.self)

        // Centre-crop to the cart's aspect, nearest-sample, BGRA to RGB565.
        let cropW = min(sw, sh * width / height)
        let cropH = min(sh, sw * height / width)
        let x0 = (sw - cropW) / 2
        let y0 = (sh - cropH) / 2
        for y in 0..<height {
            let sy = y0 + y * cropH / height
            for x in 0..<width {
                let sx = x0 + x * cropW / width
                let o = sy * rowBytes + sx * 4
                let b = UInt16(src[o])
                let g = UInt16(src[o + 1])
                let r = UInt16(src[o + 2])
                buffer[y * width + x] = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
            }
        }
        let w = width, h = height
        if let sink {
            buffer.withUnsafeBufferPointer { p in
                if let addr = p.baseAddress { sink(addr, w, h) }
            }
        }
    }
}

// MARK: - 4. Save archaeology (Gen 3 Pokemon)

/// Read-only peek inside a Gen-3 Pokemon battery save (Ruby/Sapphire/Emerald/
/// FireRed/LeafGreen and most hacks of them): player, playtime, party.
/// Nicknames default to the species name on real hardware, so the party reads
/// correctly without decrypting the species substructures.
enum Gen3Save {
    struct Insight {
        let playerName: String
        let hours: Int
        let minutes: Int
        let team: [Mon]
    }
    struct Mon: Identifiable {
        let id: Int
        let name: String
        let level: Int
    }

    static func read(for game: Game) -> Insight? {
        guard !game.isGameBoy else { return nil }
        let sav = FileLocations.saves.appendingPathComponent((game.fileName as NSString).deletingPathExtension + ".sav")
        guard let data = try? Data(contentsOf: sav), data.count >= 0xE000 else { return nil }

        func u16(_ o: Int) -> Int { Int(data[o]) | Int(data[o + 1]) << 8 }
        func u32(_ o: Int) -> UInt32 {
            UInt32(data[o]) | UInt32(data[o + 1]) << 8 | UInt32(data[o + 2]) << 16 | UInt32(data[o + 3]) << 24
        }

        // Two save slots; the valid one with the highest counter wins.
        var best: (index: UInt32, sections: [Int: Int])?
        for base in [0, 0xE000] where base + 0xE000 <= data.count {
            var sections: [Int: Int] = [:]
            var counter: UInt32 = 0
            var valid = true
            for i in 0..<14 {
                let off = base + i * 0x1000
                guard u32(off + 0xFF8) == 0x08012025 else { valid = false; break }
                sections[u16(off + 0xFF4)] = off
                counter = u32(off + 0xFFC)
            }
            if valid, sections.count == 14, best == nil || counter >= best!.index {
                best = (counter, sections)
            }
        }
        guard let slot = best, let trainer = slot.sections[0], let teamSection = slot.sections[1] else { return nil }

        let name = decodeText(data, at: trainer, max: 7)
        let hours = u16(trainer + 0x0E)
        let minutes = Int(data[trainer + 0x10])
        guard !name.isEmpty, hours < 1000 else { return nil }

        // FRLG keeps the party at a different offset than RS/E.
        let frlg = u32(trainer + 0xAC) == 1
        let countOffset = teamSection + (frlg ? 0x034 : 0x234)
        let listOffset = teamSection + (frlg ? 0x038 : 0x238)
        let count = min(6, Int(u32(countOffset)))
        var team: [Mon] = []
        for i in 0..<count {
            let m = listOffset + i * 100
            guard m + 100 <= data.count else { break }
            let nick = decodeText(data, at: m + 8, max: 10)
            let level = Int(data[m + 84])
            guard !nick.isEmpty, (1...100).contains(level) else { continue }
            team.append(Mon(id: i, name: nick, level: level))
        }
        return Insight(playerName: name, hours: hours, minutes: minutes, team: team)
    }

    /// The Gen-3 proprietary character set (western), letters and digits subset.
    private static func decodeText(_ data: Data, at offset: Int, max: Int) -> String {
        var out = ""
        for i in 0..<max {
            guard offset + i < data.count else { break }
            let b = data[offset + i]
            switch b {
            case 0xFF: return out
            case 0x00: out.append(" ")
            case 0xA1...0xAA: out.append(Character(UnicodeScalar(UInt8(b - 0xA1) + 0x30)))   // 0-9
            case 0xBB...0xD4: out.append(Character(UnicodeScalar(UInt8(b - 0xBB) + 0x41)))   // A-Z
            case 0xD5...0xEE: out.append(Character(UnicodeScalar(UInt8(b - 0xD5) + 0x61)))   // a-z
            case 0xB5: out.append("♂")
            case 0xB6: out.append("♀")
            case 0xAD: out.append(".")
            case 0xAE: out.append("-")
            default: break
            }
        }
        return out
    }
}

/// "Inside the save" rows for the game actions sheet.
struct SaveInsightRows: View {
    @Environment(\.theme) private var theme
    let insight: Gen3Save.Insight

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(title: "Inside the save",
                        subtitle: "\(insight.playerName) · \(insight.hours)h \(String(format: "%02d", insight.minutes))m played",
                        showsSeparator: !insight.team.isEmpty) { EmptyView() }
            if !insight.team.isEmpty {
                HStack(spacing: 6) {
                    ForEach(insight.team) { mon in
                        VStack(spacing: 1) {
                            Text(mon.name)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Palette.text85)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text("Lv \(mon.level)")
                                .font(.system(size: 10))
                                .foregroundColor(theme.accentText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(theme.wellStyle)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
    }
}

// MARK: - 5. Speedrun timer

/// RTA split timer, LiveSplit-style but on-screen. Tap the time to start and
/// to split; the ellipsis menu finishes (saving a personal best), resets or
/// hides. Time keeps running through menus, like real RTA.
final class SpeedrunTimer: ObservableObject {
    static let shared = SpeedrunTimer()

    @Published var visible = false
    @Published private(set) var running = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var splits: [TimeInterval] = []
    private(set) var personalBest: [TimeInterval] = []

    private var startDate: Date?
    private var tick: Timer?
    private var gameID = ""

    func attach(gameID: String) {
        guard gameID != self.gameID else { return }
        hardReset()
        self.gameID = gameID
        personalBest = Self.loadPB(gameID: gameID)
    }

    func startOrSplit() {
        if running {
            splits.append(elapsed)
        } else {
            splits = []
            startDate = Date()
            running = true
            tick?.invalidate()
            let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self, let start = self.startDate else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
            t.tolerance = 0.01
            RunLoop.main.add(t, forMode: .common)
            tick = t
        }
    }

    /// Ends the run; keeps it as the personal best if it beats the old one.
    func finish() {
        guard running else { return }
        splits.append(elapsed)
        running = false
        tick?.invalidate()
        if personalBest.isEmpty || (splits.last ?? .infinity) < (personalBest.last ?? .infinity) {
            personalBest = splits
            Self.savePB(splits, gameID: gameID)
        }
    }

    func hardReset() {
        tick?.invalidate()
        running = false
        elapsed = 0
        splits = []
        startDate = nil
    }

    /// Delta of the latest split against the personal best's same split.
    var lastDelta: TimeInterval? {
        guard let i = splits.indices.last, i < personalBest.count else { return nil }
        return splits[i] - personalBest[i]
    }

    static func format(_ t: TimeInterval) -> String {
        let cs = Int((t * 100).rounded())
        return String(format: "%d:%02d.%02d", cs / 6000, (cs / 100) % 60, cs % 100)
    }

    private static func pbFile(_ gameID: String) -> URL {
        let dir = FileLocations.documents.appendingPathComponent("Speedrun", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(gameID).json")
    }
    private static func loadPB(gameID: String) -> [TimeInterval] {
        guard let data = try? Data(contentsOf: pbFile(gameID)) else { return [] }
        return (try? JSONDecoder().decode([TimeInterval].self, from: data)) ?? []
    }
    private static func savePB(_ pb: [TimeInterval], gameID: String) {
        if let data = try? JSONEncoder().encode(pb) {
            try? data.write(to: pbFile(gameID), options: .atomic)
        }
    }
}

struct SpeedrunOverlay: View {
    @ObservedObject private var timer = SpeedrunTimer.shared
    @Environment(\.theme) private var theme

    var body: some View {
        if timer.visible {
            HStack(spacing: 8) {
                Button {
                    ButtonHaptics.shared.tap()
                    timer.startOrSplit()
                } label: {
                    HStack(spacing: 6) {
                        Text(SpeedrunTimer.format(timer.elapsed))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(timer.running ? .white : Palette.text55)
                        if !timer.splits.isEmpty {
                            Text("\(timer.splits.count)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(theme.accentText)
                        }
                        if let delta = timer.lastDelta {
                            Text(String(format: "%@%@", delta <= 0 ? "-" : "+", SpeedrunTimer.format(abs(delta))))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(delta <= 0 ? Color(hex: 0x58CC52) : Palette.destructive)
                        }
                    }
                }
                .buttonStyle(FadePressStyle())
                Menu {
                    Button { timer.finish() } label: { Label("Finish run (save PB)", systemImage: "flag.checkered") }
                    Button { timer.hardReset() } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                    Button(role: .destructive) { timer.visible = false } label: { Label("Hide timer", systemImage: "eye.slash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Palette.text55)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.72))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Palette.hairline12, lineWidth: 0.5))
        }
    }
}

// MARK: - 6. Controller remapping

/// One picker row per physical pad element; targets are GBA actions.
struct ControllerRemapCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    static let physical: [(id: String, label: String)] = [
        ("a", "A button"), ("b", "B button"), ("x", "X button"), ("y", "Y button"),
        ("l1", "Left shoulder"), ("r1", "Right shoulder"),
        ("l2", "Left trigger"), ("r2", "Right trigger"),
        ("options", "Options button"), ("menu", "Menu button"),
    ]
    static let targets: [(id: String, label: String)] = [
        ("a", "A"), ("b", "B"), ("l", "L"), ("r", "R"),
        ("select", "Select"), ("start", "Start"), ("off", "Nothing"),
    ]

    var body: some View {
        Card(bottomSpacing: 0) {
            ForEach(Array(Self.physical.enumerated()), id: \.element.id) { index, phys in
                SettingsRow(title: phys.label, showsSeparator: index < Self.physical.count - 1) {
                    Menu {
                        Picker(phys.label, selection: binding(for: phys.id)) {
                            ForEach(Self.targets, id: \.id) { t in Text(t.label).tag(t.id) }
                        }
                    } label: {
                        Text(label(for: current(phys.id)))
                            .font(Typography.detailSemibold)
                            .foregroundColor(theme.accentText)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(theme.tint)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
    }

    private func current(_ physical: String) -> String {
        model.settings.controllerBindings[physical] ?? ControllerManager.defaultBindings[physical] ?? "off"
    }
    private func label(for target: String) -> String {
        Self.targets.first { $0.id == target }?.label ?? target
    }
    private func binding(for physical: String) -> Binding<String> {
        Binding(get: { current(physical) },
                set: { model.settings.controllerBindings[physical] = $0 })
    }
}
