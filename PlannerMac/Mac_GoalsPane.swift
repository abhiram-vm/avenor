import SwiftUI
import SwiftData

// MARK: - Mac_GoalsPane
//
// Functional stub: active goals with a hairline progress bar (no system
// ProgressView, in keeping with the Stark design ethos). Read-only for now.

struct Mac_GoalsPane: View {
    @Environment(ThemeStore.self) private var theme
    @Query(sort: \PersistedGoal.sortOrder) private var goals: [PersistedGoal]

    private var activeGoals: [PersistedGoal] {
        goals.filter { $0.status == .active }
    }

    var body: some View {
        let p = theme.palette
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if activeGoals.isEmpty {
                    Text("No active goals. Capture one above.")
                        .font(p.font(.body))
                        .foregroundStyle(p.textTertiary)
                        .padding(.vertical, 28)
                } else {
                    ForEach(activeGoals) { goal in
                        card(goal, palette: p)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .themedCanvas(p)
        .navigationTitle("Goals")
    }

    @ViewBuilder
    private func card(_ goal: PersistedGoal, palette p: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(goal.title)
                    .font(p.font(.headline))
                    .foregroundStyle(p.textPrimary)
                Spacer(minLength: 0)
                Text("\(Int((goal.progress * 100).rounded()))%")
                    .font(p.font(.micro))
                    .foregroundStyle(p.textSecondary)
            }

            Text("\(goal.currentText) / \(goal.targetText)")
                .font(p.font(.body))
                .foregroundStyle(p.textSecondary)

            // Hairline progress bar — transform/opacity only, no system control.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(p.textTertiary.opacity(0.25))
                    Capsule()
                        .fill(goal.displayTint)
                        .frame(width: max(0, min(1, goal.progress)) * geo.size.width)
                }
            }
            .frame(height: 3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.rowFill)
        )
    }
}
