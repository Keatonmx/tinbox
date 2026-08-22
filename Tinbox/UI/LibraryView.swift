//
//  LibraryView.swift
//  Tinbox
//
//  "TINBOX" eyebrow over the "Library" large title, settings button, 2-column
//  grid of covers and the dashed "+ Import ROM" tile.
//

import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(model.games) { game in
                        GameTile(game: game)
                            .onTapGesture {
                                ButtonHaptics.shared.tap()
                                model.select(game)
                            }
                            .contextMenu {
                                Button { model.open(game) } label: { Label("Play", systemImage: "play.fill") }
                                Button { model.select(game) } label: { Label("Options…", systemImage: "ellipsis.circle") }
                            }
                    }
                    importTile
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 60)
            }
        }
        .background(theme.bg.ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tinbox")
                    .font(Typography.eyebrow)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundColor(Palette.textTertiary)
                Text("Library")
                    .font(Typography.largeTitle)
                    .tracking(0.3)
                    .foregroundColor(.white)
            }
            Spacer()
            CircleIconButton(size: 44, action: { model.openSheet(.settings) }) {
                SettingsGlyph()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var importTile: some View {
        Button {
            ButtonHaptics.shared.tap()
            model.importKind = .rom
        } label: {
            ZStack {
                Color.clear
                VStack(spacing: 6) {
                    Text("+").font(.system(size: 26, weight: .regular)).foregroundColor(theme.accent)
                    Text("Import ROM").font(.system(size: 13, weight: .semibold)).foregroundColor(Palette.text55)
                        .lineLimit(1)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundColor(Color(rgba: 235, 235, 245, 0.2))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(FadePressStyle())
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

/// The two-line "hamburger with accent dots" glyph from the prototype.
struct SettingsGlyph: View {
    @Environment(\.theme) private var theme
    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                Capsule().fill(Palette.text70).frame(width: 20, height: 2)
                Capsule().fill(Palette.text70).frame(width: 20, height: 2)
            }
            Circle().fill(theme.accent).frame(width: 6, height: 6).offset(x: -4, y: -5)
            Circle().fill(theme.accent).frame(width: 6, height: 6).offset(x: 4, y: 5)
        }
        .frame(width: 20, height: 16)
    }
}

struct GameTile: View {
    @Environment(\.theme) private var theme
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverArt(game: game)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.hairline07, lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 1) {
                Text(game.title)
                    .font(Typography.cardTitle)
                    .tracking(-0.2)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(meta)
                    .font(Typography.meta)
                    .foregroundColor(Palette.textTertiary)
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
    }

    private var meta: String {
        let when = (game.lastPlayed ?? game.addedAt).relativeLibraryString
        return "\(game.fileSize.fileSizeString) · \(when)"
    }
}

/// Box art if the user dropped one into Documents/Covers, otherwise the
/// striped placeholder tinted by the game's hue with the title initials.
struct CoverArt: View {
    @Environment(\.theme) private var theme
    let game: Game

    var body: some View {
        ZStack {
            if let image = GameLibraryStore.shared.coverImage(for: game) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                theme.chip
                StripedPlaceholder(stripe: Color(hue: game.coverHue / 360, saturation: 0.4, brightness: 0.65).opacity(0.13),
                                   period: 20, width: 8)
                Text(initials)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
    }

    private var initials: String {
        let words = game.title.split(separator: " ").prefix(2)
        return words.map { String($0.prefix(1)).uppercased() }.joined()
    }
}
