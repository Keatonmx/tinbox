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

    // Top-aligned so the Import tile lines up with covers, not with cover + title.
    private let columns = [GridItem(.flexible(), spacing: 16, alignment: .top), GridItem(.flexible(), spacing: 16, alignment: .top)]

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    if model.games.count > 4 || !model.searchText.isEmpty {
                        searchBar
                    }
                    if model.searchText.isEmpty, let recent = model.recentGame {
                        ContinueCard(game: recent, coverVersion: model.coverVersion)
                    }
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(model.visibleGames) { game in
                            GameTile(game: game, coverVersion: model.coverVersion)
                                .onTapGesture {
                                    ButtonHaptics.shared.tap()
                                    model.select(game)
                                }
                                .contextMenu {
                                    Button { model.open(game) } label: { Label("Play", systemImage: "play.fill") }
                                    Button { model.select(game) } label: { Label("Options…", systemImage: "ellipsis.circle") }
                                }
                        }
                        if model.searchText.isEmpty {
                            importTile
                        }
                    }
                    if !model.searchText.isEmpty, model.visibleGames.isEmpty {
                        VStack(spacing: 8) {
                            GlitchTexture()
                                .frame(width: 120, height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            if !EggText.glitchCaption.isEmpty {
                                Text(EggText.glitchCaption)
                                    .font(Typography.mono8Bold).tracking(1)
                                    .foregroundColor(Palette.textQuaternary)
                            }
                            Text("No games match")
                                .font(Typography.meta13)
                                .foregroundColor(Palette.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                    }
                    if model.games.isEmpty {
                        VStack(spacing: 12) {
                            Image("EmptyTin")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 88, height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .opacity(0.9)
                            Text("The tin is empty")
                                .font(Typography.cardTitle)
                                .foregroundColor(Palette.text55)
                            Text("Add .gba, .gb, .gbc or .zip files from the Files app. They go into your ROM folder, which you can also open in Files.")
                                .font(Typography.meta13)
                                .foregroundColor(Palette.textTertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 60)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(theme.bg.ignoresSafeArea())
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(Palette.text40)
                TextField("", text: $model.searchText, prompt: Text("Search games").foregroundColor(Palette.textQuaternary))
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .focused($searchFocused)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !model.searchText.isEmpty {
                    Button { model.searchText = ""; searchFocused = false } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(Palette.text40)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(theme.chip)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.hairline08, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Menu {
                Picker("Sort", selection: $model.settings.librarySort) {
                    ForEach(LibrarySort.allCases) { sort in Text(sort.rawValue).tag(sort) }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 12, weight: .semibold))
                    Text(model.settings.librarySort.rawValue).font(Typography.segment)
                }
                .foregroundColor(Palette.text70)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(theme.chip)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.hairline08, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                TinStamp()
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
                if model.games.isEmpty {
                    GlitchTexture().opacity(0.5).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                VStack(spacing: 6) {
                    Text("+").font(.system(size: 26, weight: .regular)).foregroundColor(theme.accent)
                    Text("Import ROM").font(.system(size: 13, weight: .semibold)).foregroundColor(Palette.text55)
                        .lineLimit(1)
                    if model.games.isEmpty, !EggText.glitchCaption.isEmpty {
                        Text(EggText.glitchCaption)
                            .font(Typography.mono8Bold).tracking(1)
                            .foregroundColor(Palette.textQuaternary)
                    }
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

/// The "TINBOX" eyebrow as a stamped brand lozenge: uppercase inside a full
/// stadium (pill) outline, a tiny ® off the shoulder, slight skew,
/// pressed-into-metal shading.
struct TinStamp: View {
    var body: some View {
        HStack(alignment: .top, spacing: 1.5) {
            Text("TINBOX")
                .font(Typography.eyebrow)
                .tracking(2)
            // Superscript ® tucked inside the pill, top-right of the word.
            Text("®")
                .font(.system(size: 6.5, weight: .semibold))
                .padding(.top, -0.5)
        }
        .foregroundColor(Palette.textTertiary)
        // Debossed: a hair of light catching the stamp's lower edge.
        .shadow(color: .white.opacity(0.18), radius: 0, y: 0.7)
        .padding(.leading, 11)
        .padding(.trailing, 8)
        .padding(.vertical, 3.5)
        .overlay(Capsule().stroke(Palette.textQuaternary, lineWidth: 1.5))
        .rotationEffect(.degrees(-3), anchor: .bottomLeading)
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
    /// Changes when a cover is (re)written so the image reloads from disk.
    var coverVersion: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverArt(game: game, coverVersion: coverVersion)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.hairline07, lineWidth: 0.5))
                .overlay(alignment: .topTrailing) {
                    Text(game.systemBadge)
                        .font(Typography.mono8Bold)
                        .tracking(0.5)
                        .foregroundColor(Palette.text70)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                        .padding(6)
                }
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

/// "Jump back in" card for the most recently played game.
struct ContinueCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    let game: Game
    let coverVersion: Int

    var body: some View {
        Button {
            ButtonHaptics.shared.tap()
            model.openAndContinue(game)
        } label: {
            HStack(spacing: 14) {
                CoverArt(game: game, coverVersion: coverVersion)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.hairline07, lineWidth: 0.5))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Continue")
                        .font(Typography.eyebrow).textCase(.uppercase).tracking(1)
                        .foregroundColor(theme.accentText)
                    Text(game.title).font(Typography.rowSemibold).foregroundColor(.white).lineLimit(1)
                    Text(model.latestSaveDescription(for: game) ?? "Played \((game.lastPlayed ?? Date()).relativeLibraryString)")
                        .font(Typography.meta).foregroundColor(Palette.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle().fill(theme.accent)
                    Image(systemName: "play.fill").font(.system(size: 14, weight: .bold)).foregroundColor(.white).offset(x: 1)
                }
                .frame(width: 40, height: 40)
            }
            .padding(12)
            .background(theme.card)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(theme.tintBorder.opacity(0.6), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(FadePressStyle(opacity: 0.8))
        .contextMenu {
            Button { model.open(game) } label: { Label("Play from the start", systemImage: "play") }
            Button { model.select(game) } label: { Label("Options…", systemImage: "ellipsis.circle") }
        }
    }
}

/// Box art if the user dropped one into Documents/Covers, otherwise the
/// striped placeholder tinted by the game's hue with the title initials.
struct CoverArt: View {
    @Environment(\.theme) private var theme
    let game: Game
    var coverVersion: Int = 0

    var body: some View {
        ZStack {
            if let image = GameLibraryStore.shared.coverImage(for: game) {
                Color.black
                Image(uiImage: image).resizable().scaledToFit()
                    .id(coverVersion)
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
