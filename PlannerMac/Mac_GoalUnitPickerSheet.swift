import SwiftUI
import SwiftData

// MARK: - Mac_GoalUnitCatalog
//
// Bridges a `CaptureParser`-detected unit token (a bare string like "pages" or
// "dollars") to a concrete `GoalUnit`. Single source of truth for both the
// direct capture path (unit already detected) and the picker sheet (unit was
// ambiguous). Mirrors the symbol/decimal conventions of the shared
// `UnitCategory.allOptions` catalog so a parser-built goal is indistinguishable
// from one created in `Mac_AddGoalSheet`.

enum Mac_GoalUnitCatalog {

    /// Tokens offered in the ambiguous-unit picker, in display order.
    static let pickerTokens = ["pages", "words", "dollars", "miles", "km", "hours", "reps"]

    /// Map a detected token to a concrete `GoalUnit`. Unknown tokens fall back
    /// to a clean custom unit using the token itself as label + symbol.
    static func unit(for token: String) -> GoalUnit {
        switch token {
        case "pages":   return .custom(label: "Pages", symbol: "pages", allowsDecimals: false, isPrefixSymbol: false)
        case "words":   return .custom(label: "Words", symbol: "words", allowsDecimals: false, isPrefixSymbol: false)
        case "dollars": return .custom(label: "USD", symbol: "$", allowsDecimals: true, isPrefixSymbol: true)
        case "miles":   return .custom(label: "Miles", symbol: "mi", allowsDecimals: true, isPrefixSymbol: false)
        case "km":      return .custom(label: "Kilometers", symbol: "km", allowsDecimals: true, isPrefixSymbol: false)
        case "hours":   return .custom(label: "Hours", symbol: "hrs", allowsDecimals: true, isPrefixSymbol: false)
        case "reps":    return .custom(label: "Reps", symbol: "reps", allowsDecimals: false, isPrefixSymbol: false)
        default:        return .custom(label: token.capitalized, symbol: token, allowsDecimals: false, isPrefixSymbol: false)
        }
    }
}

// MARK: - Mac_PendingGoal
//
// Carrier for a goal awaiting a unit choice. `Identifiable` so it drives a
// `.sheet(item:)` presentation from the capture bar. `dueDate` is carried for
// completeness but not persisted — `PersistedGoal` has no deadline field today.

struct Mac_PendingGoal: Identifiable {
    let id = UUID()
    let title: String
    let targetValue: Double
    let dueDate: Date?
}

// MARK: - Mac_GoalUnitPickerSheet
//
// Shown when the capture bar parses a goal but couldn't infer its unit
// ("save 5000", "read 200"). A compact dark form echoing `Mac_AddGoalSheet`:
// the goal title + target read-only at the top, a unit menu, and a mint Confirm
// pill. On confirm it hands the chosen `GoalUnit` back to the caller, which owns
// the insert (service-layer / model-context symmetry stays with the capture bar).

struct Mac_GoalUnitPickerSheet: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dismiss) private var dismiss

    let pending: Mac_PendingGoal
    var onConfirm: (GoalUnit) -> Void

    @State private var token: String = Mac_GoalUnitCatalog.pickerTokens.first ?? "pages"

    var body: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: 18) {
            Text("Choose a Unit")
                .font(p.font(.title))
                .foregroundStyle(p.textPrimary)

            // Goal preview — what was captured, awaiting its measure.
            VStack(alignment: .leading, spacing: 4) {
                Text(pending.title.isEmpty ? "Untitled goal" : pending.title)
                    .font(.system(size: 16, weight: .semibold, design: p.fontDesign))
                    .foregroundStyle(p.textPrimary)
                    .lineLimit(1)
                Text("Target · \(targetText)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(p.textTertiary)
            }

            field(label: "Unit", palette: p) {
                Picker("", selection: $token) {
                    ForEach(Mac_GoalUnitCatalog.pickerTokens, id: \.self) { t in
                        Text(Mac_GoalUnitCatalog.unit(for: t).label).tag(t)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Mac_Accent.mint)
            }

            HStack(spacing: 12) {
                Spacer(minLength: 0)
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    onConfirm(Mac_GoalUnitCatalog.unit(for: token))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 420)
        .themedCanvas(p)
    }

    private var targetText: String {
        let v = pending.targetValue
        return v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v)
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
}
