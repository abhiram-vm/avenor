import SwiftUI
import SwiftData

// MARK: - HabitsFeed (Pillar 3 — Habits & Routine Tracker)
//
// A spacious, editorial vertical feed of the active habit loops captured by
// the Smart Capture engine (anything that parsed into a `.habit` intent and
// was persisted as `PersistedHabit`). Deliberately NOT a calendar grid — the
// section reads like a quiet stack of cards, one ongoing routine each.
//
// This is an *embeddable section*, not a standalone tab: it renders the rows
// (or a `StarkEmptyState`) as a block to be dropped into a parent
// `LazyVStack`. It lives inside the unified "Progress" tab (`GoalsTabView`),
// swapped in by the Habits / Milestones segment switcher. The parent owns the
// `ScrollView`, header, and `.livingCanvas` background — so the Liquid Glass
// `LivingMeshBackground` animates beneath these cards automatically.

struct HabitsFeed: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.modelContext) private var modelContext

    // Active loops only — archived habits are filtered out but retain their
    // rows (and streak history) in the store.
    @Query(sort: \PersistedHabit.sortOrder) private var habits: [PersistedHabit]

    @State private var rekindleHabit: PersistedHabit?

    private let spring = Animation.spring(response: 0.35, dampingFraction: 0.7)
    private let exitSpring = Animation.spring(duration: 0.25)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if activeHabits.isEmpty {
                emptyState
                    .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
            } else {
                ForEach(activeHabits) { habit in
                    HabitSwipeRow(onArchive: { archive(habit) }) {
                        HabitCardRow(
                            habit: habit,
                            isEligible: isEligible(habit),
                            onComplete: { complete(habit) },
                            onRekindle: { rekindleHabit = habit }
                        )
                        .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
                        .padding(.vertical, 6)
                        .contextMenu {
                            Button {
                                archive(habit)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(spring, value: activeHabits.map(\.id))
        .sheet(item: $rekindleHabit) { habit in
            RekindleStreakSheet(habit: habit)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.palette.sheetBackground)
                .presentationCornerRadius(DesignTokens.Radius.sheet)
        }
    }

    private var emptyState: some View {
        StarkEmptyState(
            "No active loops.",
            footnote: "Capture one — try \"Read every day at 9pm\"."
        )
    }

    // MARK: Filtering

    private var activeHabits: [PersistedHabit] {
        habits.filter { !$0.isArchived }
    }

    // MARK: Eligibility

    /// A tap is meaningful when it would either reverse today's log or land a
    /// fresh, in-window completion. Anything else (off-day, already-logged
    /// week) is inert — the card dims and the press no-ops.
    private func isEligible(_ habit: PersistedHabit) -> Bool {
        habit.isCompletedToday() || habit.isEligibleForCompletion(on: .now)
    }

    // MARK: Mutations

    private func complete(_ habit: PersistedHabit) {
        guard isEligible(habit) else { return }
        withAnimation(exitSpring) {
            habit.toggleToday()
        }
    }

    private func archive(_ habit: PersistedHabit) {
        withAnimation(exitSpring) {
            habit.isArchived = true
            habit.updatedAt = .now
        }
    }
}

// MARK: - HabitCardRow
//
// One editorial habit card. Left column carries the parsed title + cadence
// subtitle + the current-week dot chain; the right column is the interactive
// "Streak Loop" with the consecutive-day counter. Wrapped in `ThemedCard`
// so the surface, border, and specular highlight all resolve per theme.

struct HabitCardRow: View {
    @Environment(ThemeStore.self) private var theme

    @Bindable var habit: PersistedHabit
    /// `false` when a tap would be inert (off-day or already logged for the
    /// window) — the streak loop dims and stops firing.
    let isEligible: Bool
    let onComplete: () -> Void
    let onRekindle: () -> Void

    private var isBroken: Bool {
        habit.isStreakBroken && habit.restorationAvailable
    }

    var body: some View {
        let p = theme.palette
        ThemedCard(palette: p) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    // Cadence + optional tag — uppercase micro meta strip.
                    HStack(spacing: 8) {
                        Text(habit.cadenceSubtitle)
                            .font(p.font(.micro))
                            .tracking(p.microTracking)
                            .textCase(.uppercase)
                            .monospacedDigit()
                            .foregroundStyle(p.textTertiary)
                        if let tag = habit.tag, !tag.isEmpty {
                            Text("#\(tag)")
                                .font(p.font(.micro))
                                .tracking(p.microTracking)
                                .textCase(.uppercase)
                                .foregroundStyle(p.accent.opacity(0.8))
                        }

                        if isBroken {
                            crackedFlame(p)
                        }
                    }

                    // Parsed, stripped title — the editorial focal point.
                    Text(habit.title)
                        .font(p.font(.title))
                        .tracking(p.headlineTracking)
                        .foregroundStyle(p.textPrimary)
                        .lineLimit(2)

                    // Current-week completion chain.
                    WeekDotChain(habit: habit, palette: p)
                }

                Spacer(minLength: 0)

                StreakLoop(
                    streak: habit.streakCount,
                    isCompletedToday: habit.isCompletedToday(),
                    isInteractive: isEligible,
                    palette: p,
                    onTrigger: onComplete
                )
            }
            .padding(DesignTokens.Spacing.cardInset)
        }
    }

    // Broken-streak affordance: a dimmed, muted `flame.fill` that opens the
    // "Rekindle Streak" sheet. The historical streak integer is preserved —
    // burning a priority task re-locks it and the flame returns to full white.
    private func crackedFlame(_ p: ThemePalette) -> some View {
        Button(action: onRekindle) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(p.textTertiary.opacity(0.4))
                Text("Rekindle")
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(p.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - StreakLoop
//
// The interactive completion glyph. A lightweight ring frames the live
// streak number. Pressing it integrates the Pillar-1 compression physics:
// the loop anchors and compresses under the thumb (`KineticSpring.compression`),
// fires `AppHaptic.pop()` on release, and the streak counter resolves with a
// crisp numeric flip (`contentTransition(.numericText())`). A horizontal
// travel of >10pt cancels the press so the parent `HabitSwipeRow` owns the
// swipe gesture — mirroring `TaskCompletionModifier`.

struct StreakLoop: View {
    let streak: Int
    let isCompletedToday: Bool
    /// When `false` the loop is inert — dimmed and non-firing — because a tap
    /// wouldn't change anything (off-day or already logged for the window).
    var isInteractive: Bool = true
    let palette: ThemePalette
    let onTrigger: () -> Void

    @State private var pressed = false
    @State private var cancelled = false

    private let diameter: CGFloat = 60

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // Base ring — hollow when pending, accent-filled when done.
                Circle()
                    .stroke(isCompletedToday ? palette.accent : palette.hairline,
                            lineWidth: isCompletedToday ? 3 : 2)
                    .frame(width: diameter, height: diameter)

                Circle()
                    .fill(palette.accent.opacity(isCompletedToday ? 0.14 : 0))
                    .frame(width: diameter, height: diameter)

                // Live streak count with a numeric flip on change.
                VStack(spacing: 0) {
                    Text("\(streak)")
                        .font(.system(size: 22, weight: .bold, design: palette.fontDesign))
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                        .contentTransition(.numericText())
                    Image(systemName: isCompletedToday
                          ? "checkmark"
                          : "arrow.triangle.2.circlepath")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isCompletedToday ? palette.accent : palette.textTertiary)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .scaleEffect(pressed ? 0.9 : 1.0)
            .animation(KineticSpring.compression, value: pressed)
            .animation(KineticSpring.dissolve, value: streak)
            .animation(KineticSpring.dissolve, value: isCompletedToday)

            Text("Day Streak")
                .font(palette.font(.micro))
                .tracking(palette.microTracking)
                .textCase(.uppercase)
                .foregroundStyle(palette.textTertiary)
        }
        .frame(width: 72)
        .opacity(isInteractive ? 1.0 : 0.4)
        .animation(KineticSpring.dissolve, value: isInteractive)
        .contentShape(Rectangle())
        .gesture(pressGesture)
        .accessibilityElement()
        .accessibilityLabel("Streak \(streak) days")
        .accessibilityValue(isCompletedToday ? "Completed today" : "Not completed today")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { fire() }
    }

    // Touch-down compresses; horizontal travel cancels (yields to swipe row);
    // release commits the pop + toggle.
    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let moved = abs(value.translation.width) > 10
                          || abs(value.translation.height) > 10
                if moved {
                    if pressed { pressed = false }
                    cancelled = true
                    return
                }
                if !pressed, !cancelled {
                    AppHaptic.prepare()
                    pressed = true
                }
            }
            .onEnded { _ in
                defer { cancelled = false }
                guard pressed, !cancelled else {
                    pressed = false
                    return
                }
                pressed = false
                fire()
            }
    }

    private func fire() {
        // Inert when ineligible: suppress haptic + skip the toggle so an
        // off-day or double-log press reads as a no-op.
        guard isInteractive else { return }
        AppHaptic.pop()
        onTrigger()
    }
}

