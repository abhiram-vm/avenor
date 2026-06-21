import SwiftUI
import SwiftData

// MARK: - Mac_RoutinesPane
//
// Displays all non-archived PersistedHabit objects synced from iOS via
// CloudKit. No creation UI — habits are created on iOS. Each row shows a
// 2pt gold rail, the routine title, streak count in mint, last-completed
// date in Space Mono micro text, and a checkbox for logging today.
//
// Mutation: `habit.toggleToday()` is the canonical path (self-contained in
// the model, as used by the iOS GoalsTabView and HabitsDashboardView). We
// call it directly and save, matching the iOS pattern.

private let gold = Color(red: 251 / 255, green: 191 / 255, blue: 36 / 255)

struct Mac_RoutinesPane: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \PersistedHabit.sortOrder) private var habits: [PersistedHabit]

    private var activeHabits: [PersistedHabit] {
        habits.filter { !$0.isArchived }
    }

    var body: some View {
        let p = theme.palette
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Mac_DisplayTitle(
                    title: "Routines",
                    metaLabel: subtitleMeta,
                    accentCallout: activeHabits.isEmpty ? nil : "\(activeHabits.count) ACTIVE",
                    size: 72
                )
                .padding(.bottom, 40)

                if activeHabits.isEmpty {
                    Mac_CinematicEmpty(
                        headline: "no\nroutines",
                        footnote: "Create routines on iOS — they sync here automatically."
                    )
                    .padding(.top, 8)
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(activeHabits) { habit in
                            Mac_RoutineRow(habit: habit) {
                                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) {
                                    habit.toggleToday()
                                    try? modelContext.save()
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 56)
            .padding(.top, 60)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .themedCanvas(p)
    }

    private var subtitleMeta: String {
        Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased()
    }
}

// MARK: - Mac_RoutineRow

struct Mac_RoutineRow: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let habit: PersistedHabit
    var onToggle: () -> Void

    @State private var hovering = false

    private var isCompletedToday: Bool { habit.isCompletedToday() }

    var body: some View {
        let p = theme.palette
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
        HStack(spacing: 0) {
            // 2pt gold accent rail
            Rectangle()
                .fill(gold)
                .frame(width: 2)
                .frame(maxHeight: .infinity)

            content(p)
        }
        .frame(minHeight: 56)
        .background(shape.fill(hovering ? p.chromeSurface : p.rowFill))
        .overlay(shape.strokeBorder(p.hairline, lineWidth: 1))
        .clipShape(shape)
        .opacity(isCompletedToday ? 0.6 : 1)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: isCompletedToday)
        .contextMenu {
            Button {
                onToggle()
            } label: {
                Label(isCompletedToday ? "Mark Incomplete" : "Complete Today",
                      systemImage: "checkmark")
            }
        }
    }

    private func content(_ p: ThemePalette) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Checkbox
            Button(action: onToggle) {
                Image(systemName: isCompletedToday ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(isCompletedToday ? Mac_Accent.mint : p.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: isCompletedToday)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)

            // Title + meta
            VStack(alignment: .leading, spacing: 5) {
                metaStrip(p)
                Text(habit.title.isEmpty ? "Untitled" : habit.title)
                    .font(.system(size: 15, weight: .medium, design: p.fontDesign))
                    .tracking(p.headlineTracking)
                    .foregroundStyle(isCompletedToday ? p.textTertiary : p.textPrimary)
                    .strikethrough(isCompletedToday, color: p.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Streak badge
            streakBadge(p)
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.vertical, 12)
    }

    private func metaStrip(_ p: ThemePalette) -> some View {
        HStack(spacing: 0) {
            Text(habit.cadenceDisplayLabel.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(p.textTertiary)
            if let last = habit.lastCompletedAt {
                Text("·")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(p.textTertiary)
                    .padding(.horizontal, 6)
                Text(lastCompletedText(last))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(p.textTertiary)
            }
        }
    }

    private func streakBadge(_ p: ThemePalette) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(habit.streakCount)")
                .font(.system(size: 20, weight: .heavy, design: p.fontDesign))
                .foregroundStyle(Mac_Accent.mint)
                .monospacedDigit()
            Text("STREAK")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(p.textTertiary)
        }
        .frame(minWidth: 40, alignment: .trailing)
    }

    private func lastCompletedText(_ date: Date) -> String {
        let cal = Calendar.autoupdatingCurrent
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
