//
//  RetroAchievements.swift
//  Tinbox
//
//  RetroAchievements account + per-game achievement list via the public
//  dorequest API (the same endpoints rcheevos' rc_client uses):
//    login2   → token + score
//    gameid   → game id for the ROM's MD5
//    patch    → achievement definitions
//    unlocks  → which of them this user already earned
//
//  What is NOT here yet: runtime evaluation of achievement logic (memory
//  watching + unlock submission). That needs the rcheevos C library linked the
//  same way as mGBA; `RetroAchievementsService` is the integration point and
//  Hardcore mode already gates save states/cheats in the UI.
//

import Foundation
import CryptoKit

/// Published state is only mutated on the main actor (see `MainActor.run`).
final class RetroAchievementsService: ObservableObject {
    static let shared = RetroAchievementsService()

    @Published private(set) var user: RAUser?
    @Published private(set) var achievements: [Achievement] = []
    @Published private(set) var gameName: String?
    @Published private(set) var isBusy = false
    @Published private(set) var lastError: String?

    private let base = URL(string: "https://retroachievements.org/dorequest.php")!
    private let userKey = "tinbox.ra.user.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: userKey),
           let user = try? JSONDecoder().decode(RAUser.self, from: data) {
            self.user = user
        }
    }

    var userChipText: String {
        guard let user else { return "Not signed in" }
        let points = NumberFormatter.localizedString(from: NSNumber(value: user.score), number: .decimal)
        return "\(user.username) · \(points) pts"
    }

    // MARK: Account

    func login(username: String, password: String) async {
        await MainActor.run { isBusy = true; lastError = nil }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "r", value: "login2"), .init(name: "u", value: username), .init(name: "p", value: password)]
        var newUser: RAUser?
        var error: String?
        do {
            let (data, _) = try await URLSession.shared.data(from: components.url!)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            if json["Success"] as? Bool == true, let token = json["Token"] as? String {
                newUser = RAUser(username: username, token: token, score: json["Score"] as? Int ?? 0)
            } else {
                error = json["Error"] as? String ?? "Login failed"
            }
        } catch let e {
            error = e.localizedDescription
        }
        let userKey = self.userKey
        await MainActor.run {
            if let newUser {
                self.user = newUser
                UserDefaults.standard.set(try? JSONEncoder().encode(newUser), forKey: userKey)
            }
            self.lastError = error
            self.isBusy = false
        }
    }

    @MainActor
    func logout() {
        user = nil
        achievements = []
        gameName = nil
        UserDefaults.standard.removeObject(forKey: userKey)
    }

    // MARK: Game

    /// Looks up the ROM by MD5 and loads its achievement list + the user's unlocks.
    func loadAchievements(for game: Game, hardcore: Bool) async {
        guard let user else { return }
        await MainActor.run { isBusy = true; lastError = nil }
        var result: [Achievement] = []
        var title: String?
        var error: String?
        do {
            let hash = try Self.md5(of: game.romURL)
            if let gameID = try await request(["r": "gameid", "m": hash])["GameID"] as? Int, gameID > 0 {
                let patch = try await request(["r": "patch", "u": user.username, "t": user.token, "g": "\(gameID)"])
                let patchData = patch["PatchData"] as? [String: Any] ?? [:]
                title = patchData["Title"] as? String
                let defs = patchData["Achievements"] as? [[String: Any]] ?? []
                let unlocks = try await request(["r": "unlocks", "u": user.username, "t": user.token, "g": "\(gameID)", "h": hardcore ? "1" : "0"])
                let earned = Set((unlocks["UserUnlocks"] as? [Int]) ?? [])
                result = defs.compactMap { def in
                    guard let id = def["ID"] as? Int, let name = def["Title"] as? String else { return nil }
                    // Flags 3 == core set; 5 == unofficial.
                    if let flags = def["Flags"] as? Int, flags != 3 { return nil }
                    return Achievement(id: id, title: name,
                                       description: def["Description"] as? String ?? "",
                                       points: def["Points"] as? Int ?? 0,
                                       earned: earned.contains(id),
                                       badgeName: def["BadgeName"] as? String)
                }
            } else {
                error = "This ROM is not in the RetroAchievements database."
            }
        } catch let e {
            error = e.localizedDescription
        }
        await MainActor.run {
            self.gameName = title
            self.achievements = result
            self.lastError = error
            self.isBusy = false
        }
    }

    private func request(_ params: [String: String]) async throws -> [String: Any] {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    static func md5(of url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
