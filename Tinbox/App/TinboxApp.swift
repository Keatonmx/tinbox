//
//  TinboxApp.swift
//  Tinbox — a lightweight GBA emulator by Redfern's Outpost.
//

import SwiftUI
import UIKit

@main
struct TinboxApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.session)
                .environment(\.theme, model.theme)
                .environment(\.skin, model.skin)
                .preferredColorScheme(.dark)
                .statusBarHidden(model.screen == .game)
                .persistentSystemOverlays(model.screen == .game ? .hidden : .automatic)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .inactive: model.sceneDidBecomeInactive()
            case .active: model.sceneDidBecomeActive()
            case .background: model.sceneDidEnterBackground()
            @unknown default: break
            }
        }
    }
}

/// Only needed to make the orientation mask dynamic: portrait in the library,
/// portrait + landscape in game (the rotate buttons flip it).
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationMask: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationMask
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                theme.bg.ignoresSafeArea()

                switch model.screen {
                case .library:
                    LibraryView()
                        .transition(.opacity)
                case .game:
                    GameContainerView()
                        // Controls must never animate from a zero-size first pass.
                        .transaction { $0.animation = nil }
                        .transition(.opacity)
                }

                sheetHost(landscape: landscape)

                if let toast = model.toast {
                    VStack {
                        Spacer()
                        ToastView(message: toast)
                            .padding(.bottom, landscape ? 60 : 110)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(60)
                    .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: model.screen)
            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: model.activeSheet)
        }
        .sheet(item: Binding(get: { model.importKind.map(ImportRequest.init) }, set: { if $0 == nil { model.importKind = nil } })) { request in
            DocumentPicker(kind: request.kind,
                           onPick: { model.handlePicked($0, kind: request.kind) },
                           onCancel: { model.importKind = nil })
                .ignoresSafeArea()
        }
        .sheet(item: Binding(get: { model.shareURL.map(ShareItem.init) }, set: { if $0 == nil { model.shareURL = nil } })) { item in
            ShareSheet(items: [item.url]).ignoresSafeArea()
        }
        .onChange(of: model.screen) { screen in
            if screen == .game {
                OrientationLock.set(mask: .allButUpsideDown)
            } else {
                OrientationLock.set(mask: .portrait, rotateTo: .portrait)
            }
        }
    }

    @ViewBuilder
    private func sheetHost(landscape: Bool) -> some View {
        if let sheet = model.activeSheet {
            Group {
                switch sheet {
                case .quickMenu:
                    if landscape && model.screen == .game {
                        LandscapeQuickMenu { model.openSheet(.quickMenuFull) }
                    } else {
                        QuickMenuSheet()
                    }
                case .quickMenuFull:
                    QuickMenuSheet()
                case .saveStates: SaveStatesSheet()
                case .cheats: CheatsSheet()
                case .settings: SettingsSheet()
                case .skins: SkinsSheet()
                case .themes: ThemesSheet()
                case .retroAchievements: RetroAchievementsSheet()
                case .raLogin: RALoginSheet()
                case .layoutProfiles: LayoutProfilesSheet()
                case .controllers: ControllersSheet()
                case .gameActions: GameActionsSheet()
                case .romFolder: ROMFolderSheet()
                }
            }
            .zIndex(40)
        }
    }
}

private struct ImportRequest: Identifiable {
    let kind: ImportKind
    var id: String { kind.title }
}

private struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.path }
}
