//
//  CoverArt.swift
//  Tinbox
//
//  Box art for the Library. First choice: a user-supplied image in
//  Documents/Covers/<game id>.png. Otherwise the libretro-thumbnails project
//  (https://github.com/libretro-thumbnails) is tried — it hosts covers for
//  nearly every GBA / GB / GBC release, keyed by the No-Intro file name, which
//  is usually what a ROM is called. Results are cached in Covers/.
//

import Foundation
import UIKit

final class CoverArtService {
    static let shared = CoverArtService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = ["User-Agent": "Tinbox/1.0 (iOS)"]
        return URLSession(configuration: config)
    }()
    private var inFlight: Set<String> = []
    private let lock = NSLock()

    /// Marker written when every candidate 404s so we don't retry each launch.
    private func missMarker(for id: String) -> URL {
        FileLocations.covers.appendingPathComponent("\(id).none")
    }

    /// Kicks off a download if no cover exists yet. `completion` is called on
    /// the main thread only when a new image was stored.
    func fetchIfNeeded(for game: Game, completion: @escaping () -> Void) {
        if FileLocations.coverImage(gameID: game.id) != nil { return }
        if FileManager.default.fileExists(atPath: missMarker(for: game.id).path) { return }
        lock.lock()
        if inFlight.contains(game.id) { lock.unlock(); return }
        inFlight.insert(game.id)
        lock.unlock()

        let candidates = Self.candidateURLs(for: game)
        tryNext(candidates, index: 0, game: game, completion: completion)
    }

    private func tryNext(_ urls: [URL], index: Int, game: Game, completion: @escaping () -> Void) {
        guard index < urls.count else {
            try? Data().write(to: missMarker(for: game.id))
            finish(game.id)
            return
        }
        session.dataTask(with: urls[index]) { [weak self] data, response, _ in
            guard let self else { return }
            if let data, (response as? HTTPURLResponse)?.statusCode == 200, UIImage(data: data) != nil {
                let dest = FileLocations.covers.appendingPathComponent("\(game.id).png")
                try? data.write(to: dest, options: .atomic)
                self.finish(game.id)
                DispatchQueue.main.async(execute: completion)
            } else {
                self.tryNext(urls, index: index + 1, game: game, completion: completion)
            }
        }.resume()
    }

    private func finish(_ id: String) {
        lock.lock(); inFlight.remove(id); lock.unlock()
    }

    /// Forget a cached miss so the next refresh retries (e.g. after a rename).
    func clearMiss(for game: Game) {
        try? FileManager.default.removeItem(at: missMarker(for: game.id))
    }

    // MARK: Name matching

    private static let systems: [String: [String]] = [
        "gba": ["Nintendo_-_Game_Boy_Advance"],
        "agb": ["Nintendo_-_Game_Boy_Advance"],
        "gbc": ["Nintendo_-_Game_Boy_Color", "Nintendo_-_Game_Boy"],
        "gb":  ["Nintendo_-_Game_Boy", "Nintendo_-_Game_Boy_Color"],
        "sgb": ["Nintendo_-_Game_Boy"],
        "zip": ["Nintendo_-_Game_Boy_Advance", "Nintendo_-_Game_Boy_Color", "Nintendo_-_Game_Boy"],
    ]

    /// libretro-thumbnails replaces characters that are illegal in file names.
    static func thumbnailName(_ name: String) -> String {
        var out = name
        for ch in ["&", "*", "/", ":", "`", "<", ">", "?", "\\", "|"] {
            out = out.replacingOccurrences(of: ch, with: "_")
        }
        return out
    }

    static func candidateURLs(for game: Game) -> [URL] {
        let ext = (game.fileName as NSString).pathExtension.lowercased()
        let repos = systems[ext] ?? systems["gba"]!
        let base = (game.fileName as NSString).deletingPathExtension
        var names: [String] = [base]
        // Fallbacks: the cleaned title with common region tags.
        let title = game.title
        if title != base {
            for region in ["(USA)", "(USA, Europe)", "(Europe)", "(Japan)", "(World)"] {
                names.append("\(title) \(region)")
            }
        }
        var urls: [URL] = []
        for repo in repos {
            for name in names {
                let file = thumbnailName(name) + ".png"
                guard let encoded = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                      let url = URL(string: "https://raw.githubusercontent.com/libretro-thumbnails/\(repo)/master/Named_Boxarts/\(encoded)") else { continue }
                urls.append(url)
            }
        }
        return urls
    }

    // MARK: Manual covers

    /// Stores a user-chosen image (any format) as the game's cover.
    func setCover(for game: Game, from url: URL) -> Bool {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return false }
        // Normalise to a square-ish PNG no larger than 600px on the long side.
        let maxSide: CGFloat = 600
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let png = resized.pngData() else { return false }
        for ext in ["png", "jpg", "jpeg"] {
            try? FileManager.default.removeItem(at: FileLocations.covers.appendingPathComponent("\(game.id).\(ext)"))
        }
        try? FileManager.default.removeItem(at: missMarker(for: game.id))
        return (try? png.write(to: FileLocations.covers.appendingPathComponent("\(game.id).png"), options: .atomic)) != nil
    }

    func removeCover(for game: Game) {
        for ext in ["png", "jpg", "jpeg"] {
            try? FileManager.default.removeItem(at: FileLocations.covers.appendingPathComponent("\(game.id).\(ext)"))
        }
        // Remember not to re-download automatically.
        try? Data().write(to: missMarker(for: game.id))
    }
}
