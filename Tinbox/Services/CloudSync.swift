//
//  CloudSync.swift
//  Tinbox
//
//  Cloud saves: mirrors Documents/Saves (battery .sav) and Documents/States
//  to a cloud folder and back, newest-modification-date wins.
//
//  - iCloud: the app's ubiquity container (requires the iCloud Documents
//    capability + `com.apple.developer.ubiquity-container-identifiers` in
//    Tinbox.entitlements; both are already declared, enable iCloud for the
//    App ID in your developer account).
//  - Google Drive: needs the GoogleSignIn SDK and a client ID. The provider
//    protocol is in place; `GoogleDriveSyncProvider` currently reports that it
//    is not configured instead of silently doing nothing.
//

import Foundation

protocol CloudSyncProvider {
    var name: String { get }
    /// Returns the remote root folder, creating it if needed.
    func remoteRoot() throws -> URL
}

enum CloudSyncError: LocalizedError {
    case notAvailable(String)
    var errorDescription: String? {
        switch self {
        case .notAvailable(let reason): return reason
        }
    }
}

struct ICloudSyncProvider: CloudSyncProvider {
    let name = "iCloud"
    func remoteRoot() throws -> URL {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            throw CloudSyncError.notAvailable("iCloud Drive is not available. Sign in to iCloud and enable iCloud Drive for Tinbox.")
        }
        let root = container.appendingPathComponent("Documents/Tinbox", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

struct GoogleDriveSyncProvider: CloudSyncProvider {
    let name = "Google Drive"
    func remoteRoot() throws -> URL {
        // Integration point: add the GoogleSignIn Swift package, sign in with
        // the drive.file scope, and mirror files through the Drive REST API.
        throw CloudSyncError.notAvailable("Google Drive sync needs the GoogleSignIn SDK and a client ID (see CloudSync.swift).")
    }
}

final class CloudSync: @unchecked Sendable {
    static let shared = CloudSync()
    private let queue = DispatchQueue(label: "com.redfernsoutpost.tinbox.cloudsync", qos: .utility)
    private var dirty = false

    func markDirty() {
        dirty = true
    }

    func provider(for setting: CloudProvider) -> CloudSyncProvider? {
        switch setting {
        case .off: return nil
        case .iCloud: return ICloudSyncProvider()
        case .googleDrive: return GoogleDriveSyncProvider()
        }
    }

    struct Summary {
        var uploaded = 0
        var downloaded = 0
    }

    /// Two-way mirror of Saves and States. Completion is called on the main thread.
    func syncNow(using setting: CloudProvider, completion: @escaping (Result<Summary, Error>) -> Void) {
        guard let provider = provider(for: setting) else {
            DispatchQueue.main.async { completion(.failure(CloudSyncError.notAvailable("Cloud saves are off."))) }
            return
        }
        queue.async {
            do {
                let remote = try provider.remoteRoot()
                var summary = Summary()
                for folder in ["Saves", "States"] {
                    let local = FileLocations.documents.appendingPathComponent(folder, isDirectory: true)
                    let remoteFolder = remote.appendingPathComponent(folder, isDirectory: true)
                    try FileManager.default.createDirectory(at: remoteFolder, withIntermediateDirectories: true)
                    try self.mirror(from: local, to: remoteFolder, counter: &summary.uploaded)
                    try self.mirror(from: remoteFolder, to: local, counter: &summary.downloaded)
                }
                self.dirty = false
                DispatchQueue.main.async { completion(.success(summary)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    /// Copies every file in `source` (recursively) into `destination` when the
    /// source copy is newer or the destination copy is missing.
    private func mirror(from source: URL, to destination: URL, counter: inout Int) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { return }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            let relative = url.path.replacingOccurrences(of: source.path, with: "")
            let target = destination.appendingPathComponent(relative)
            if values.isDirectory == true {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }
            let sourceDate = values.contentModificationDate ?? .distantPast
            let targetDate = (try? target.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if sourceDate > targetDate.addingTimeInterval(1) {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try fm.copyItem(at: url, to: target)
                counter += 1
            }
        }
    }
}
