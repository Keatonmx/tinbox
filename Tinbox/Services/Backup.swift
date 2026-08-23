//
//  Backup.swift
//  Tinbox
//
//  iOS deletes an app's Documents folder when the app is uninstalled, so in-game
//  saves and save states need a copy somewhere else. Backup zips Saves/ and
//  States/ (via NSFileCoordinator's forUploading, which produces a zip for a
//  directory) and hands it to the share sheet / Files; Restore unzips with
//  libmgba's minizip and merges the contents back.
//

import Foundation
import UIKit
import SwiftUI

enum Backup {
    static func makeArchive() throws -> URL {
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("Tinbox Backup", isDirectory: true)
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        for folder in ["Saves", "States", "Cheats"] {
            let src = FileLocations.documents.appendingPathComponent(folder, isDirectory: true)
            if FileManager.default.fileExists(atPath: src.path) {
                try FileManager.default.copyItem(at: src, to: staging.appendingPathComponent(folder, isDirectory: true))
            }
        }
        let stamp: String = {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HHmm"; return f.string(from: Date())
        }()
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("Tinbox Backup \(stamp).zip")
        try? FileManager.default.removeItem(at: out)

        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: staging, options: .forUploading, error: &coordinatorError) { zipURL in
            do { try FileManager.default.copyItem(at: zipURL, to: out) } catch { copyError = error }
        }
        if let coordinatorError { throw coordinatorError }
        if let copyError { throw copyError }
        try? FileManager.default.removeItem(at: staging)
        return out
    }

    /// Merges a backup zip into Documents. Returns the number of files restored.
    static func restore(from zipURL: URL) -> Int {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("tinbox-restore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let accessed = zipURL.startAccessingSecurityScopedResource()
        defer { if accessed { zipURL.stopAccessingSecurityScopedResource() } }
        guard GBAEmulatorCore.extractZip(at: zipURL, toDirectory: tmp) > 0 else { return 0 }

        // The zip may wrap everything in a top-level "Tinbox Backup" folder.
        var root = tmp
        if let only = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil),
           only.count == 1, (try? only[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
           !["Saves", "States", "Cheats"].contains(only[0].lastPathComponent) {
            root = only[0]
        }
        var restored = 0
        for folder in ["Saves", "States", "Cheats"] {
            let src = root.appendingPathComponent(folder, isDirectory: true)
            guard let enumerator = FileManager.default.enumerator(at: src, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for case let url as URL in enumerator {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { continue }
                let rel = url.path.replacingOccurrences(of: src.path, with: "")
                let dest = FileLocations.documents.appendingPathComponent(folder).appendingPathComponent(rel)
                try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: dest)
                if (try? FileManager.default.copyItem(at: url, to: dest)) != nil { restored += 1 }
            }
        }
        return restored
    }
}

/// UIActivityViewController wrapper for the share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
