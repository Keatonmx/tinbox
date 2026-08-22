//
//  AppModel.swift
//  Tinbox
//
//  Single source of truth for the UI: settings, library, session routing,
//  sheets and toasts. Views only talk to this object and to EmulatorSession.
//

import SwiftUI
import Combine
import UIKit

enum Screen: Equatable {
    case library
    case game
}

enum ActiveSheet: Equatable, Identifiable {
    case quickMenu
    /// Full bottom-sheet quick menu even in landscape ("More…" from the compact dialog).
    case quickMenuFull
    case saveStates
    case cheats
    case settings
    case skins
    case themes
    case retroAchievements
    case raLogin
    case layoutProfiles
    case controllers
    /// Play / load save / patch / remove for `AppModel.selectedGame`.
    case gameActions
    case romFolder
    var id: Self { self }
}

/// Main-thread only (not actor-annotated so plain closures can call it in Swift 5 mode).
final class AppModel: ObservableObject {

    // MARK: Persistent state
    @Published var settings: AppSettings {
        didSet {
            SettingsStore.shared.save(settings)
            session.settings = settings
            ButtonHaptics.shared.enabled = settings.hapticsEnabled
        }
    }
    @Published private(set) var games: [Game] = []
    @Published var profiles: [LayoutProfile] {
        didSet { SettingsStore.shared.saveProfiles(profiles) }
    }

    // MARK: Session state
    let session: EmulatorSession
    @Published private(set) var screen: Screen = .library
    @Published private(set) var currentGame: Game?
    /// Game whose action sheet is open (tapped in the library).
    @Published private(set) var selectedGame: Game?
    @Published var gameData = GameData()
    @Published var activeSheet: ActiveSheet?
    @Published var importKind: ImportKind?
    @Published var isLayoutEditing = false
    /// Rotate button state; actual layout also follows the real orientation.
    @Published var forceLandscape = false
    @Published var showBrightnessOverlay = false
    @Published var toast: String?
    @Published private(set) var lastSyncText: String = "Never"

    var theme: ThemeTokens { ThemeTokens.tokens(for: settings.theme) }
    var skin: ControllerSkin { ControllerSkin.skin(named: settings.skin) }

    private var toastWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    init() {
        let settings = SettingsStore.shared.load()
        self.settings = settings
        self.profiles = SettingsStore.shared.loadProfiles()
        self.session = EmulatorSession(settings: settings)
        ButtonHaptics.shared.enabled = settings.hapticsEnabled
        ROMFolderAccess.shared.activate(bookmark: settings.customROMFolderBookmark)
        refreshLibrary()
        updateSyncText()

        ControllerManager.shared.onMenuPressed = { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.screen == .game else { return }
                if self.activeSheet == nil { self.openSheet(.quickMenu) }
            }
        }
        session.$controllerConnected
            .dropFirst()
            .sink { [weak self] connected in
                self?.showToast(connected ? "Controller connected" : "Controller disconnected")
            }
            .store(in: &cancellables)

