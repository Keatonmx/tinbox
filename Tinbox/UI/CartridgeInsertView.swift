//
//  CartridgeInsertView.swift
//  Tinbox
//
//  The boot flourish's cartridge: a drawn GBA cart, customised per game
//  (plastic tinted by the game's hue, the cover art as the label sticker,
//  the ROM header code on the spine). PortraitGameView slides it down into
//  the screen band before the lid opens.
//

import SwiftUI

struct CartridgeView: View {
    let game: Game

    /// Cart plastic from the game's deterministic hue (like the coloured
    /// Pokémon carts); label is the game's cover art.
    private var plasticTop: Color { Color(hue: game.coverHue, saturation: 0.38, brightness: 0.42) }
    private var plasticBottom: Color { Color(hue: game.coverHue, saturation: 0.42, brightness: 0.30) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = w / 1.5
            VStack(spacing: 0) {
                // Body
                ZStack {
                    RoundedRectangle(cornerRadius: w * 0.045, style: .continuous)
                        .fill(LinearGradient(colors: [plasticTop, plasticBottom], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: w * 0.045, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1))

                    VStack(spacing: h * 0.045) {
                        // Embossed brand line
                        Text("GAME BOY ADVANCE")
                            .font(.system(size: w * 0.052, weight: .heavy))
                            .tracking(w * 0.008)
                            .foregroundColor(.black.opacity(0.35))
                            .shadow(color: .white.opacity(0.18), radius: 0, y: 0.7)
                            .padding(.top, h * 0.07)

                        // Label sticker: the game's cover art (or its striped
                        // placeholder), recessed into the plastic.
                        CoverArt(game: game)
                            .aspectRatio(1.55, contentMode: .fill)
                            .frame(width: w * 0.74, height: h * 0.52)
                            .clipShape(RoundedRectangle(cornerRadius: w * 0.03, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: w * 0.03, style: .continuous)
                                .stroke(Color.black.opacity(0.45), lineWidth: 1.5))
                            .shadow(color: .black.opacity(0.35), radius: 1, y: -1)

                        // Header code, like the moulded AGB code on real carts.
                        Text("AGB-\(game.gameCode ?? String(game.title.prefix(4)).uppercased())")
                            .font(.system(size: w * 0.045, design: .monospaced).weight(.semibold))
                            .foregroundColor(.white.opacity(0.35))
                        Spacer(minLength: 0)
                    }

                    // Side grip ridges
                    HStack {
                        gripRidges(height: h)
                        Spacer()
                        gripRidges(height: h)
                    }
                    .padding(.horizontal, w * 0.02)
                }
                .frame(width: w, height: h)

                // Gold edge connector, leading the way in.
                HStack(spacing: w * 0.022) {
                    ForEach(0..<12, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(LinearGradient(colors: [Color(hex: 0xC9A24B), Color(hex: 0x8A6E2F)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: w * 0.036, height: h * 0.10)
                    }
                }
                .padding(.vertical, h * 0.015)
                .frame(width: w * 0.86)
                .background(Color.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
            .shadow(color: .black.opacity(0.55), radius: 14, y: 10)
        }
        .aspectRatio(1.5 / 1.13, contentMode: .fit)   // body + connector
    }

    private func gripRidges(height: CGFloat) -> some View {
        VStack(spacing: 2.5) {
            ForEach(0..<4, id: \.self) { _ in
                Capsule().fill(Color.black.opacity(0.25)).frame(width: 8, height: 2)
            }
        }
        .padding(.top, height * 0.08)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
