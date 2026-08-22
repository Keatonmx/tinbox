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

        // Merge with what is actually on disk (the user may have added files via Files.app).
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: FileLocations.roms, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey], options: [.skipsHiddenFiles])) ?? []
        var result: [Game] = []
        var seen = Set<String>()
        for url in files where FileLocations.romExtensions.contains(url.pathExtension.lowercased()) {
            let fileName = url.lastPathComponent
            let id = Game.makeID(fileName: fileName)
            seen.insert(id)
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
            let size = Int64(values?.fileSize ?? 0)
            if var existing = known[id] {
                existing.fileName = fileName
                existing.fileSize = size
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
                    coverHue: Self.hue(for: id)))
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

    /// Copies a picked ROM into Documents/ROMs and returns the new Game.
    func importROM(from sourceURL: URL) throws -> Game {
        FileLocations.createAll()
        let ext = sourceURL.pathExtension.lowercased()
        guard FileLocations.romExtensions.contains(ext) else {
            throw ImportError.unsupportedType(ext)
        }
        let dest = FileLocations.uniqueURL(in: FileLocations.roms, preferredName: sourceURL.lastPathComponent)
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
        try FileManager.default.copyItem(at: sourceURL, to: dest)
        let size = (try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let fileName = dest.lastPathComponent
        let id = Game.makeID(fileName: fileName)
        return Game(id: id, fileName: fileName, title: Game.prettyTitle(fromFileName: fileName),
                    fileSize: size, addedAt: Date(), lastPlayed: nil, layoutProfile: nil,
                    patchFileName: nil, internalTitle: nil, gameCode: nil, coverHue: Self.hue(for: id))
    }

    func deleteGame(_ game: Game) {
        try? FileManager.default.removeItem(at: game.romURL)
        try? FileManager.default.removeItem(at: FileLocations.stateDirectory(for: game.id))
    }

    enum ImportError: LocalizedError {
        case unsupportedType(String)
        var errorDescription: String? {
            switch self {
            case .unsupportedType(let ext): return "Unsupported file type .\(ext)"
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
