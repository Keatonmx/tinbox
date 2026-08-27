//
//  GameActionsSheet.swift
//  Tinbox
//
//  Opens when a library tile is tapped: Play, Continue from the newest save,
//  load a save file from Files, make a patched copy, remove.
//  Plus the small ROM-folder chooser used from Settings.
//

import SwiftUI

struct GameActionsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @State private var confirmRemove = false

    var body: some View {
        BottomSheet(onDismiss: { model.closeSheet() }) {
            if let game = model.selectedGame {
                HStack(spacing: 14) {
                    CoverArt(game: game, coverVersion: model.coverVersion)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.hairline07, lineWidth: 0.5))
                        .contextMenu {
                            Button { model.coverPhotoTarget = game } label: { Label("Cover from Photos…", systemImage: "photo.on.rectangle") }
                            Button { model.importKind = .coverForGame } label: { Label("Cover from Files…", systemImage: "folder") }
                            Button { model.retryCover(for: game) } label: { Label("Find box art online", systemImage: "arrow.clockwise") }
                            Button(role: .destructive) { model.removeCover(for: game) } label: { Label("Remove cover", systemImage: "trash") }
                        }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(game.title).font(Typography.sheetTitle).foregroundColor(.white).lineLimit(2)
                        Text("\(game.systemBadge) · \(game.fileSize.fileSizeString) · \(game.isExternal ? ROMFolderAccess.shared.displayName : "Tinbox › ROMs")")
                            .font(Typography.meta13).foregroundColor(Palette.text40)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 14)

                Button {
                    ButtonHaptics.shared.tap()
                    model.open(game)
                } label: {
                    Text("Play")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(DimPressStyle())
                .padding(.bottom, 12)

                // Revision X: what the battery save says (Gen-3 Pokemon only).
                if let insight = Gen3Save.read(for: game) {
                    Card { SaveInsightRows(insight: insight) }
                }

                Card {
                    if let latest = model.selectedGameLatestSave, let slot = model.latestSlotIndex(for: game) {
                        Button {
                            ButtonHaptics.shared.tap()
                            model.openAndContinue(game)
                        } label: {
                            HStack(spacing: 12) {
                                SaveThumbnail(image: GameLibraryStore.shared.thumbnail(gameID: game.id, slot: slot))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Continue").font(Typography.row).foregroundColor(.white)
                                    Text("From \(latest)").font(Typography.rowSubtitle).foregroundColor(Palette.textTertiary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                RowChevron()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        RowSeparator()
                    }
                    NavRow(title: "Load a save file…", subtitle: "Pick a .sav or .sst from Files, then play") {
                        model.importKind = .saveForGame
                    }
                    NavRow(title: "Make a patched copy…", subtitle: "IPS / UPS / BPS · saves a new ROM, keeps this one") {
                        model.importKind = .patchForGame
                    }
                    NavRow(title: "Choose cover image…", subtitle: "Or long-press the cover for more options", showsSeparator: false) {
                        model.importKind = .coverForGame
                    }
                }

                Button {
                    ButtonHaptics.shared.tap()
                    confirmRemove = true
                } label: {
                    Text(game.isExternal ? "Remove from Library" : "Delete ROM & saves")
                        .font(Typography.rowSemibold)
                        .foregroundColor(Palette.destructive)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 54)
                        .background(theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(ExitPressStyle())
                .confirmationDialog(game.isExternal ? "Remove \(game.title) from the library? The file stays in \(ROMFolderAccess.shared.displayName)."
                                                    : "Delete \(game.title)? The ROM file and its save states are removed.",
                                    isPresented: $confirmRemove, titleVisibility: .visible) {
                    Button(game.isExternal ? "Remove" : "Delete", role: .destructive) { model.deleteGame(game) }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
    }
}

/// 84×56 save-state screenshot (or a dashed placeholder).
struct SaveThumbnail: View {
    @Environment(\.theme) private var theme
    let image: UIImage?

    var body: some View {
        ZStack {
            theme.well
            if let image {
                Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
            } else {
                StripedPlaceholder(stripe: theme.stripe2, period: 16, width: 6)
            }
        }
        .frame(width: 84, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Palette.hairline08, lineWidth: 0.5))
    }
}

struct ROMFolderSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        BottomSheet(onDismiss: { model.openSheet(.settings) }) {
            SheetHeader(title: "ROM Folder", onBack: { model.openSheet(.settings) }) { EmptyView() }
            Text("New imports go here and the Library shows every ROM inside it.")
                .font(Typography.meta13).foregroundColor(Palette.text40)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).padding(.bottom, 8)
            Card(bottomSpacing: 0) {
                NavRow(title: "Tinbox › ROMs", subtitle: "Files › On My iPhone › Tinbox › ROMs",
                       detail: ROMFolderAccess.shared.isCustom ? nil : "Current", showsChevron: ROMFolderAccess.shared.isCustom) {
                    if ROMFolderAccess.shared.isCustom { model.useDefaultROMFolder() }
                }
                NavRow(title: "Choose a folder…", subtitle: ROMFolderAccess.shared.isCustom ? "Current: \(ROMFolderAccess.shared.displayName)" : "Any folder in Files or iCloud Drive",
                       showsSeparator: false) {
                    model.importKind = .romFolder
                }
            }
        }
    }
}
