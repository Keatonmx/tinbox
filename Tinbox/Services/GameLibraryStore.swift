//
//  GameLibraryStore.swift
//  Tinbox
//
//  Scans Documents/ROMs, merges with persisted metadata, and stores per-game
//  data (save slots, cheats) as JSON next to the states.
//

import Foundation
import UIKit

final class GameLibraryStore {
    static let shared = GameLibraryStore()

    private var indexURL: URL { FileLocations.library.appendingPathComponent("library.json") }
    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    // MARK: Library index

    func loadGames() -> [Game] {
        FileLocations.createAll()
        var known: [String: Game] = [:]
        if let data = try? Data(contentsOf: indexURL),
           let games = try? decoder.decode([Game].self, from: data) {
            for g in games { known[g.id] = g }
        }

        // Merge with what is actually on disk (the user may have added files via
        // Files.app) — the default folder plus the user's chosen folder, if any.
        let fm = FileManager.default
        let defaultFiles = (try? fm.contentsOfDirectory(at: FileLocations.roms, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey], options: [.skipsHiddenFiles])) ?? []
        let scan: [(URL, Bool)] = defaultFiles.map { ($0, false) } + ROMFolderAccess.shared.customFolderROMs().map { ($0, true) }
        var result: [Game] = []
        var seen = Set<String>()
        for (url, external) in scan where FileLocations.romExtensions.contains(url.pathExtension.lowercased()) {
            let fileName = url.lastPathComponent
            let id = (external ? "ext-" : "") + Game.makeID(fileName: fileName)
            if seen.contains(id) { continue }
            seen.insert(id)
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
            let size = Int64(values?.fileSize ?? 0)
            if var existing = known[id] {
                existing.fileName = fileName
                existing.fileSize = size
                existing.externalPath = external ? url.path : nil
                result.append(existing)
            } else {
                result.append(Game(
                    id: id,
                    fileName: fileName,
                    title: Game.prettyTitle(fromFileName: fileName),
                    fileSize: size,
                    addedAt: values?.creationDate ?? Date(),
                    lastPlayed: nil,
                    layoutProfile: nil,
                    patchFileName: nil,
                    internalTitle: nil,
                    gameCode: nil,
                    coverHue: Self.hue(for: id),
                    externalPath: external ? url.path : nil))
            }
        }
        result.sort { ($0.lastPlayed ?? $0.addedAt) > ($1.lastPlayed ?? $1.addedAt) }
        saveGames(result)
        return result
    }

    func saveGames(_ games: [Game]) {
        if let data = try? encoder.encode(games) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    struct ImportResult {
        let game: Game
        /// True when the original file was removed (move succeeded).
        let movedOriginal: Bool
    }

    /// Brings a picked ROM into the library folder (the default Documents/ROMs or
    /// the user's chosen folder). With `move`, the original is deleted afterwards
    /// when the provider allows it; otherwise it is left in place.
    func importROM(from sourceURL: URL, move: Bool) throws -> ImportResult {
        FileLocations.createAll()
        let ext = sourceURL.pathExtension.lowercased()
        guard FileLocations.romExtensions.contains(ext) else {
            throw ImportError.unsupportedType(ext)
        }
        let folder = ROMFolderAccess.shared.activeFolderURL
        let external = ROMFolderAccess.shared.isCustom
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        // Already inside the library folder? Just register it.
        if sourceURL.standardizedFileURL.deletingLastPathComponent() == folder.standardizedFileURL {
            return ImportResult(game: makeGame(for: sourceURL, external: external), movedOriginal: false)
        }

        let dest = FileLocations.uniqueURL(in: folder, preferredName: sourceURL.lastPathComponent)
        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: sourceURL, options: [], error: &coordinatorError) { readURL in
            do { try FileManager.default.copyItem(at: readURL, to: dest) } catch { copyError = error }
        }
        if let coordinatorError { throw coordinatorError }
        if let copyError { throw copyError }

        var moved = false
        if move {
            var deleteError: NSError?
            NSFileCoordinator().coordinate(writingItemAt: sourceURL, options: .forDeleting, error: &deleteError) { writeURL in
                moved = (try? FileManager.default.removeItem(at: writeURL)) != nil
            }
        }
        return ImportResult(game: makeGame(for: dest, external: external), movedOriginal: moved)
    }

    private func makeGame(for url: URL, external: Bool) -> Game {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let fileName = url.lastPathComponent
        let id = (external ? "ext-" : "") + Game.makeID(fileName: fileName)
        return Game(id: id, fileName: fileName, title: Game.prettyTitle(fromFileName: fileName),
                    fileSize: size, addedAt: Date(), lastPlayed: nil, layoutProfile: nil,
                    patchFileName: nil, internalTitle: nil, gameCode: nil, coverHue: Self.hue(for: id),
                    externalPath: external ? url.path : nil)
    }

    /// Writes a patched ROM next to the original as a new, permanent library entry.
    /// The original file is never modified.
    func createPatchedCopy(of game: Game, patchURL: URL) throws -> Game {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("tinbox-patch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        // A throwaway core so the running game (if any) is untouched; its save
        // directory is the temp folder so no real .sav is opened twice.
        guard let core = GBAEmulatorCore(saveDirectory: tmp, stateDirectory: tmp, screenshotDirectory: tmp) else {
            throw ImportError.patchFailed("Emulator core unavailable")
        }
        try core.loadROM(at: game.romURL)
        guard core.applyPatch(at: patchURL) else {
            core.unloadROM()
            throw ImportError.patchFailed("The patch doesn't match this ROM")
        }
        guard let data = core.copyROMData() else {
            core.unloadROM()
            throw ImportError.patchFailed("Couldn't read the patched ROM")
        }
        core.unloadROM()

        let patchName = (patchURL.lastPathComponent as NSString).deletingPathExtension
        let base = (game.fileName as NSString).deletingPathExtension
        let folder = game.isExternal ? game.romURL.deletingLastPathComponent() : FileLocations.roms
        let dest = FileLocations.uniqueURL(in: folder, preferredName: "\(base) [\(patchName)].gba")
        try data.write(to: dest, options: .atomic)
        var patched = makeGame(for: dest, external: game.isExternal)
        patched.title = "\(game.title) (\(patchName))"
        return patched
    }

    /// Removes the ROM file and its states. External ROMs (user folder) are
    /// left on disk unless `deleteFile` is set.
    func deleteGame(_ game: Game, deleteFile: Bool) {
        if deleteFile || !game.isExternal {
            try? FileManager.default.removeItem(at: game.romURL)
        }
        try? FileManager.default.removeItem(at: FileLocations.stateDirectory(for: game.id))
    }

    enum ImportError: LocalizedError {
        case unsupportedType(String)
        case patchFailed(String)
        var errorDescription: String? {
            switch self {
            case .unsupportedType(let ext): return "Unsupported file type .\(ext)"
            case .patchFailed(let reason): return reason
            }
        }
    }

    // MARK: Per-game data

    func loadGameData(for gameID: String) -> GameData {
        let url = FileLocations.gameDataFile(gameID: gameID)
        guard let data = try? Data(contentsOf: url),
              var gameData = try? decoder.decode(GameData.self, from: data) else {
            return GameData()
        }
        // Reconcile with files on disk (states may have been imported via Files).
        for i in 0..<SaveSlot.count {
            let file = FileLocations.stateFile(gameID: gameID, slot: i)
            let exists = FileManager.default.fileExists(atPath: file.path)
            if exists, gameData.slots[i].savedAt == nil {
                let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                gameData.slots[i].savedAt = date
            } else if !exists {
                gameData.slots[i].savedAt = nil
            }
        }
        return gameData
    }

    func saveGameData(_ gameData: GameData, for gameID: String) {
        if let data = try? encoder.encode(gameData) {
            try? data.write(to: FileLocations.gameDataFile(gameID: gameID), options: .atomic)
        }
    }

    // MARK: Thumbnails / covers

    func thumbnail(gameID: String, slot: Int) -> UIImage? {
        UIImage(contentsOfFile: FileLocations.stateThumbnail(gameID: gameID, slot: slot).path)
    }

    func writeThumbnail(_ rgba: Data, width: Int, height: Int, gameID: String, slot: Int) {
        guard let image = UIImage.fromRGBA(rgba, width: width, height: height),
              let png = image.pngData() else { return }
        try? png.write(to: FileLocations.stateThumbnail(gameID: gameID, slot: slot), options: .atomic)
    }

    func coverImage(for game: Game) -> UIImage? {
        guard let url = FileLocations.coverImage(gameID: game.id) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private static func hue(for id: String) -> Double {
        var h: UInt32 = 2166136261
        for byte in id.utf8 { h = (h ^ UInt32(byte)) &* 16777619 }
        return Double(h % 360)
    }
}

extension UIImage {
    /// Builds an image from mGBA's native 32-bit buffer (R,G,B,X byte order).
    static func fromRGBA(_ data: Data, width: Int, height: Int) -> UIImage? {
        guard data.count >= width * height * 4 else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo,
                                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
