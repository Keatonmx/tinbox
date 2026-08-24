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
