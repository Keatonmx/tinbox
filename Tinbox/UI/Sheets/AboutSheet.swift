//
//  AboutSheet.swift
//  Tinbox
//
//  About · open-source acknowledgements (licence texts bundled from
//  Resources/Licenses) · privacy summary. Required for App Store review: the
//  MPL-2.0 (mGBA), libpng, zlib and inih notices must be viewable in-app.
//

import SwiftUI

struct AboutSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @State private var expanded: String?

    private struct Component: Identifiable {
        let id: String
        let name: String
        let licence: String
        let file: String?
        let note: String
        let url: String
    }

    private let components: [Component] = [
        Component(id: "mgba", name: "mGBA", licence: "MPL-2.0", file: "mgba-MPL-2.0",
                  note: "Game Boy Advance / Game Boy emulation core by endrift and contributors. Tinbox applies a two-line build patch, published with its source.",
                  url: "https://mgba.io"),
        Component(id: "libpng", name: "libpng", licence: "PNG Reference Library License", file: "libpng",
                  note: "Save-state screenshots.", url: "http://www.libpng.org"),
        Component(id: "zlib", name: "zlib & minizip", licence: "zlib License", file: "zlib",
                  note: "Compression and .zip ROM archives.", url: "https://zlib.net"),
        Component(id: "inih", name: "inih", licence: "BSD-3-Clause", file: "inih",
                  note: "Configuration parsing inside mGBA.", url: "https://github.com/benhoyt/inih"),
        Component(id: "thumbs", name: "libretro-thumbnails", licence: "Artwork © respective publishers", file: nil,
                  note: "Optional box-art lookup (Settings › Extras › Box art). Fetched from GitHub only for games without a cover.",
                  url: "https://github.com/libretro-thumbnails"),
        Component(id: "ra", name: "RetroAchievements", licence: "Service", file: nil,
                  note: "Optional sign-in to view achievement lists. Your password is sent only to retroachievements.org.",
                  url: "https://retroachievements.org"),
    ]

    var body: some View {
        BottomSheet(maxHeightFraction: 0.84, onDismiss: { model.openSheet(.settings) }) {
            SheetHeader(title: "About", onBack: { model.openSheet(.settings) }) { EmptyView() }
            HuggingScrollView {
                VStack(spacing: 0) {
                    Card {
                        SettingsRow(title: "Tinbox", subtitle: "by Redfern's Outpost") {
                            Text(AppInfo.versionString).font(Typography.detail).foregroundColor(Palette.text40)
                        }
                        SettingsRow(title: "Emulation core", subtitle: GBAEmulatorCore.coreVersion, showsSeparator: true) { EmptyView() }
                        link("Source code", url: AppInfo.sourceURL, showsSeparator: true)
                        link("Privacy policy", url: AppInfo.privacyURL, showsSeparator: false)
                    }

                    SectionHeader(title: "Privacy")
                    Card {
                        SettingsRow(title: "No accounts, ads or analytics",
                                    subtitle: "Everything stays on your phone. The only network use is the optional box-art download and the optional RetroAchievements sign-in.",
                                    showsSeparator: false) { EmptyView() }
                    }

                    SectionHeader(title: "Open source & credits")
                    Card(bottomSpacing: 0) {
                        ForEach(Array(components.enumerated()), id: \.element.id) { index, c in
                            VStack(spacing: 0) {
                                Button {
                                    ButtonHaptics.shared.tap()
                                    withAnimation(.easeInOut(duration: 0.2)) { expanded = expanded == c.id ? nil : c.id }
                                } label: {
                                    HStack(spacing: 8) {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(c.name).font(Typography.row).foregroundColor(.white)
                                            Text(c.note).font(Typography.rowSubtitle).foregroundColor(Palette.textTertiary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(c.licence).font(Typography.meta).foregroundColor(theme.accentText).multilineTextAlignment(.trailing)
                                        if c.file != nil {
                                            ChevronShape(direction: .right)
                                                .stroke(Palette.textQuaternary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                                .frame(width: 7, height: 12)
                                                .rotationEffect(.degrees(expanded == c.id ? 90 : 0))
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 54)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(RowPressStyle())
                                if expanded == c.id {
                                    VStack(alignment: .leading, spacing: 8) {
                                        if let file = c.file, let text = AppInfo.licenceText(named: file) {
                                            Text(text)
                                                .font(Typography.mono10)
                                                .foregroundColor(Palette.text70)
                                                .textSelection(.enabled)
                                        }
                                        Link(c.url, destination: URL(string: c.url)!)
                                            .font(Typography.meta13).foregroundColor(theme.accentText)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16).padding(.bottom, 12)
                                }
                                if index < components.count - 1 { RowSeparator() }
                            }
                        }
                    }
                }
            }
        }
    }

    private func link(_ title: String, url: String, showsSeparator: Bool) -> some View {
        NavRow(title: title, detail: url.replacingOccurrences(of: "https://", with: ""), showsSeparator: showsSeparator) {
            if let u = URL(string: url) { UIApplication.shared.open(u) }
        }
    }
}

enum AppInfo {
    static let sourceURL = "https://github.com/Keatonmx/tinbox"
    static let privacyURL = "https://github.com/Keatonmx/tinbox/blob/main/PRIVACY.md"

    static var versionString: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    static func licenceText(named name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
