//
//  CartridgeInsertView.swift
//  Tinbox
//
//  The boot flourish's cartridge: a drawn GBA cart with the real silhouette
//  (domed grip, shoulder notches, inset rails, stepped connector lip), traced
//  from a reference render. Customised per game: plastic tinted by the game's
//  hue, the cover art as the label sticker, the ROM header code printed on it.
//  PortraitGameView slides it down into the screen band before the lid opens.
//

import SwiftUI

/// Front-view outline of a GBA cartridge, connector edge down.
struct GBACartShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: r.minX + x * w, y: r.minY + y * h)
        }
        // Rails sit inset from the full-width "ears" above the shoulder notch.
        let rail: CGFloat = 0.955
        var p = Path()
        p.move(to: pt(0, 0.115))
        // Top-left corner, then the grip dome across the top.
        p.addQuadCurve(to: pt(0.075, 0.045), control: pt(0.005, 0.045))
        p.addLine(to: pt(0.16, 0.045))
        p.addQuadCurve(to: pt(0.84, 0.045), control: pt(0.5, -0.045))
        p.addLine(to: pt(0.925, 0.045))
        p.addQuadCurve(to: pt(1, 0.115), control: pt(0.995, 0.045))
        // Right ear down to the shoulder notch, step in to the rail.
        p.addLine(to: pt(1, 0.28))
        p.addLine(to: pt(rail, 0.30))
        // Rail down to the connector step.
        p.addLine(to: pt(rail, 0.865))
        p.addLine(to: pt(0.93, 0.885))
        // Connector lip with chamfered bottom corner.
        p.addLine(to: pt(0.93, 0.965))
        p.addLine(to: pt(0.905, 1))
        // Bottom edge, then mirror everything up the left side.
        p.addLine(to: pt(0.095, 1))
        p.addLine(to: pt(0.07, 0.965))
        p.addLine(to: pt(0.07, 0.885))
        p.addLine(to: pt(1 - rail, 0.865))
        p.addLine(to: pt(1 - rail, 0.30))
        p.addLine(to: pt(0, 0.28))
        p.closeSubpath()
        return p
    }
}

struct CartridgeView: View {
    let game: Game

    /// Cart plastic from the game's deterministic hue (like the coloured
    /// Pokémon carts); label is the game's cover art.
    private var plasticTop: Color { Color(hue: game.coverHue, saturation: 0.38, brightness: 0.44) }
    private var plasticBottom: Color { Color(hue: game.coverHue, saturation: 0.42, brightness: 0.30) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Body
                GBACartShape()
                    .fill(LinearGradient(colors: [plasticTop, plasticBottom], startPoint: .top, endPoint: .bottom))
                GBACartShape()
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)

                // Recessed band with the embossed brand line, under the dome.
                Text("GAME BOY ADVANCE")
                    .font(.system(size: w * 0.048, weight: .heavy))
                    .tracking(w * 0.010)
                    .foregroundColor(.black.opacity(0.38))
                    .shadow(color: .white.opacity(0.20), radius: 0, y: 0.7)
                    .padding(.horizontal, w * 0.03)
                    .padding(.vertical, h * 0.018)
                    .background(Capsule().fill(Color.black.opacity(0.10)))
                    .position(x: w * 0.5, y: h * 0.135)

                // Label sticker: cover art recessed into the plastic, with the
                // header code printed on it like the real AGB-XXXX mark.
                CoverArt(game: game)
                    .frame(width: w * 0.70, height: h * 0.50)
                    .clipShape(RoundedRectangle(cornerRadius: w * 0.025, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: w * 0.025, style: .continuous)
                        .stroke(Color.black.opacity(0.45), lineWidth: 1.5))
                    .overlay(alignment: .bottomTrailing) {
                        Text("AGB-\(game.gameCode ?? String(game.title.prefix(4)).uppercased())")
                            .font(.system(size: w * 0.036, design: .monospaced).weight(.semibold))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, w * 0.016)
                            .padding(.vertical, h * 0.008)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Capsule())
                            .padding(w * 0.018)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 1, y: -1)
                    .position(x: w * 0.5, y: h * 0.545)

                // Moulded arrow near the bottom-right, like the real cart.
                ChevronShape(direction: .right)
                    .stroke(Color.black.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(width: w * 0.030, height: h * 0.045)
                    .rotationEffect(.degrees(90))
                    .position(x: w * 0.80, y: h * 0.83)

                // Board edge peeking out of the connector lip.
                HStack(spacing: w * 0.020) {
                    ForEach(0..<14, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(LinearGradient(colors: [Color(hex: 0xC9A24B), Color(hex: 0x8A6E2F)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: w * 0.030, height: h * 0.055)
                    }
                }
                .frame(width: w * 0.80, height: h * 0.085)
                .background(Color.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                .position(x: w * 0.5, y: h * 0.945)
            }
            .shadow(color: .black.opacity(0.55), radius: 14, y: 10)
        }
        .aspectRatio(1.6, contentMode: .fit)
    }
}
