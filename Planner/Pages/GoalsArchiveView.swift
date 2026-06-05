import SwiftUI
import SwiftData

// MARK: - GoalsArchiveView (Sophisticated Stark)
//
// Sheet-presented historical view of abandoned goals. Rows render at ~0.40
// opacity so the page reads as past intent. Leading swipe = restore (goal
// returns to the active workspace with its `currentValue` intact). Trailing
// swipe = permanent purge from SwiftData (rigid haptic).
//
// No tap-to-edit, no scrub, no +1 — abandoned goals are read-only history.

struct GoalsArchiveView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeStore.self) private var theme

    @Query(sort: \PersistedGoal.abandonedAt, order: .reverse) private var allGoals: [PersistedGoal]

    private let spring = Animation.spring(response: 0.35, dampingFraction: 0.7)

    var body: some View {
        let p = theme.palette
        NavigationStack {
            ZStack {
                p.canvasView

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        header
                            .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
                            .padding(.top, DesignTokens.Spacing.pageTop)
                            .padding(.bottom, DesignTokens.Spacing.stackLarge)

                        if abandoned.isEmpty {
                            StarkEmptyState(
                                "Archive empty.",
                                footnote: "Abandoned goals land here."
                            )
                            .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
                        } else {
                            separator
                            ForEach(abandoned) { goal in
                                StarkSwipeRow(
                                    leading: StarkSwipeAction(
                                        systemImage: "arrow.uturn.backward",
                                        label: "Restore",
                                        perform: { restore(goal) }
                                    ),
                                    trailing: StarkSwipeAction(
                                        systemImage: "trash",
                                        label: "Purge",
                                        perform: { purge(goal) }
                                    )
                                ) {
                                    AbandonedGoalRow(goal: goal, onRestore: { restore(goal) })
                                }
                                .transition(.asymmetric(
                                    insertion: .opacity,
                                    removal: .opacity.combined(with: .move(edge: .leading))
                                ))
                                separator
                            }
                            Spacer(minLength: DesignTokens.Spacing.pageBottom)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .animation(spring, value: abandoned.map(\.id))
            }
            .navigationTitle("Goals Archive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .font(p.font(.micro))
                        .tracking(p.microTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(p.textPrimary)
                }
            }
        }
    }

    private var header: some View {
        let p = theme.palette
        return VStack(alignment: .leading, spacing: 10) {
            Text("Archive")
                .font(p.font(.display))
                .tracking(p.displayTracking)
                .foregroundStyle(p.textPrimary)

            HStack(spacing: 0) {
                Text("Abandoned")
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(p.textSecondary)

                Text("·")
                    .font(p.font(.micro))
                    .foregroundStyle(p.textTertiary)
                    .padding(.horizontal, 8)

                Text("\(abandoned.count) record\(abandoned.count == 1 ? "" : "s")")
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .textCase(.uppercase)
                    .monospacedDigit()
                    .foregroundStyle(p.textSecondary)

                Spacer(minLength: 0)
            }
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(theme.palette.hairline)
            .frame(height: 0.5)
    }

    private var abandoned: [PersistedGoal] {
        allGoals.filter { $0.isAbandoned }
    }

    private func purge(_ goal: PersistedGoal) {
        GoalMutator.delete(goal, in: modelContext, with: spring)
    }

    private func restore(_ goal: PersistedGoal) {
        GoalMutator.restore(goal, with: spring)
    }
}

// MARK: - AbandonedGoalRow
//
// Demoted variant of GoalRowCell. Tint rail, title, and meta all drop to
// ~0.40 opacity. Includes a monospaced "ABANDONED [DATE]" stamp.

struct AbandonedGoalRow: View {
    @Environment(ThemeStore.self) private var theme
    let goal: PersistedGoal
    let onRestore: () -> Void

    private static let abandonFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("MMMd jmm")
        return f
    }()

    var body: some View {
        let p = theme.palette
        HStack(spacing: 0) {
            Rectangle()
                .fill(goal.tint.opacity(0.40))
                .frame(width: 2)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                metaStrip
                Text(goal.title.isEmpty ? "Untitled" : goal.title)
                    .font(p.font(.headline))
                    .tracking(p.headlineTracking)
                    .foregroundStyle(p.textTertiary)
                    .strikethrough(true, color: p.textTertiary)
                    .lineLimit(1)

                progressBar(p)
            }
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(p.rowFill)
        .contextMenu {
            Button {
                onRestore()
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
        }
    }

    private var metaStrip: some View {
        HStack(spacing: 0) {
            metaToken("Goal")

            separator
            metaToken("\(goal.currentText) / \(goal.targetText)", monospaced: true)

            separator
            metaToken(abandonText, monospaced: true)

            Spacer(minLength: 0)
        }
    }

    private func metaToken(_ text: String, monospaced: Bool = false) -> some View {
        let p = theme.palette
        return Text(text)
            .font(p.font(.micro))
            .tracking(p.microTracking)
            .textCase(.uppercase)
            .conditionalMonospaced(monospaced)
            .foregroundStyle(p.textTertiary)
            .lineLimit(1)
    }

    private var separator: some View {
        let p = theme.palette
        return Text("·")
            .font(p.font(.micro))
            .foregroundStyle(p.textTertiary)
            .padding(.horizontal, 8)
    }

    private var abandonText: String {
        if let abandoned = goal.abandonedAt {
            return "Abandoned \(Self.abandonFormatter.string(from: abandoned))"
        }
        return "Abandoned"
    }

    private func progressBar(_ p: ThemePalette) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(p.hairline)
                Rectangle()
                    .fill(goal.tint.opacity(0.40))
                    .frame(width: max(0, min(1, goal.progress)) * geo.size.width)
            }
        }
        .frame(height: 2)
    }
}

#Preview {
    GoalsArchiveView()
        .environment(ThemeStore())
        .modelContainer(
            for: [PersistedTask.self, PersistedNote.self, PersistedGoal.self],
            inMemory: true
        )
        .preferredColorScheme(.dark)
}
