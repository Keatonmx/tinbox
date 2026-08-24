//
//  TimeCapsule.swift
//  Tinbox
//
//  The Time Capsule: automatic playthrough snapshots. The files are the source
//  of truth — `Timeline/cap-<unix-ms>.ss` (a normal save state) plus a PNG of
//  the frame — so moments survive backups and show up in the Files app.
//

import UIKit

/// One automatic snapshot in a game's timeline.
struct CapsuleMoment: Identifiable, Equatable {
    /// Unix milliseconds — also the file name stem.
    let id: Int64
    let gameID: String

    var date: Date { Date(timeIntervalSince1970: Double(id) / 1000) }
    var stateURL: URL { FileLocations.timelineFile(gameID: gameID, timestamp: id) }
    var imageURL: URL { stateURL.deletingPathExtension().appendingPathExtension("png") }
}

final class TimeCapsuleStore {
    static let shared = TimeCapsuleStore()

    /// Snapshots beyond this per game are thinned (oldest first, every other
    /// one), so early history gets sparser instead of vanishing.
    static let cap = 240

    /// All moments for a game, oldest first.
    func moments(for gameID: String) -> [CapsuleMoment] {
        let dir = FileLocations.timelineDirectory(for: gameID)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files.compactMap { name -> CapsuleMoment? in
            guard name.hasPrefix("cap-"), name.hasSuffix(".ss"),
                  let ts = Int64(name.dropFirst(4).dropLast(3)) else { return nil }
            return CapsuleMoment(id: ts, gameID: gameID)
        }.sorted { $0.id < $1.id }
    }

    func count(for gameID: String) -> Int {
        moments(for: gameID).count
    }

    func thumbnail(for moment: CapsuleMoment) -> UIImage? {
        UIImage(contentsOfFile: moment.imageURL.path)
    }

    func writeThumbnail(_ rgba: Data, width: Int, height: Int, to url: URL) {
        guard let image = UIImage.fromRGBA(rgba, width: width, height: height),
              let png = image.pngData() else { return }
        try? png.write(to: url, options: .atomic)
    }

    func totalBytes(for gameID: String) -> Int64 {
        let dir = FileLocations.timelineDirectory(for: gameID)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    func delete(_ moment: CapsuleMoment) {
        try? FileManager.default.removeItem(at: moment.stateURL)
        try? FileManager.default.removeItem(at: moment.imageURL)
    }

    func clear(gameID: String) {
        try? FileManager.default.removeItem(at: FileLocations.timelineDirectory(for: gameID))
    }

    /// Over the cap, drop every other snapshot from the oldest 60% — long-ago
    /// play keeps coarse coverage while recent play stays dense.
    func thinIfNeeded(gameID: String) {
        var all = moments(for: gameID)
        guard all.count > TimeCapsuleStore.cap else { return }
        while all.count > TimeCapsuleStore.cap {
            let oldest = Array(all.prefix(Int(Double(all.count) * 0.6)))
            let victims = stride(from: 1, to: oldest.count, by: 2).map { oldest[$0] }
            guard !victims.isEmpty else { break }
            victims.forEach(delete)
            all = moments(for: gameID)
        }
    }

    /// Moments grouped by calendar day (oldest day first) for the filmstrip.
    func momentsByDay(for gameID: String) -> [(day: String, moments: [CapsuleMoment])] {
        let cal = Calendar.current
        var groups: [(Date, [CapsuleMoment])] = []
        for m in moments(for: gameID) {
            let day = cal.startOfDay(for: m.date)
            if let last = groups.last, last.0 == day {
                groups[groups.count - 1].1.append(m)
            } else {
                groups.append((day, [m]))
            }
        }
        return groups.map { (Self.dayLabel($0.0), $0.1) }
    }

    static func dayLabel(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = cal.isDate(day, equalTo: Date(), toGranularity: .year) ? "MMM d" : "MMM d, yyyy"
        return f.string(from: day)
    }
}