        // CI smoke test: `-tinbox-autoplay` boots the first ROM in Documents/ROMs
        // so a simulator screenshot shows real emulator output.
        if CommandLine.arguments.contains("-tinbox-autoplay"), let first = games.first {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.open(first)
                if CommandLine.arguments.contains("-tinbox-landscape") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self?.forceLandscape = true
                        OrientationLock.set(mask: .landscape, rotateTo: .landscapeRight)
                    }
                }
            }
        }
    }

    // MARK: Library

    func refreshLibrary() {
        let hidden = Set(settings.hiddenGameIDs)
        games = GameLibraryStore.shared.loadGames().filter { !hidden.contains($0.id) }
    }

    /// Tapping a library tile opens the game's action sheet.
    func select(_ game: Game) {
        selectedGame = game
        activeSheet = .gameActions
    }

    /// "Continue" from the action sheet: boot and load the newest save state.
    func openAndContinue(_ game: Game) {
        open(game)
        guard currentGame?.id == game.id else { return }
        let slots = gameData.slots.filter { $0.isFilled }
        guard let newest = slots.max(by: { ($0.savedAt ?? .distantPast) < ($1.savedAt ?? .distantPast) }) else { return }
        if session.loadState(slot: newest.index) {
            showToast("Continued from \(newest.name)")
        }
    }

    var selectedGameLatestSave: String? {
        guard let game = selectedGame else { return nil }
        let data = GameLibraryStore.shared.loadGameData(for: game.id)
        guard let newest = data.slots.filter({ $0.isFilled }).max(by: { ($0.savedAt ?? .distantPast) < ($1.savedAt ?? .distantPast) }),
              let date = newest.savedAt else { return nil }
        return "\(newest.name) · \(date.slotTimestampString)"
    }

    func open(_ game: Game) {
        var game = game
        let data = GameLibraryStore.shared.loadGameData(for: game.id)
        do {
            try session.load(game, cheats: data.cheats)
        } catch {
            showToast("Couldn't load \(game.title)")
            return
        }
        // Fill in header info on first boot.
        let info = session.runner.withCore { ($0.gameTitle, $0.gameCode) }
        game.internalTitle = info.0
        game.gameCode = info.1
        game.lastPlayed = Date()
        updateGame(game)

        currentGame = game
        gameData = data
        forceLandscape = false
        activeSheet = nil
        selectedGame = nil
        screen = .game
        session.start()

        // Auto-suspend recovery: if the app was killed mid-session, resume it.
        let suspend = FileLocations.suspendState(gameID: game.id)
        if FileManager.default.fileExists(atPath: suspend.path) {
            if session.loadState(from: suspend) {
                showToast("Resumed suspended session")
            }
            try? FileManager.default.removeItem(at: suspend)
        }
    }

    func exitGame() {
        guard let game = currentGame else { return }
        var autosaved = false
        if session.isRunning {
            autosaved = session.saveState(slot: 0)
            if autosaved {
                gameData.slots[0].savedAt = Date()
                persistGameData()
            }
        }
        session.stop()
        // A normal exit supersedes any emergency snapshot from an app switch.
        try? FileManager.default.removeItem(at: FileLocations.suspendState(gameID: game.id))
        activeSheet = nil
        isLayoutEditing = false
        forceLandscape = false
        showBrightnessOverlay = false
        screen = .library
        currentGame = nil
        OrientationLock.set(mask: .portrait, rotateTo: .portrait)
        refreshLibrary()
        if autosaved { showToast("Auto-saved \(game.title)") }
    }

    private func updateGame(_ game: Game) {
        if let i = games.firstIndex(where: { $0.id == game.id }) {
            games[i] = game
        } else {
            games.insert(game, at: 0)
        }
        GameLibraryStore.shared.saveGames(games)
    }

    func deleteGame(_ game: Game) {
        GameLibraryStore.shared.deleteGame(game, deleteFile: !game.isExternal)
        if game.isExternal, !settings.hiddenGameIDs.contains(game.id) {
            settings.hiddenGameIDs.append(game.id)   // the folder is rescanned; keep it out of the list
        }
        games.removeAll { $0.id == game.id }
        GameLibraryStore.shared.saveGames(games)
        if selectedGame?.id == game.id { selectedGame = nil; activeSheet = nil }
        showToast(game.isExternal ? "Removed from library · file kept in \(ROMFolderAccess.shared.displayName)" : "Removed \(game.title)")
    }

    private func persistGameData() {
        guard let game = currentGame else { return }
        GameLibraryStore.shared.saveGameData(gameData, for: game.id)
    }

    // MARK: Sheets / toasts

    func openSheet(_ sheet: ActiveSheet) {
        if screen == .game, activeSheet == nil {
            session.pause()
        }
        activeSheet = sheet
    }

    func closeSheet() {
        activeSheet = nil
        if screen == .game {
            session.resume()
        }
    }

    func showToast(_ message: String) {
        toastWork?.cancel()
        withAnimation(.easeOut(duration: 0.25)) { toast = message }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeIn(duration: 0.25)) { self?.toast = nil }
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    // MARK: Quick menu actions

    func saveToAutoSlot() {
        guard !settings.raHardcore else { showToast("Save states are off in Hardcore mode"); return }
        if session.saveState(slot: 0) {
            gameData.slots[0].savedAt = Date()
            persistGameData()
            closeSheet()
            showToast("State saved · Auto")
        } else {
            showToast("Couldn't save state")
        }
    }

    func save(toSlot index: Int) {
        guard !settings.raHardcore else { showToast("Save states are off in Hardcore mode"); return }
        if session.saveState(slot: index) {
            gameData.slots[index].savedAt = Date()
            persistGameData()
            showToast("Saved to \(gameData.slots[index].name)")
        } else {
            showToast("Couldn't save state")
        }
    }

    func load(fromSlot index: Int) {
        guard !settings.raHardcore else { showToast("Save states are off in Hardcore mode"); return }
        if session.loadState(slot: index) {
            closeSheet()
            showToast("Loaded \(gameData.slots[index].name)")
        } else {
            showToast("Couldn't load state")
        }
    }

    func rewindTenSeconds() {
        guard settings.rewindEnabled else { showToast("Rewind is off in Settings"); return }
        guard !settings.raHardcore else { showToast("Rewind is off in Hardcore mode"); return }
        if session.rewind(seconds: 10) {
            closeSheet()
            showToast("Rewound 10 seconds")
        } else {
            showToast("Nothing to rewind yet")
        }
    }

    func toggleFastForward() {
        session.isFastForward.toggle()
    }

    /// A quick tap on » (no slide) — the button is a scrubber now.
    func showFastForwardHint() {
        showToast("Hold » and slide: ◀ rewind · fast-forward ▶")
        if !settings.hasSeenFastForwardHint { settings.hasSeenFastForwardHint = true }
    }

    /// Quick Menu "Load": the most recently saved slot, one tap.
    func loadLatestState() {
        guard !settings.raHardcore else { showToast("Save states are off in Hardcore mode"); return }
        guard let slot = gameData.slots.filter({ $0.isFilled }).max(by: { ($0.savedAt ?? .distantPast) < ($1.savedAt ?? .distantPast) }) else {
            showToast("No saved state yet · use Save first")
            return
        }
        load(fromSlot: slot.index)
    }

    /// Subtitle for the Quick Menu "Load" tile.
    var latestStateDescription: String {
        guard let slot = gameData.slots.filter({ $0.isFilled }).max(by: { ($0.savedAt ?? .distantPast) < ($1.savedAt ?? .distantPast) }),
              let date = slot.savedAt else { return "Nothing saved yet" }
        return "\(slot.name) · \(date.slotTimestampString)"
    }

    func toggleSectionCollapsed(_ name: String) {
        if let i = settings.collapsedSections.firstIndex(of: name) {
            settings.collapsedSections.remove(at: i)
        } else {
            settings.collapsedSections.append(name)
        }
    }

    func setSpeed(_ speed: Double) {
        settings.ffSpeed = speed
        session.ffSpeed = speed
    }

    // MARK: Cheats

    func addCheat(name: String, code: String, type: CheatType) -> Bool {
        let name = name.trimmingCharacters(in: .whitespaces)
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !code.isEmpty else { showToast("Enter a name and code"); return false }
        guard GBAEmulatorCore.validateCheatCode(code, type: type.coreType) else {
            showToast("That doesn't look like a \(type.label) code")
            return false
        }
        gameData.cheats.append(Cheat(name: name, code: code.uppercased(), type: type, enabled: true))
        persistGameData()
        applyCheats()
        showToast("Cheat added")
        return true
    }

    func toggleCheat(_ cheat: Cheat) {
        guard let i = gameData.cheats.firstIndex(where: { $0.id == cheat.id }) else { return }
        gameData.cheats[i].enabled.toggle()
        persistGameData()
        session.setCheat(at: i, enabled: gameData.cheats[i].enabled)
    }

    func deleteCheat(_ cheat: Cheat) {
        gameData.cheats.removeAll { $0.id == cheat.id }
        persistGameData()
        applyCheats()
    }

    private func applyCheats() {
        if settings.raHardcore {
            session.applyCheats([])
        } else {
            session.applyCheats(gameData.cheats)
        }
    }

    var activeCheatCount: Int { gameData.cheats.filter(\.enabled).count }

    // MARK: Imports

    func handlePicked(_ urls: [URL], kind: ImportKind) {
        importKind = nil
        switch kind {
        case .rom:
            importROMs(urls)
        case .saveState:
            guard let game = currentGame else { return }
            let loaded = importSaveFiles(urls, for: game, running: true)
            if loaded.state != nil || loaded.battery { activeSheet = .saveStates }
        case .saveForGame:
            guard let game = selectedGame else { return }
            let loaded = importSaveFiles(urls, for: game, running: false)
            // Start the game on what was just imported.
            if loaded.battery || loaded.state != nil {
                open(game)
                if let slot = loaded.state, currentGame?.id == game.id {
                    _ = session.loadState(slot: slot)
                }
            }
        case .bios:
            guard let url = urls.first else { return }
            importBIOS(url)
        case .patchForGame:
            guard let url = urls.first, let game = selectedGame else { return }
            createPatchedCopy(of: game, patchURL: url)
        case .romFolder:
            guard let url = urls.first else { return }
            chooseROMFolder(url)
        }
    }

    private func importROMs(_ urls: [URL]) {
        var imported = 0
        var movedCount = 0
        for url in urls {
            do {
                let result = try GameLibraryStore.shared.importROM(from: url, move: settings.importMode == .move)
                settings.hiddenGameIDs.removeAll { $0 == result.game.id }
                if !games.contains(where: { $0.id == result.game.id }) {
                    games.insert(result.game, at: 0)
                }
                imported += 1
                if result.movedOriginal { movedCount += 1 }
            } catch {
                showToast(error.localizedDescription)
            }
        }
        guard imported > 0 else { return }
        GameLibraryStore.shared.saveGames(games)
        let where_ = ROMFolderAccess.shared.displayName
        if settings.importMode == .move {
            if movedCount == imported {
                showToast(imported == 1 ? "Moved to \(where_)" : "Moved \(imported) ROMs to \(where_)")
            } else {
                showToast("Copied to \(where_) · original couldn't be removed")
            }
        } else {
            showToast(imported == 1 ? "Copied to \(where_)" : "Copied \(imported) ROMs to \(where_)")
        }
    }

    /// Imports .sav (battery) / .sst (state) files for `game`. Returns what was
    /// imported; `state` is the slot index a save state landed in.
    @discardableResult
    private func importSaveFiles(_ urls: [URL], for game: Game, running: Bool) -> (battery: Bool, state: Int?) {
        var data = running ? gameData : GameLibraryStore.shared.loadGameData(for: game.id)
        var battery = false
        var stateSlot: Int?
        for url in urls {
            let ext = url.pathExtension.lowercased()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            if FileLocations.batteryExtensions.contains(ext) {
                // Battery save: replace <rom>.sav in mGBA's save dir.
                let base = (game.fileName as NSString).deletingPathExtension
                let dest = FileLocations.saves.appendingPathComponent("\(base).sav")
                if running { session.pause() }
                try? FileManager.default.removeItem(at: dest)
                if (try? FileManager.default.copyItem(at: url, to: dest)) != nil {
                    battery = true
                    if running {
                        // Reload so the core maps the new file.
                        try? session.load(game, cheats: data.cheats)
                        session.start()
                    }
                    showToast("Loaded in-game save")
                }
                if running { session.resume() }
            } else if FileLocations.stateExtensions.contains(ext) {
                guard let slot = data.slots.first(where: { !$0.isFilled }) ?? data.slots.last else { continue }
                let dest = FileLocations.stateFile(gameID: game.id, slot: slot.index)
                try? FileManager.default.removeItem(at: dest)
                if (try? FileManager.default.copyItem(at: url, to: dest)) != nil {
                    data.slots[slot.index].savedAt = Date()
                    stateSlot = slot.index
                    showToast("Save state placed in \(slot.name)")
                }
            } else {
                showToast("Only .sav and .sst files")
            }
        }
        if running {
            gameData = data
            persistGameData()
        } else {
            GameLibraryStore.shared.saveGameData(data, for: game.id)
        }
        return (battery, stateSlot)
    }

    private func createPatchedCopy(of game: Game, patchURL: URL) {
        showToast("Patching…")
        let accessed = patchURL.startAccessingSecurityScopedResource()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try GameLibraryStore.shared.createPatchedCopy(of: game, patchURL: patchURL) }
            if accessed { patchURL.stopAccessingSecurityScopedResource() }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let patched):
                    self.refreshLibrary()
                    if let i = self.games.firstIndex(where: { $0.id == patched.id }) {
                        self.games[i].title = patched.title
                        GameLibraryStore.shared.saveGames(self.games)
                    }
                    self.activeSheet = nil
                    self.showToast("Saved \(patched.fileName) · original untouched")
                case .failure(let error):
                    self.showToast(error.localizedDescription)
                }
            }
        }
    }

    private func chooseROMFolder(_ url: URL) {
        guard let bookmark = ROMFolderAccess.shared.adopt(folder: url) else {
            showToast("Couldn't access that folder"); return
        }
        settings.customROMFolderBookmark = bookmark
        settings.customROMFolderName = url.lastPathComponent
        refreshLibrary()
        showToast("ROM folder: \(url.lastPathComponent)")
    }

    func useDefaultROMFolder() {
        ROMFolderAccess.shared.release()
        settings.customROMFolderBookmark = nil
        settings.customROMFolderName = nil
        refreshLibrary()
        showToast("ROM folder: Tinbox › ROMs")
    }

    private func importBIOS(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let dest = FileLocations.bios.appendingPathComponent("gba_bios.bin")
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
        } catch {
            showToast("Couldn't copy BIOS"); return
        }
        // Validate through the core (GBAIsBIOS).
        let ok = session.runner.withCore { $0.setBIOSFile(dest) }
        if ok {
            settings.biosFileName = "gba_bios.bin"
            settings.bootMode = .biosFile
            if session.isRunning {
                // Explicit core->loadBIOS + reset so the imported BIOS is used right away.
                _ = session.runner.withCore { $0.loadBIOSNow() }
                showToast("BIOS imported · game restarted")
            } else {
                showToast("BIOS imported")
            }
        } else {
            try? FileManager.default.removeItem(at: dest)
            settings.bootMode = .hle
            showToast("Not a valid gba_bios.bin")
        }
    }

    // MARK: Cloud

    func syncNow() {
        guard settings.cloudProvider != .off else { showToast("Turn on iCloud or Google Drive first"); return }
        showToast("Syncing with \(settings.cloudProvider.rawValue)…")
        session.flushSaveData()
        CloudSync.shared.syncNow(using: settings.cloudProvider) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let summary):
                self.settings.lastCloudSync = Date()
                self.updateSyncText()
                self.showToast("Synced · ↑\(summary.uploaded) ↓\(summary.downloaded)")
                if self.screen == .game { self.gameData = GameLibraryStore.shared.loadGameData(for: self.currentGame?.id ?? "") }
            case .failure(let error):
                self.showToast(error.localizedDescription)
            }
        }
    }

    private func updateSyncText() {
        guard let date = settings.lastCloudSync else { lastSyncText = "Never synced"; return }
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        lastSyncText = minutes < 1 ? "Last synced just now" : (minutes < 60 ? "Last synced \(minutes) min ago" : "Last synced \(date.relativeLibraryString)")
    }

    // MARK: Hardcore

    func setHardcore(_ on: Bool) {
        settings.raHardcore = on
        applyCheats()
        showToast(on ? "Hardcore on · states & cheats disabled" : "Hardcore off")
    }

    // MARK: Layout profiles

    var currentProfile: LayoutProfile {
        let name = currentGame?.layoutProfile ?? LayoutProfile.defaultName
        return profiles.first { $0.name == name } ?? profiles.first ?? .default
    }

    func saveLayout(portrait: ControlLayout?, landscape: ControlLayout?) {
        var profile = currentProfile
        if let portrait { profile.portrait = portrait.sanitized(fallback: .portraitDefault) }
        if let landscape { profile.landscape = landscape.sanitized(fallback: .landscapeDefault) }
        if let i = profiles.firstIndex(where: { $0.name == profile.name }) {
            profiles[i] = profile
        } else {
            profiles.append(profile)
        }
    }

    func resetLayout() {
        var profile = currentProfile
        profile.portrait = .portraitDefault
        profile.landscape = .landscapeDefault
        if let i = profiles.firstIndex(where: { $0.name == profile.name }) { profiles[i] = profile }
        showToast("Layout reset")
    }

    func createProfile(named name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !profiles.contains(where: { $0.name == name }) else { return }
        var p = currentProfile
        p.name = name
        profiles.append(p)
        assignProfile(name)
    }

    func assignProfile(_ name: String) {
        guard var game = currentGame else { return }
        game.layoutProfile = name == LayoutProfile.defaultName ? nil : name
        currentGame = game
        updateGame(game)
        showToast("Using \(name) layout")
    }

    func deleteProfile(_ name: String) {
        guard name != LayoutProfile.defaultName else { return }
        profiles.removeAll { $0.name == name }
        if currentGame?.layoutProfile == name { assignProfile(LayoutProfile.defaultName) }
    }

    // MARK: Scene phase

    func sceneDidBecomeInactive() {
        guard screen == .game, session.isRunning else { return }
        if settings.autoSuspendSave {
            session.writeSuspendState()
        }
        session.flushSaveData()
        if activeSheet == nil { session.pause() }
    }

    func sceneDidBecomeActive() {
        // Still alive, so the emergency snapshot is no longer needed.
        if let game = currentGame {
            try? FileManager.default.removeItem(at: FileLocations.suspendState(gameID: game.id))
        }
        guard screen == .game, session.isRunning, activeSheet == nil, !isLayoutEditing else { return }
        session.resume()
    }

    func sceneDidEnterBackground() {
        session.flushSaveData()
    }
}

// MARK: - Orientation helper

enum OrientationLock {
    /// Sets the orientations the app currently allows (read by AppDelegate) and
    /// optionally asks the window scene to rotate right away.
    static func set(mask: UIInterfaceOrientationMask, rotateTo preferred: UIInterfaceOrientationMask? = nil) {
        AppDelegate.orientationMask = mask
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        if let preferred {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: preferred)) { _ in }
        }
    }
}
