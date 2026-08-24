//
//  TimeCapsuleSheet.swift
//  Tinbox
//
//  The Time Capsule: a filmstrip of automatic snapshots across the whole
//  playthrough. Select a moment, see it big, jump back to it (the current
//  spot is stashed in the Auto slot first) — or capture one on demand.
//

import SwiftUI

struct TimeCapsuleSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: EmulatorSession
    @Environment(\.theme) private var theme

    @State private var days: [(day: String, moments: [CapsuleMoment])] = []
    @State private var selected: CapsuleMoment?
    @State private var confirmClear = false

    private var gameID: String { model.currentGame?.id ?? "" }
    private var allMoments: [CapsuleMoment] { days.flatMap(\.moments) }

    var body: some View {
        BottomSheet(maxHeightFraction: 0.92, onDismiss: { model.openSheet(.quickMenu) }) {
            SheetHeader(title: "Time Capsule", onBack: { model.openSheet(.quickMenu) }) {
                TintPill(title: "Capture") { captureNow() }
            }
            if allMoments.isEmpty {
                emptyState
            } else {
                HuggingScrollView {
                    VStack(spacing: 0) {
                        if let selected {
                            preview(selected)
                        }
                        filmstrip
                        if let selected {
                            AccentButton(title: "Jump to this moment") { model.jumpToCapsule(selected) }
                                .padding(.top, 14)
                        }
                        footer
                    }
                }
            }
        }
        .onAppear { refresh(selectNewest: true) }
        .confirmationDialog("Clear this game's timeline?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear \(allMoments.count) moments", role: .destructive) {
                TimeCapsuleStore.shared.clear(gameID: gameID)
                refresh(selectNewest: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save-state slots are not affected.")
        }
    }

    // MARK: Pieces

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image("EmptyTin")
                .resizable().scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .opacity(0.9)
            Text("The capsule is still empty").font(Typography.cardTitle).foregroundColor(Palette.text55)
            Text(model.settings.timeCapsuleEnabled
                 ? "While you play, Tinbox keeps a snapshot every \(model.settings.timeCapsuleMinutes) minutes. Come back after a session — or tap Capture to keep this exact moment."
                 : "The Time Capsule is turned off in Settings › Advanced. Tap Capture to keep this exact moment anyway.")
                .font(Typography.meta13).foregroundColor(Palette.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 18)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func preview(_ moment: CapsuleMoment) -> some View {
        VStack(spacing: 8) {
            Group {
                if let image = TimeCapsuleStore.shared.thumbnail(for: moment) {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(session.videoAspect, contentMode: .fit)
                } else {
                    StripedPlaceholder(stripe: theme.stripe2, period: 16, width: 6)
                        .aspectRatio(session.videoAspect, contentMode: .fit)
                        .overlay(Text("snapshot").font(Typography.mono9).foregroundColor(.white.opacity(0.3)))
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.hairline08, lineWidth: 0.5))

            HStack {
                Text(caption(for: moment)).font(Typography.detailSemibold).foregroundColor(.white)
                Spacer()
                if let i = allMoments.firstIndex(of: moment) {
                    Text("\(i + 1) of \(allMoments.count)").font(Typography.meta13).foregroundColor(Palette.text40)
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(.bottom, 12)
    }

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(days, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.day.uppercased())
                                .font(Typography.badge).tracking(0.8)
                                .foregroundColor(Palette.textTertiary)
                            HStack(spacing: 6) {
                                ForEach(group.moments) { moment in
                                    thumb(moment)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
            .onAppear {
                if let last = allMoments.last { proxy.scrollTo(last.id, anchor: .trailing) }
            }
        }
        .frame(height: 86)
        .padding(.vertical, 4)
        .background(theme.well)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.hairline08, lineWidth: 0.5))
    }

    private func thumb(_ moment: CapsuleMoment) -> some View {
        let isSelected = moment == selected
        return Button {
            ButtonHaptics.shared.tap()
            selected = moment
        } label: {
            Group {
                if let image = TimeCapsuleStore.shared.thumbnail(for: moment) {
                    Image(uiImage: image).resizable().interpolation(.none).scaledToFill()
                } else {
                    StripedPlaceholder(stripe: theme.stripe2, period: 12, width: 5)
                }
            }
            .frame(width: 84, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? theme.accent : Palette.hairline08, lineWidth: isSelected ? 2 : 0.5))
            .overlay(alignment: .bottomTrailing) {
                Text(moment.date, format: .dateTime.hour().minute())
                    .font(Typography.badge)
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 4).padding(.vertical, 1.5)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Capsule())
                    .padding(3)
            }
        }
        .buttonStyle(FadePressStyle(opacity: 0.8))
        .id(moment.id)
        .contextMenu {
            Button(role: .destructive) {
                TimeCapsuleStore.shared.delete(moment)
                refresh(selectNewest: selected == moment)
            } label: { Label("Delete this moment", systemImage: "trash") }
        }
    }

    private var footer: some View {
        HStack {
            Text(footerText).font(Typography.meta).foregroundColor(Palette.text40)
            Spacer()
            Button {
                ButtonHaptics.shared.tap()
                confirmClear = true
            } label: {
                Text("Clear…").font(Typography.meta).foregroundColor(Palette.destructive.opacity(0.85))
            }
            .buttonStyle(FadePressStyle())
        }
        .padding(.top, 12)
        .padding(.horizontal, 4)
    }

    private var footerText: String {
        let mb = Double(TimeCapsuleStore.shared.totalBytes(for: gameID)) / 1_048_576
        let cadence = model.settings.timeCapsuleEnabled ? "Every \(model.settings.timeCapsuleMinutes) min while you play" : "Automatic snapshots off"
        return String(format: "%@ · %.1f MB", cadence, mb)
    }

    private func caption(for moment: CapsuleMoment) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEE MMM d jmm")
        return f.string(from: moment.date)
    }

    // MARK: Actions

    private func captureNow() {
        guard session.captureCapsuleMoment() else {
            model.showToast(model.settings.raHardcore ? "Save states are off in Hardcore mode" : "Couldn't capture")
            return
        }
        model.showToast("Moment captured")
        // The PNG is written on a background queue; refresh once it lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { refresh(selectNewest: true) }
    }

    private func refresh(selectNewest: Bool) {
        days = TimeCapsuleStore.shared.momentsByDay(for: gameID)
        let all = allMoments
        if selectNewest || !(selected.map(all.contains) ?? false) {
            selected = all.last
        }
    }
}

/// Full-width accent action button (the Quick Menu's Exit style, in accent).
private struct AccentButton: View {
    @Environment(\.theme) private var theme
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            ButtonHaptics.shared.tap()
            action()
        } label: {
            Text(title)
                .font(Typography.rowSemibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(FadePressStyle(opacity: 0.85))
    }
}
