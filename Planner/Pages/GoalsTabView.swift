import SwiftUI
import SwiftData

// MARK: - GoalsTabView (1.3 Unified Hierarchy)
//
// Phase 2 redesign: drops the Habits / Milestones segmented picker in favour
// of a single scrolling canvas that shows:
//
//   1. YOUR GOALS — active PersistedGoal rows with their linked child routines
//      (PersistedHabit.anchorGoalID == goal.id) nested immediately beneath.
//   2. STANDALONE ROUTINES — habits with no parent goal (anchorGoalID == nil),
//      plus any orphaned habits whose parent goal no longer exists.
//
// All user-facing copy says "Routine", never "Habit". The SwiftData model
// name (`PersistedHabit`) is intentionally unchanged for migration safety.

struct GoalsTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeStore.self) private var theme

    @Query(sort: \PersistedGoal.sortOrder) private var goals: [PersistedGoal]
    @Query(sort: \PersistedHabit.sortOrder) private var habits: [PersistedHabit]

    @State private var isPresentingAdd: Bool = false
    @State private var isPresentingArchive: Bool = false
    @State private var selectedGoalID: UUID? = nil
    @State private var rekindleHabit: PersistedHabit?

    private let spring = Animation.spring(response: 0.35, dampingFraction: 0.7)
    private let exitSpring = Animation.spring(duration: 0.25)

    var body: some View {
        let p = theme.palette
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
                        .padding(.top, DesignTokens.Spacing.pageTop)
                        .padding(.bottom, 20)

                    goalsWithRoutinesSection
                        .padding(.bottom, DesignTokens.Spacing.stackLarge)

                    if !standaloneRoutines.isEmpty {
                        standaloneRoutinesSection
                    }

                    Spacer(minLength: DesignTokens.Spacing.pageBottom)
                }
            }
            .scrollIndicators(.hidden)
            .animation(spring, value: activeGoals.map(\.id))
            .animation(spring, value: habits.filter { !$0.isArchived }.map(\.id))
            .livingCanvas(p)
            .navigationTitle("Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { archiveButton }
                ToolbarItem(placement: .topBarTrailing) { plusButton }
            }
            .sheet(isPresented: $isPresentingArchive) {
                GoalsArchiveView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(p.sheetBackground)
                    .presentationCornerRadius(DesignTokens.Radius.sheet)
            }
            .sheet(isPresented: $isPresentingAdd) {
                AddGoalSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(
                        p.id == .liquidGlass
                            ? AnyShapeStyle(.clear)
                            : AnyShapeStyle(p.sheetBackground)
                    )
                    .presentationCornerRadius(DesignTokens.Radius.sheet)
            }
            .sheet(item: Binding(
                get: { selectedGoalID.map(IdentifiedID.init) },
                set: { selectedGoalID = $0?.id }
            )) { id in
                if let goal = goals.first(where: { $0.id == id.id }) {
                    UpdateGoalSheet(goal: goal)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .presentationBackground(DesignTokens.Background.canvas)
                        .presentationCornerRadius(DesignTokens.Radius.sheet)
                }
            }
            .sheet(item: $rekindleHabit) { habit in
                RekindleStreakSheet(habit: habit)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(p.sheetBackground)
                    .presentationCornerRadius(DesignTokens.Radius.sheet)
            }
        }
        .onChange(of: goals.map(\.currentValue)) { _, _ in
            WidgetSnapshotPublisher.publishGoals(goals)
        }
        .onChange(of: goals.map(\.id)) { _, _ in
            WidgetSnapshotPublisher.publishGoals(goals)
        }
        .onAppear {
            WidgetSnapshotPublisher.publishGoals(goals)
        }
    }

    // MARK: Header

    private var header: some View {
        let p = theme.palette
        return VStack(alignment: .leading, spacing: 10) {
            Text("Goals")
                .font(p.font(.display))
                .tracking(p.displayTracking)
                .foregroundStyle(p.textPrimary)

            Text(headerMeta)
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .textCase(.uppercase)
                .monospacedDigit()
                .foregroundStyle(p.textSecondary)
        }
    }

    private var headerMeta: String {
        let g = activeGoals.count
        let r = habits.filter { !$0.isArchived }.count
        return "\(g) goal\(g == 1 ? "" : "s") · \(r) routine\(r == 1 ? "" : "s")"
    }

    // MARK: Section 1 — Active Goals with linked routines

    @ViewBuilder
    private var goalsWithRoutinesSection: some View {
        subSectionHeader("Your Goals", count: activeGoals.count)
            .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
            .padding(.bottom, 12)

        if activeGoals.isEmpty {
            StarkEmptyState(
                "No goals in flight.",
                footnote: "Tap + to define your first goal."
            )
            .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
        } else {
            RowSeparator()
            ForEach(activeGoals) { goal in
                goalHierarchyBlock(for: goal)
                RowSeparator()
            }
        }
    }

    @ViewBuilder
    private func goalHierarchyBlock(for goal: PersistedGoal) -> some View {
        let linked = linkedRoutines(for: goal)
        VStack(spacing: 0) {
            GoalIncrementSwipeRow(
                onIncrement: { GoalMutator.increment(goal, with: exitSpring) },
                trailing: StarkSwipeAction(
                    systemImage: "archivebox",
                    label: "Abandon",
                    perform: { abandon(goal) }
                ),
                isAtCeiling: goal.currentValue >= goal.targetValue
            ) {
                GoalRowCell(goal: goal) { selectedGoalID = goal.id }
                    .contextMenu {
                        Button { abandon(goal) } label: {
                            Label("Abandon", systemImage: "archivebox")
                        }
                    }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity
            ))

            if !linked.isEmpty {
                // Hairline connecting the goal card to its routines.
                Rectangle()
                    .fill(theme.palette.hairline)
                    .frame(height: 0.5)
                    .padding(.leading, DesignTokens.Spacing.pageHorizontal)

                ForEach(linked) { habit in
                    LinkedRoutineRow(habit: habit)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                    Rectangle()
                        .fill(theme.palette.hairline)
                        .frame(height: 0.5)
                        .padding(.leading, DesignTokens.Spacing.pageHorizontal + 32)
                }
            }
        }
    }

    // MARK: Section 2 — Standalone Routines

    @ViewBuilder
    private var standaloneRoutinesSection: some View {
        subSectionHeader("Standalone Routines", count: standaloneRoutines.count)
            .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
            .padding(.top, 4)
            .padding(.bottom, 12)

        RowSeparator()
        ForEach(standaloneRoutines) { habit in
            HabitSwipeRow(onArchive: { archiveHabit(habit) }) {
                HabitCardRow(
                    habit: habit,
                    isEligible: habit.isCompletedToday() || habit.isEligibleForCompletion(on: .now),
                    onComplete: {
                        guard habit.isCompletedToday() || habit.isEligibleForCompletion(on: .now) else { return }
                        withAnimation(exitSpring) { habit.toggleToday() }
                    },
                    onRekindle: { rekindleHabit = habit }
                )
                .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
                .padding(.vertical, 6)
                .contextMenu {
                    Button { archiveHabit(habit) } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity
            ))
            RowSeparator()
        }
    }

    // MARK: Shared chrome

    private func subSectionHeader(_ title: String, count: Int) -> some View {
        let p = theme.palette
        return HStack(spacing: 0) {
            Text(title)
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .textCase(.uppercase)
                .foregroundStyle(p.textPrimary)

            Text("·")
                .font(p.font(.micro))
                .foregroundStyle(p.textTertiary)
                .padding(.horizontal, 8)

            Text("\(count)")
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .monospacedDigit()
                .foregroundStyle(p.textTertiary)

            Spacer(minLength: 0)
        }
    }

    // MARK: Toolbar items

    private var archiveButton: some View {
        let p = theme.palette
        return Button {
            isPresentingArchive = true
            AppHaptic.tap()
        } label: {
            Image(systemName: "archivebox")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(p.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(p.chromeSurface))
                .overlay(Capsule().strokeBorder(p.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Archive")
    }

    private var plusButton: some View {
        let p = theme.palette
        return Button {
            isPresentingAdd = true
            AppHaptic.tap()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(p.textPrimary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(p.chromeSurface))
                .overlay(Circle().strokeBorder(p.prominent, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add Goal")
    }

    // MARK: Filtering

    private var activeGoals: [PersistedGoal] {
        goals.filter { $0.status == .active }
    }

    /// Routines explicitly linked to this goal (non-archived).
    private func linkedRoutines(for goal: PersistedGoal) -> [PersistedHabit] {
        habits.filter { !$0.isArchived && $0.anchorGoalID == goal.id }
    }

    /// Standalone routines: either no parent goal set, or the parent goal
    /// no longer exists in the active workspace (orphaned after deletion).
    private var standaloneRoutines: [PersistedHabit] {
        let activeGoalIDs = Set(activeGoals.map(\.id))
        return habits.filter { habit in
            guard !habit.isArchived else { return false }
            guard let goalID = habit.anchorGoalID else { return true }
            return !activeGoalIDs.contains(goalID)
        }
    }

    // MARK: Mutations

    private func abandon(_ goal: PersistedGoal) {
        GoalMutator.abandon(goal, with: exitSpring)
    }

    private func archiveHabit(_ habit: PersistedHabit) {
        withAnimation(exitSpring) {
            habit.isArchived = true
            habit.updatedAt = .now
        }
    }
}

// MARK: - LinkedRoutineRow
//
// Compact child row rendered beneath a parent goal. Shows the routine's
// cadence meta, title, and the interactive StreakLoop so the user can
// log today's completion without leaving the Goals screen.

private struct LinkedRoutineRow: View {
    @Environment(ThemeStore.self) private var theme
    @Bindable var habit: PersistedHabit

    var body: some View {
        let p = theme.palette
        HStack(spacing: 0) {
            // Visual indent line: 20pt gutter → hairline connector → content
            Rectangle()
                .fill(p.hairline)
                .frame(width: 0.5)
                .frame(maxHeight: .infinity)
                .padding(.leading, 20)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(p.accent.opacity(0.65))

                        Text("Routine · \(habit.cadenceDisplayLabel.uppercased())")
                            .font(p.font(.micro))
                            .tracking(p.microTracking)
                            .textCase(.uppercase)
                            .foregroundStyle(p.textTertiary)
                    }

                    Text(habit.title)
                        .font(p.font(.headline))
                        .tracking(p.headlineTracking)
                        .foregroundStyle(p.textPrimary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                StreakLoop(
                    streak: habit.streakCount,
                    isCompletedToday: habit.isCompletedToday(),
                    palette: p,
                    onTrigger: {
                        withAnimation(.spring(duration: 0.25)) { habit.toggleToday() }
                    }
                )
            }
            .padding(.leading, 14)
            .padding(.trailing, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(p.rowFill)
    }
}

// MARK: - Internal identifier wrapper

private struct IdentifiedID: Identifiable, Equatable {
    let id: UUID
}

#Preview {
    GoalsTabView()
        .environment(ThemeStore())
        .modelContainer(
            for: [PersistedTask.self, PersistedNote.self, PersistedGoal.self, PersistedHabit.self],
            inMemory: true
        )
        .preferredColorScheme(.dark)
}
