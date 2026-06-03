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

    // Active loops only — archived habits are filtered out but retain their
    // rows (and streak history) in the store.
    @Query(sort: \PersistedHabit.sortOrder) private var habits: [PersistedHabit]

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
                        HabitCardRow(habit: habit) {
                            complete(habit)
                        }
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

    // MARK: Mutations

    private func complete(_ habit: PersistedHabit) {
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
    let onComplete: () -> Void

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
                    palette: p,
                    onTrigger: onComplete
                )
            }
            .padding(DesignTokens.Spacing.cardInset)
        }
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
