//
//  StarterGames.swift
//  Tinbox
//
//  Free homebrew games preinstalled on first launch so the tin isn't empty.
//  Which games ship depends on the edition: the App Store build carries only
//  permissively licensed ROMs (MIT / CC BY); CI deletes the GPL and AGPL ones
//  from Resources/StarterGames before archiving, and everything here adapts
//  to whatever is actually in the bundle. Licence texts live in
//  Resources/Licenses/starter-*.txt and are shown in About › Included games.
//

import Foundation

enum StarterGames {
    struct Game {
        /// Bundle resource name, split for Bundle.main lookup. The file name
        /// is also what lands in Documents/ROMs, so it is the library title.
        let file: String
        let ext: String
        let title: String
        let author: String
        let licenceLabel: String
        let licenceFile: String
        let note: String
        let sourceURL: String

        var fileName: String { "\(file).\(ext)" }
    }

    /// Everything Tinbox can ship. Presence in the bundle decides what a
    /// given build actually seeds and credits.
    static let all: [Game] = [
        Game(file: "Tobu Tobu Girl Deluxe", ext: "gb",
             title: "Tobu Tobu Girl Deluxe", author: "Tangram Games",
             licenceLabel: "MIT · CC BY 4.0", licenceFile: "starter-tobu",
             note: "Game Boy arcade platformer by Tangram Games. Code MIT, art and music CC BY 4.0.",
             sourceURL: "https://github.com/SimonLarsen/tobutobugirl-dx"),
        Game(file: "Pong Brew", ext: "gba",
             title: "Pong Brew", author: "ZeroDayArcade",
             licenceLabel: "MIT", licenceFile: "starter-pong",
             note: "A simple pong for the GBA by ZeroDayArcade, built as a homebrew lesson.",
             sourceURL: "https://github.com/ZeroDayArcade/Pong-Homebrew-GBA"),
        Game(file: "Apotris", ext: "gba",
             title: "Apotris", author: "akouzoukos",
             licenceLabel: "AGPL-3.0", licenceFile: "starter-apotris",
             note: "Block stacking game by akouzoukos.",
             sourceURL: "https://gitea.com/akouzoukos/apotris"),
        Game(file: "BlindJump", ext: "gba",
             title: "BlindJump", author: "Evan Bowman",
             licenceLabel: "MIT · GPL", licenceFile: "starter-blindjump",
             note: "Action adventure by Evan Bowman. The GBA build is distributed under the GPL.",
             sourceURL: "https://github.com/evanbowman/blind-jump-portable"),
    ]

    /// The games present in this build, with their bundle URLs.
    static var bundled: [(game: Game, url: URL)] {
        all.compactMap { game in
            Bundle.main.url(forResource: game.file, withExtension: game.ext).map { (game, $0) }
        }
    }

    private static let seededKey = "starterGamesSeeded"

    /// Copies the bundled games into the ROM folder, once per install.
    /// Deleting one afterwards is respected: we never re-seed.
    static func seedIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: seededKey) else { return }
        defaults.set(true, forKey: seededKey)
        let fm = FileManager.default
        try? fm.createDirectory(at: FileLocations.roms, withIntermediateDirectories: true)
        for (game, url) in bundled {
            let dest = FileLocations.roms.appendingPathComponent(game.fileName)
            guard !fm.fileExists(atPath: dest.path) else { continue }
            try? fm.copyItem(at: url, to: dest)
        }
    }
}
