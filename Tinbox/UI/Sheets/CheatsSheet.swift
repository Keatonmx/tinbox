//
//  CheatsSheet.swift
//  Tinbox
//
//  Cheat list with type badges and toggles, plus the inline add form
//  (type segmented control, name field, monospace code field).
//

import SwiftUI

struct CheatsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @State private var adding = false
    @State private var type: CheatType = .gameShark
    @State private var name = ""
    @State private var code = ""
    @FocusState private var focus: Field?

    private enum Field { case name, code }

    var body: some View {
        BottomSheet(maxHeightFraction: 0.72, onDismiss: { model.closeSheet() }) {
            SheetHeader(title: "Cheats", onBack: { model.openSheet(.quickMenu) }) {
                if !adding {
                    TintPill(title: "+ Add") {
                        ButtonHaptics.shared.tap()
                        withAnimation(.easeOut(duration: 0.2)) { adding = true }
                        focus = .name
                    }
                }
            }

            if adding { addForm }

            HuggingScrollView {
                VStack(spacing: 0) {
                    if model.gameData.cheats.isEmpty {
                        Text("No cheats yet · tap + Add")
                            .font(Typography.detail)
                            .foregroundColor(Palette.text40)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 58)
                    }
                    ForEach(Array(model.gameData.cheats.enumerated()), id: \.element.id) { index, cheat in
                        CheatRow(cheat: cheat, isLast: index == model.gameData.cheats.count - 1) {
                            model.toggleCheat(cheat)
                        } onDelete: {
                            model.deleteCheat(cheat)
                        }
                    }
                }
                .background(theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            SegmentedPill(options: CheatType.allCases, label: { $0.label }, selection: $type, fontSize: 12, horizontalPadding: 11)
            field(text: $name, placeholder: "Cheat name", font: .system(size: 15), fieldID: .name)
            field(text: $code, placeholder: "Code (e.g. 3E2A19C4 77F0210B)", font: Typography.mono14, fieldID: .code, mono: true)
            HStack(spacing: 10) {
                Spacer()
                SecondaryPill(title: "Cancel") { cancel() }
                AccentPill(title: "Add Cheat") { submit() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.bottom, 12)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func field(text: Binding<String>, placeholder: String, font: Font, fieldID: Field, mono: Bool = false) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundColor(Palette.textQuaternary))
            .font(font)
            .foregroundColor(.white)
            .tracking(mono ? 0.5 : 0)
            .textInputAutocapitalization(mono ? .characters : .words)
            .autocorrectionDisabled(true)
            .focused($focus, equals: fieldID)
            .submitLabel(fieldID == .name ? .next : .done)
            .onSubmit { if fieldID == .name { focus = .code } else { submit() } }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(theme.well)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Palette.hairline10, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func submit() {
        if model.addCheat(name: name, code: code, type: type) {
            name = ""; code = ""
            withAnimation(.easeOut(duration: 0.2)) { adding = false }
            focus = nil
        }
    }

    private func cancel() {
        ButtonHaptics.shared.tap()
        withAnimation(.easeOut(duration: 0.2)) { adding = false }
        focus = nil
    }
}

private struct CheatRow: View {
    let cheat: Cheat
    let isLast: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(cheat.name).font(Typography.row).foregroundColor(.white).lineLimit(1)
                        Text(cheat.type.label)
                            .font(Typography.badge)
                            .tracking(0.3)
                            .foregroundColor(Palette.textTertiary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.07))
                            .clipShape(Capsule())
                    }
                    Text(cheat.code.replacingOccurrences(of: "\n", with: " · "))
                        .font(Typography.mono12)
                        .tracking(0.5)
                        .foregroundColor(Palette.text40)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                TinboxToggle(isOn: Binding(get: { cheat.enabled }, set: { _ in onToggle() }))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 58)
            .contextMenu {
                Button(role: .destructive) { onDelete() } label: { Label("Delete Cheat", systemImage: "trash") }
            }
            if !isLast { RowSeparator() }
        }
    }
}
