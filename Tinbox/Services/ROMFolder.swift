//
//  ROMFolder.swift
//  Tinbox
//
//  Where ROMs live. Default: Documents/ROMs (Files › On My iPhone › Tinbox ›
//  ROMs). The user may pick any folder instead; iOS hands us a security-scoped
//  URL which we persist as a bookmark and keep open for the app's lifetime.
//

import Foundation

final class ROMFolderAccess {
    static let shared = ROMFolderAccess()

    private(set) var customFolderURL: URL?
    private var accessing = false

    /// The folder new imports go to and the library scans (in addition to the default).
    var activeFolderURL: URL { customFolderURL ?? FileLocations.roms }
    var displayName: String { customFolderURL?.lastPathComponent ?? "Tinbox › ROMs" }
    var isCustom: Bool { customFolderURL != nil }

    /// Resolves the saved bookmark (if any) and starts security-scoped access.
    func activate(bookmark: Data?) {
        release()
        guard let bookmark else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return }
        if url.startAccessingSecurityScopedResource() {
            accessing = true
        }
        customFolderURL = url
    }

    /// Called with the URL from a folder picker. Returns the bookmark to persist.
    func adopt(folder url: URL) -> Data? {
        release()
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else { return nil }
        activate(bookmark: bookmark)
        return bookmark
    }

    func release() {
        if accessing, let url = customFolderURL {
            url.stopAccessingSecurityScopedResource()
        }
        accessing = false
        customFolderURL = nil
    }

    /// ROM files in the active custom folder (empty when using the default).
    func customFolderROMs() -> [URL] {
        guard let folder = customFolderURL else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey], options: [.skipsHiddenFiles])) ?? []
        return files.filter { FileLocations.romExtensions.contains($0.pathExtension.lowercased()) }
    }
}
