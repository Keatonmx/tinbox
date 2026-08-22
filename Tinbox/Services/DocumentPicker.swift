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

enum ImportKind {
    case rom
    case saveState
    case bios
    case patch

    var title: String {
        switch self {
        case .rom: return "Import ROM"
        case .saveState: return "Import Save States"
        case .bios: return "Import BIOS"
        case .patch: return "Apply ROM patch"
        }
    }

    /// Destination shown in the import chip.
    var destination: String {
        switch self {
        case .rom: return "On My iPhone › Tinbox › ROMs"
        case .saveState: return "On My iPhone › Tinbox › States"
        case .bios: return "On My iPhone › Tinbox › BIOS"
        case .patch: return "On My iPhone › Tinbox › Patches"
        }
    }

    var contentTypes: [UTType] {
        switch self {
        case .rom:
            return [UTType.gbaROM, .zip, .archive, .data]
        case .saveState:
            return [UTType.gbaSaveState, UTType.gbaBatterySave, .data]
        case .bios:
            return [UTType.gbaBIOS, .data]
        case .patch:
            return [UTType.ipsPatch, UTType.upsPatch, UTType.bpsPatch, .data]
        }
    }

    var allowsMultiple: Bool {
        switch self {
        case .rom, .saveState: return true
        case .bios, .patch: return false
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
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: kind.contentTypes, asCopy: true)
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