// MARK: - WeekDotChain
//
// A subtle horizontal chain of seven soft dots — one per day of the current
// calendar week (Sun…Sat). A day reads "filled" when it falls inside the
// active streak window ending at `lastCompletedAt`; today carries a thin
// ring; future days dim out. Purely derived from `streakCount` +
// `lastCompletedAt`, so no extra per-day persistence is needed.

struct WeekDotChain: View {
    let habit: PersistedHabit
    let palette: ThemePalette

    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 7) {
            ForEach(dots, id: \.date) { dot in
                Circle()
                    .fill(dot.isCompleted ? palette.accent : palette.textTertiary.opacity(0.22))
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .strokeBorder(palette.accent.opacity(dot.isToday ? 0.9 : 0),
                                          lineWidth: 1.5)
                            .frame(width: 12, height: 12)
                    )
                    .opacity(dot.isFuture ? 0.5 : 1)
            }
        }
        .frame(height: 12)
    }

    private struct DayDot {
        let date: Date
        let isCompleted: Bool
        let isToday: Bool
        let isFuture: Bool
    }

    private var dots: [DayDot] {
        let today = calendar.startOfDay(for: .now)
        guard let week = calendar.dateInterval(of: .weekOfYear, for: today) else { return [] }

        // Days covered by the current streak (walking back from last log).
        var completed: Set<Date> = []
        if habit.streakCount > 0, let last = habit.lastCompletedAt {
            let lastDay = calendar.startOfDay(for: last)
            for offset in 0..<habit.streakCount {
                if let d = calendar.date(byAdding: .day, value: -offset, to: lastDay) {
                    completed.insert(d)
                }
            }
        }

        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: week.start) else { return nil }
            let start = calendar.startOfDay(for: day)
            return DayDot(
                date: start,
                isCompleted: completed.contains(start),
                isToday: calendar.isDate(start, inSameDayAs: today),
                isFuture: start > today
            )
        }
    }
}

