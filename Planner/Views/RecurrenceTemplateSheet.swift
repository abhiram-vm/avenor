import SwiftUI

// MARK: - RecurrenceTemplateSheet
//
// Browser for pre-built recurrence patterns ("Smart Recurrence Templates").
// Presented from the recurrence card's "Browse →" affordance in the
// routine-creation flow. Selecting a row fires `onSelect` with the chosen
// template and dismisses — the host applies `template.rule` to the chip
// matrix with the overshooting `DesignTokens.Motion.springy` so the chips
// visibly snap into their new state.
//
// Templates are additive: this sheet never mutates anything itself, so the
// manual chip matrix keeps working exactly as before.

struct RecurrenceTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeStore.self) private var theme

    /// The template the host currently has applied, if any — rendered with
    /// an accent ring so re-opening the browser shows the active choice.
    var selected: RecurrenceTemplate? = nil
    let onSelect: (RecurrenceTemplate) -> Void

    var body: some View {
        let p = theme.palette
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(RecurrenceTemplate.allCases) { template in
                        templateRow(template, palette: p)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
                .padding(.top, DesignTokens.Spacing.pageTop)
                .padding(.bottom, DesignTokens.Spacing.pageBottom)
            }
            .scrollIndicators(.hidden)
            .livingCanvas(p)
            .navigationTitle("Quick Templates")
            .avenorInlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(p.textSecondary)
                }
            }
            #if os(iOS)
            .toolbarColorScheme(p.colorScheme, for: .navigationBar)
            #endif
        }
        .preferredColorScheme(p.colorScheme)
        .tint(p.controlTint)
    }

    // MARK: Row

    private func templateRow(_ template: RecurrenceTemplate, palette p: ThemePalette) -> some View {
        Button {
            AppHaptic.pop()
            onSelect(template)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: template.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(p.accent)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 4) {
                    Text(template.rawValue)
                        .font(.system(size: 16, weight: .semibold, design: p.fontDesign))
                        .tracking(p.headlineTracking)
                        .foregroundStyle(p.textPrimary)

                    Text(template.description)
                        .font(p.font(.micro))
                        .tracking(p.microTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(p.textTertiary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(p.textTertiary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 60)
            .inputSurface(p, filled: true, emphasized: template == selected)
            .contentShape(Rectangle())
        }
        .buttonStyle(KineticButtonStyle(pressedScale: 0.97))
        .accessibilityLabel(Text(template.rawValue))
        .accessibilityHint(Text(template.description))
        .accessibilityAddTraits(template == selected ? .isSelected : [])
    }
}
