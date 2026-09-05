//
//  Edition.swift
//  Tinbox
//
//  One switch, two builds. Sideload builds ship everything; CI flips `store`
//  to true for the App Store binary, which launches lean and keeps the gated
//  features below as ready-made "New in 1.x" updates. Every gate is one line
//  to lift when its update ships.
//

enum Edition {
    /// Flipped to true by CI for the App Store build. Never commit as true.
    static let store = false

    // Feature gates: all on for sideload, held back in the store's v1.0.
    static var speedrunTimer: Bool { !store }
    static var postcards: Bool { !store }
    static var gbCamera: Bool { !store }
    static var saveInsight: Bool { !store }
    static var retroAchievements: Bool { !store }
    static var gameClock: Bool { !store }
    static var secretTheme: Bool { !store }
}