// MARK: - HabitSwipeRow
//
// Trailing-only swipe-to-archive primitive, tuned for translucent cards.
// Unlike `StarkSwipeRow` (which paints an opaque `rowFill` behind its
// content), this keeps the content background clear and *masks* the archive
// backdrop to exactly the gutter the card vacates as it slides. At rest the
// mask width is 0, so nothing is drawn behind the card — letting the
// Liquid Glass `LivingMeshBackground` bleed through the frosted surface.
// For opaque themes the card masks the gutter region itself, so the result
// is visually identical to the rest of the app.

struct HabitSwipeRow<Content: View>: View {
    @Environment(ThemeStore.self) private var theme

    let onArchive: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var axisLocked = false
    @State private var axisRejected = false
    @State private var hasCrossedTrigger = false

    private let triggerThreshold: CGFloat = 120
    private let spring = Animation.spring(response: 0.35, dampingFraction: 0.7)

    var body: some View {
        let p = theme.palette
        ZStack {
            backdrop(p)
                .mask(alignment: .trailing) {
                    Rectangle().frame(width: max(0, -offset))
                }

            content()
                .offset(x: offset)
                .gesture(dragGesture)
        }
        .clipped()
    }

    private func backdrop(_ p: ThemePalette) -> some View {
        let triggered = -offset >= triggerThreshold
        return HStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                Image(systemName: "archivebox")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(p.textPrimary)
                Text("Archive")
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(triggered ? p.textPrimary : p.textSecondary)
            }
            .frame(minWidth: 56)
            .scaleEffect(triggered ? 1.08 : 1.0)
            .animation(spring, value: triggered)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.chromeSurface)
        .allowsHitTesting(false)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if !axisLocked && !axisRejected {
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    if dx > dy * 1.4 && dx > 8 {
                        axisLocked = true
                    } else if dy > 8 {
                        axisRejected = true
                        return
                    } else {
                        return
                    }
                }
                guard axisLocked else { return }

                let raw = value.translation.width
                // Trailing-only: rubber-band any rightward (leading) pull.
                offset = raw < 0 ? raw : rubberBand(raw)

                let crossed = -offset >= triggerThreshold
                if crossed && !hasCrossedTrigger {
                    hasCrossedTrigger = true
                    AppHaptic.tap()
                } else if !crossed {
                    hasCrossedTrigger = false
                }
            }
            .onEnded { _ in
                defer {
                    axisLocked = false
                    axisRejected = false
                    hasCrossedTrigger = false
                }
                if offset <= -triggerThreshold {
                    onArchive()
                    withAnimation(spring) { offset = 0 }
                } else {
                    withAnimation(spring) { offset = 0 }
                }
            }
    }

    private func rubberBand(_ x: CGFloat) -> CGFloat {
        let limit: CGFloat = 64
        return limit * (1 - 1 / (x / limit + 1))
    }
}

