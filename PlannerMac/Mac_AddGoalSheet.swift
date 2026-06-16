import SwiftUI
import SwiftData

// MARK: - Mac_AddGoalSheet
//
// Mac-native goal create / edit form. Goal creation never flowed through the
// capture bar (CaptureParser has no goal intent — the iOS path is a dedicated
// AddGoalSheet), and the iOS sheet's unit picker is touch-first, so Mac gets
// this minimal form: title, target value, and a unit picker drawn from the
// shared `UnitCategory.allOptions` catalog.
//
// Creation inserts directly via the model context — the same pattern the Mac
// capture bar uses for tasks. Lifecycle mutations (abandon / delete /
// increment) still route through `GoalMutator`; a fresh insert is not a
// mutation. No recurrence, no templates, no tint picker (Color → hex
// serialization is iOS-only today, so a Mac-picked tint would not persist).

struct Mac_AddGoalSheet: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Non-nil → edit that goal in place; nil → create a new goal.
    private let existing: PersistedGoal?

    @State private var title: String
    @State private var targetText: String
    @State private var unitOptionID: String

    init(existing: PersistedGoal? = nil) {
        self.existing = existing
        _title = State(initialValue: existing?.title ?? "")
        _unitOptionID = State(initialValue: UnitCategory.allOptions.first?.id ?? "")
        if let existing {
            _targetText = State(initialValue: Self.numberText(existing.targetValue,
                                                              decimals: existing.unit.allowsDecimals))
        } else {
            _targetText = State(initialValue: "")
        }
    }

    private var isEditing: Bool { existing != nil }

    private var selectedOption: UnitOption {
        UnitCategory.option(id: unitOptionID) ?? UnitCategory.allOptions[0]
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: 18) {
            Text(isEditing ? "Edit Goal" : "New Goal")
                .font(p.font(.title))
                .foregroundStyle(p.textPrimary)

            field(label: "Title", palette: p) {
                TextField("e.g. Read 12 books", text: $title)
                    .textFieldStyle(.plain)
                    .font(p.font(.body))
                    .foregroundStyle(p.textPrimary)
                    .tint(Mac_Accent.mint)
            }

            // Unit is fixed once a goal exists — editing it would orphan the
            // stored progress value's meaning, so the picker is create-only.
            if !isEditing {
                field(label: "Unit", palette: p) {
                    Picker("", selection: $unitOptionID) {
                        ForEach(UnitCategory.allOptions) { opt in
                            Text(opt.title).tag(opt.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(Mac_Accent.mint)
                }
            }

            field(label: "Target", palette: p) {
                HStack(spacing: 8) {
                    TextField(targetPlaceholder, text: $targetText)
                        .textFieldStyle(.plain)
                        .font(p.font(.body))
                        .foregroundStyle(p.textPrimary)
                        .tint(Mac_Accent.mint)
                    Text(unitSymbol)
                        .font(p.font(.micro))
                        .foregroundStyle(p.textTertiary)
                }
            }

            HStack(spacing: 12) {
                Spacer(minLength: 0)
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button(isEditing ? "Save" : "Create") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedTitle.isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 420)
        .themedCanvas(p)
    }

    private var unitSymbol: String {
        isEditing ? (existing?.unit.symbol ?? "") : selectedOption.symbol
    }

    private var targetPlaceholder: String {
        isEditing ? "" : Self.numberText(selectedOption.defaultTarget,
                                         decimals: selectedOption.allowsDecimals)
    }

    @ViewBuilder
    private func field<Content: View>(label: String, palette p: ThemePalette,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .foregroundStyle(p.textSecondary)
            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous).fill(p.rowFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                        .strokeBorder(p.hairline)
                )
        }
    }

    // MARK: Commit

    private func commit() {
        guard !trimmedTitle.isEmpty else { return }

        if let existing {
            existing.title = trimmedTitle
            if let t = parsedTarget, t > 0 { existing.targetValue = t }
            existing.lastUpdatedAt = .now
        } else {
            let option = selectedOption
            let target: Double = {
                if let t = parsedTarget, t > 0 { return t }
                return option.defaultTarget
            }()
            let goal = PersistedGoal(
                title: trimmedTitle,
                unit: option.goalUnit,
                currentValue: 0,
                targetValue: target
            )
            modelContext.insert(goal)
        }

        // Commit immediately so the @Query-backed Goals pane updates without
        // waiting for the autosave coalescing window.
        try? modelContext.save()
        dismiss()
    }

    private var parsedTarget: Double? {
        Double(targetText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func numberText(_ v: Double, decimals: Bool) -> String {
        if decimals {
            return v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v)
        }
        return String(Int(v.rounded()))
    }
}
