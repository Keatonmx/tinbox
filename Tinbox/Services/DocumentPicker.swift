//
//  DocumentPicker.swift
//  Tinbox
//
//  Native UIDocumentPickerViewController, filtered per import kind. Picks are
//  copied (asCopy: true) so the app owns the file; callers then move the copy
//  into Documents/ROMs, States, Saves, BIOS or Patches.
//

import SwiftUI
import UniformTypeIdentifiers

enum ImportKind: Equatable {
    case rom
    /// Save file for the running game.
    case saveState
    /// Save file for a specific library game (from the game's action sheet).
    case saveForGame
    case bios
    /// Patch → permanent patched copy of a specific library game.
    case patchForGame
    /// Choose the ROM library folder.
    case romFolder

    var title: String {
        switch self {
        case .rom: return "Import ROM"
        case .saveState, .saveForGame: return "Load Save File"
        case .bios: return "Import BIOS"
        case .patchForGame: return "Choose a patch"
        case .romFolder: return "Choose ROM folder"
        }
    }

    var contentTypes: [UTType] {
        switch self {
        case .rom:
            return [UTType.gbaROM, .zip, .archive, .data]
        case .saveState, .saveForGame:
            return [UTType.gbaSaveState, UTType.gbaBatterySave, .data]
        case .bios:
            return [UTType.gbaBIOS, .data]
        case .patchForGame:
            return [UTType.ipsPatch, UTType.upsPatch, UTType.bpsPatch, .data]
        case .romFolder:
            return [.folder]
        }
    }

    var allowsMultiple: Bool {
        switch self {
        case .rom, .saveState, .saveForGame: return true
        case .bios, .patchForGame, .romFolder: return false
        }
    }

    /// ROMs are opened in place (not copied to a temp file) so "Move" can
    /// remove the original afterwards.
    var opensInPlace: Bool {
        switch self {
        case .rom, .romFolder: return true
        default: return false
        }
    }
}

extension UTType {
    // Declared as exported types in Info.plist so Files shows the right icons
    // and the picker can filter on them.
    static let gbaROM = UTType(exportedAs: "com.redfernsoutpost.tinbox.gba-rom", conformingTo: .data)
    static let gbaSaveState = UTType(exportedAs: "com.redfernsoutpost.tinbox.gba-savestate", conformingTo: .data)
    static let gbaBatterySave = UTType(exportedAs: "com.redfernsoutpost.tinbox.gba-battery-save", conformingTo: .data)
    static let gbaBIOS = UTType(exportedAs: "com.redfernsoutpost.tinbox.gba-bios", conformingTo: .data)
    static let ipsPatch = UTType(exportedAs: "com.redfernsoutpost.tinbox.ips-patch", conformingTo: .data)
    static let upsPatch = UTType(exportedAs: "com.redfernsoutpost.tinbox.ups-patch", conformingTo: .data)
    static let bpsPatch = UTType(exportedAs: "com.redfernsoutpost.tinbox.bps-patch", conformingTo: .data)
}

struct DocumentPicker: UIViewControllerRepresentable {
    let kind: ImportKind
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: kind.contentTypes, asCopy: !kind.opensInPlace)
        picker.allowsMultipleSelection = kind.allowsMultiple
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        picker.overrideUserInterfaceStyle = .dark
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(_ parent: DocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}