// MARK: - RekindleStreakSheet (Feature 3 — "Burn a Task")
//
// When a routine's scheduling window lapses, its streak integer is preserved
// (not zeroed) and the card surfaces a "Rekindle" affordance. This sheet lets
// the user spend a high-priority task to restore the streak: tapping a P1 task
// atomically completes + archives it, re-locks the streak via
// `habit.rekindleStreak()`, and dismisses. One burn per lapse.

struct RekindleStreakSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeStore.self) private var theme

    @Bindable var habit: PersistedHabit

    // Highest-priority tasks are the only valid "fuel". Filtered to still-open
    // items in-memory (completion is type-dependent, so it can't live in the
    // SwiftData predicate cleanly).
    @Query(filter: #Predicate<PersistedTask> { $0.priority == 1 },
           sort: \PersistedTask.sortOrder) private var priorityTasks: [PersistedTask]

    var body: some View {
        let p = theme.palette
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.stackLarge) {
                    header(p)

                    if burnable.isEmpty {
                        StarkEmptyState(
                            "No P1 tasks to burn.",
                            footnote: "Capture a high-priority task with \"!!!\" to fuel a rekindle."
                        )
                        .padding(.top, 24)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(burnable) { task in
                                Button { burn(task) } label: {
                                    burnRow(task, p)
                                }
                                .buttonStyle(.plain)
                                Rectangle().fill(p.hairline).frame(height: 0.5)
                            }
                        }
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
                .padding(.top, DesignTokens.Spacing.pageTop)
                .padding(.bottom, DesignTokens.Spacing.pageBottom)
            }
            .scrollIndicators(.hidden)
            .livingCanvas(p)
            .navigationTitle("Rekindle Streak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(p.textSecondary)
                }
            }
            .toolbarColorScheme(p.colorScheme, for: .navigationBar)
        }
        .preferredColorScheme(p.colorScheme)
        .tint(p.controlTint)
    }

    private func header(_ p: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(p.accent)
                Text("\(habit.streakCount)-day streak at risk")
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .textCase(.uppercase)
                    .monospacedDigit()
                    .foregroundStyle(p.textSecondary)
            }
            Text("Burn a priority task to lock it back in.")
                .font(p.font(.body))
                .foregroundStyle(p.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func burnRow(_ task: PersistedTask, _ p: ThemePalette) -> some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(task.type.tint)
                .frame(width: 2, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.type.displayName)
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(p.textTertiary)
                Text(task.title.isEmpty ? "Untitled" : task.title)
                    .font(p.font(.headline))
                    .tracking(p.headlineTracking)
                    .foregroundStyle(p.textPrimary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "flame")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(p.accent)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    // MARK: Data

    private var burnable: [PersistedTask] {
        priorityTasks.filter { t in
            switch t.type {
            case .todo, .reminder: return (t.isDone ?? false) == false
            case .idea:            return (t.ideaStatus ?? .thinking) != .completed
            }
        }
    }

    // MARK: Burn

    private func burn(_ task: PersistedTask) {
        let now = Date.now
        // Complete + archive the task atomically (type-dependent completion).
        switch task.type {
        case .todo, .reminder:
            task.isDone = true
        case .idea:
            task.ideaStatus = .completed
        }
        task.completedAt = now
        task.updatedAt = now
        NotificationManager.shared.cancel(for: task)

        // Re-lock the streak — preserves the historical integer.
        habit.rekindleStreak(asOf: now)

        try? modelContext.save()
        AppHaptic.success()
        dismiss()
    }
}

#Preview {
    ScrollView {
        HabitsFeed()
            .padding(.top, 24)
    }
    .environment(ThemeStore())
    .modelContainer(
        for: [PersistedTask.self, PersistedNote.self, PersistedGoal.self, PersistedHabit.self],
        inMemory: true
    )
    .preferredColorScheme(.dark)
}
