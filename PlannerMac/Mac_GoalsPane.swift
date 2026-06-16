import SwiftUI
import SwiftData

// MARK: - Mac_GoalsPane
//
// Active goals with a hairline progress bar (no system ProgressView, in
// keeping with the Stark design ethos). Create via the toolbar "+"; manage
// each goal with a right-click context menu (log progress / edit / abandon /
// delete). Every lifecycle mutation routes through the shared `GoalMutator`.

struct Mac_GoalsPane: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(Mac_NavState.self) private var nav
    @Query(sort: \PersistedGoal.sortOrder) private var goals: [PersistedGoal]

    @State private var showingAdd = false
    @State private var editingGoal: PersistedGoal?
    /// Goal id currently flashing a mint ring after a cross-pane navigation.
    @State private var flashID: UUID?

    private var activeGoals: [PersistedGoal] {
        goals.filter { $0.status == .active }
    }

    var body: some View {
        let p = theme.palette
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if activeGoals.isEmpty {
                        StarkEmptyState("No active goals.", footnote: "Add one with +.")
                    } else {
                        ForEach(activeGoals) { goal in
                            Mac_GoalCard(
                                goal: goal,
                                onLogProgress: {
                                    GoalMutator.increment(goal)
                                    try? modelContext.save()
                                },
                                onEdit: { editingGoal = goal },
                                onAbandon: {
                                    GoalMutator.abandon(goal)
                                    try? modelContext.save()
                                },
                                onDelete: {
                                    GoalMutator.delete(goal, in: modelContext)
                                    try? modelContext.save()
                                },
                                highlighted: flashID == goal.id
                            )
                            .id(goal.id)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: nav.pendingFocus) { _, target in
                guard case .goal(let id)? = target else { return }
                reveal(id, proxy: proxy)
            }
            .onAppear {
                if case .goal(let id)? = nav.pendingFocus { reveal(id, proxy: proxy) }
            }
        }
        .themedCanvas(p)
        .navigationTitle("Goals")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(p.textPrimary)
                }
                .help("New Goal")
            }
        }
        .sheet(isPresented: $showingAdd) {
            Mac_AddGoalSheet()
        }
        .sheet(item: $editingGoal) { goal in
            Mac_AddGoalSheet(existing: goal)
        }
    }

    /// Scroll the requested goal into view, flash its ring, then clear the
    /// nav token so the same target can be requested again later.
    private func reveal(_ id: UUID, proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
        flashID = id
        nav.pendingFocus = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if flashID == id { withAnimation(.easeInOut(duration: 0.2)) { flashID = nil } }
        }
    }
}

// MARK: - Mac_GoalCard
//
// Goal row matching the iOS GoalsViews anatomy: title + percent, a hairline-
// track progress bar with the goal's damped tint fill, and the "current /
// target" meta below the bar. Wrapped in a `ThemedCard` so Liquid Glass gets
// its material + specular edge for free. Hover lift + right-click context menu
// mirror the task rows.

struct Mac_GoalCard: View {
    @Environment(ThemeStore.self) private var theme
    let goal: PersistedGoal
    var onLogProgress: () -> Void
    var onEdit: () -> Void
    var onAbandon: () -> Void
    var onDelete: () -> Void
    /// Mint ring flash when navigated to via an @mention / backlink.
    var highlighted: Bool = false

    @State private var hovering = false

    var body: some View {
        let p = theme.palette
        ThemedCard(palette: p) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(goal.title)
                        .font(p.font(.headline))
                        .tracking(p.headlineTracking)
                        .foregroundStyle(p.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(goal.percentText)
                        .font(p.font(.micro))
                        .tracking(p.microTracking)
                        .monospacedDigit()
                        .foregroundStyle(p.textPrimary)
                }

                // Hairline progress bar — transform/opacity only, no system control.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(p.hairline)
                        Rectangle()
                            .fill(goal.displayTint)
                            .frame(width: max(0, min(1, goal.progress)) * geo.size.width)
                    }
                }
                .frame(height: 2)

                Text("\(goal.currentText) / \(goal.targetText)")
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .textCase(.uppercase)
                    .monospacedDigit()
                    .foregroundStyle(p.textTertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? p.chromeSurface : Color.clear)
        }
        .overlay(
            RoundedRectangle(cornerRadius: p.cardRadius, style: .continuous)
                .strokeBorder(highlighted ? Mac_Accent.mint : Color.clear, lineWidth: 1.5)
        )
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovering)
        .animation(.easeInOut(duration: 0.2), value: highlighted)
        .contextMenu {
            Button("Log Progress") { onLogProgress() }
            Button("Edit…") { onEdit() }
            Divider()
            Button("Abandon") { onAbandon() }
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
}
