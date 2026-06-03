import SwiftUI
import SwiftData

// MARK: - GoalsTabView (Sophisticated Stark)
//
// `ScrollView + LazyVStack + StarkSwipeRow`. Leading swipe = quick +1
// (or +0.1 for decimal units), capped at target. Trailing swipe = delete.

struct GoalsTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeStore.self) private var theme

    @Query(sort: \PersistedGoal.sortOrder) private var goals: [PersistedGoal]
    // Habits feed owns its own query for rows; this mirror only powers the
    // header meta count when the Habits segment is active.
    @Query(sort: \PersistedHabit.sortOrder) private var habits: [PersistedHabit]

    @State private var searchText: String = ""

    // Unified "Progress" sections. Habits leads (left) to match the feature
    // focus; Milestones holds the original Goals content.
    enum Segment: String, CaseIterable, Identifiable {
        case habits, milestones
        var id: String { rawValue }
        var title: String {
            switch self {
            case .habits:     return "Habits"
            case .milestones: return "Milestones"
            }
        }
    }

    @State private var segment: Segment = .habits
    @Namespace private var segmentNamespace

    enum Filter: String, CaseIterable, Identifiable {
        case all, current, completed
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "All"
            case .current: return "Current"
            case .completed: return "Completed"
            }
        }
    }

    @State private var filter: Filter = .current
    @State private var isPresentingAdd: Bool = false
    @State private var isPresentingArchive: Bool = false
    @State private var draft = NewGoalDraft()
    @State private var selectedGoalID: UUID? = nil

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

                    segmentSwitcher
                        .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
                        .padding(.bottom, DesignTokens.Spacing.stackLarge - 12)

                    // Fluid cross-fade between the two feeds, driven by the
                    // shared `DesignTokens.Motion.smooth` spring.
                    Group {
                        switch segment {
                        case .habits:     habitsSection
                        case .milestones: milestonesSection
                        }
                    }
                    .transition(.opacity)
                }
            }
            .scrollIndicators(.hidden)
            .animation(spring, value: filteredGoals.map(\.id))
            .livingCanvas(p)
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if segment == .milestones { archiveButton }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if segment == .milestones { plusButton }
                }
            }
            .sheet(isPresented: $isPresentingArchive) {
                GoalsArchiveView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(p.sheetBackground)
                    .presentationCornerRadius(DesignTokens.Radius.sheet)
            }
            .sheet(isPresented: $isPresentingAdd) {
                AddGoalSheet(draft: $draft) { new in
                    let goal = PersistedGoal(
                        title: new.title,
                        subtitle: new.subtitle,
                        icon: new.icon,
                        tint: new.tint,
                        unit: new.unit,
                        currentValue: max(new.currentValue, 0),
                        targetValue: max(new.targetValue, 1)
                    )
                    modelContext.insert(goal)
                    // Force an immediate write so the @Query-backed feed
                    // refreshes the instant the sheet dismisses (don't wait
                    // for the autosave coalescing window).
                    try? modelContext.save()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(p.id == .liquidGlass ? AnyShapeStyle(.clear) : AnyShapeStyle(p.sheetBackground))
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
        }
        // Search is milestone-specific; the Habits feed has no query field,
        // so we only mount the search bar on the Milestones segment.
        .modifier(MilestonesSearchable(active: segment == .milestones, text: $searchText))
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
            Text("Progress")
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

    /// Count line tracks the active segment.
    private var headerMeta: String {
        switch segment {
        case .habits:
            let n = habits.filter { !$0.isArchived }.count
            return "\(n) loop\(n == 1 ? "" : "s")"
        case .milestones:
            let n = filteredGoals.count
            return "\(n) item\(n == 1 ? "" : "s")"
        }
    }

    // MARK: Segment switcher — sliding-pill text toggle

    private var segmentSwitcher: some View {
        let p = theme.palette
        return HStack(spacing: 4) {
            ForEach(Segment.allCases) { seg in
                let selected = segment == seg
                Button {
                    guard segment != seg else { return }
                    AppHaptic.tap()
                    withAnimation(DesignTokens.Motion.smooth) { segment = seg }
                } label: {
                    Text(seg.title)
                        .font(p.font(.headline))
                        .tracking(p.headlineTracking)
                        .foregroundStyle(selected ? p.textPrimary : p.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if selected {
                                Capsule(style: .continuous)
                                    .fill(p.chromeSurface)
                                    .overlay(Capsule(style: .continuous).strokeBorder(p.hairline, lineWidth: 0.5))
                                    .matchedGeometryEffect(id: "progressSegmentPill", in: segmentNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .strokeBorder(p.hairline, lineWidth: 0.5)
        )
    }

    // MARK: Sections

    /// Habits — the embeddable routine-streak feed (Pillar 3 components).
    private var habitsSection: some View {
        HabitsFeed()
            .padding(.bottom, DesignTokens.Spacing.pageBottom)
    }

    /// Milestones — the original Goals content (filter row + swipe rows).
    @ViewBuilder
    private var milestonesSection: some View {
        filterRow
            .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
            .padding(.bottom, 12)

        if filteredGoals.isEmpty {
            emptyState
                .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
                .padding(.top, 24)
                .padding(.bottom, DesignTokens.Spacing.pageBottom)
        } else {
            rowSeparator
            ForEach(filteredGoals) { goal in
                GoalIncrementSwipeRow(
                    onIncrement: { GoalMutator.increment(goal, with: exitSpring) },
                    trailing: StarkSwipeAction(
                        systemImage: "archivebox",
                        label: "Abandon",
                        perform: { abandon(goal) }
                    ),
                    isAtCeiling: goal.currentValue >= goal.targetValue
                ) {
                    GoalRowCell(goal: goal) {
                        selectedGoalID = goal.id
                    }
                    .contextMenu {
                        Button {
                            abandon(goal)
                        } label: {
                            Label("Abandon", systemImage: "archivebox")
                        }
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
                rowSeparator
            }
            Spacer(minLength: DesignTokens.Spacing.pageBottom)
        }
    }

    private var filterRow: some View {
        let p = theme.palette
        return HStack(spacing: 12) {
            Text("Your list")
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .textCase(.uppercase)
                .foregroundStyle(p.textSecondary)

            Spacer()

            Menu {
                Button("All") { filter = .all }
                Divider()
                Button("Current") { filter = .current }
                Button("Completed") { filter = .completed }
            } label: {
                HStack(spacing: 6) {
                    Text(filter.title)
                        .font(p.font(.micro))
                        .tracking(p.microTracking)
                        .textCase(.uppercase)
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(p.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(p.chromeSurface))
                .overlay(Capsule().strokeBorder(p.hairline, lineWidth: 0.5))
            }
            .menuOrder(.fixed)
            .buttonStyle(.plain)
        }
    }

    private var rowSeparator: some View {
        Rectangle()
            .fill(theme.palette.hairline)
            .frame(height: 0.5)
    }

    // MARK: Archive — tracked uppercase pill, opens abandoned-goals sheet

    private var archiveButton: some View {
        let p = theme.palette
        return Button {
            isPresentingArchive = true
            AppHaptic.tap()
        } label: {
            Text("Archive")
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .textCase(.uppercase)
                .foregroundStyle(p.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(p.chromeSurface))
                .overlay(Capsule().strokeBorder(p.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Archive")
    }

    // MARK: Plus

    private var plusButton: some View {
        let p = theme.palette
        return Button {
            draft = NewGoalDraft()
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

    // MARK: Empty state

    private var emptyState: some View {
        StarkEmptyState(emptyTitle, footnote: emptySubtitle)
    }

    private var emptyTitle: String {
        switch filter {
        case .all:       return "No goals."
        case .current:   return "Nothing in flight."
        case .completed: return "Nothing finished yet."
        }
    }

    private var emptySubtitle: String {
        switch filter {
        case .all:       return "Tap + to set your first goal."
        case .current:   return "All caught up — or yet to begin."
        case .completed: return "Finish a goal and it'll show up here."
        }
    }

    // MARK: Filtering / mutation

    /// Active workspace excludes abandoned goals — they live in the
    /// archive sheet. Completed goals stay visible under the `.completed`
    /// filter so the user can celebrate / re-target them.
    private var filteredGoals: [PersistedGoal] {
        let live = goals.filter { !$0.isAbandoned }
        let base: [PersistedGoal]
        switch filter {
        case .all:       base = live
        case .current:   base = live.filter { !$0.isCompleted }
        case .completed: base = live.filter { $0.isCompleted }
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }
        return base.filter { g in
            g.title.localizedCaseInsensitiveContains(q) ||
            g.subtitle.localizedCaseInsensitiveContains(q) ||
            (g.lastUpdateNote?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    private func abandon(_ goal: PersistedGoal) {
        GoalMutator.abandon(goal, with: exitSpring)
    }
}

// Internal identifier wrapper so `sheet(item:)` can drive on UUID.
private struct IdentifiedID: Identifiable, Equatable {
    let id: UUID
}

// Mounts the goal search bar only while the Milestones segment is active, so
// the Habits feed never shows a search field it can't drive.
private struct MilestonesSearchable: ViewModifier {
    let active: Bool
    @Binding var text: String

    func body(content: Content) -> some View {
        if active {
            content.searchable(
                text: $text,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "Search goals"
            )
        } else {
            content
        }
    }
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
