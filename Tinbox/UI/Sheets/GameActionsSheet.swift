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
                    CoverArt(game: game)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.hairline07, lineWidth: 0.5))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(game.title).font(Typography.sheetTitle).foregroundColor(.white).lineLimit(2)
                        Text("\(game.fileSize.fileSizeString) · \(game.isExternal ? ROMFolderAccess.shared.displayName : "Tinbox › ROMs")")
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

                Card {
                    if let latest = model.selectedGameLatestSave {
                        NavRow(title: "Continue", subtitle: "From \(latest)") {
                            model.openAndContinue(game)
                        }
                    }
                    NavRow(title: "Load a save file…", subtitle: "Pick a .sav or .sst from Files, then play") {
                        model.importKind = .saveForGame
                    }
                    NavRow(title: "Make a patched copy…", subtitle: "IPS / UPS / BPS · saves a new ROM, keeps this one", showsSeparator: false) {
                        model.importKind = .patchForGame
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
