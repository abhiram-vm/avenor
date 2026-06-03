//
//  AvenorTasksWidget.swift
//  AvenorWidget
//
//  The interactive Task & Routine widget (Phase 6). Distinct from the
//  date/time `AvenorWidget` — this one surfaces actionable items with
//  one-tap checkboxes / loop toggles powered by `AppIntent`.
//
//  Families:
//    • systemSmall  — top 2 urgent items (task or routine), tappable glyphs.
//    • systemMedium — split: routine loops + streaks (left), top 3 tasks (right).
//
//  Theme: inherits the shared `WidgetPalette` (Stark Dark / Stark Light /
//  Calm Earth / Liquid Glass) read from the App Group every timeline tick.
//
//  Interaction: each glyph is a `Button(intent:)`. The intent journals the
//  mutation to the App Group queue and reloads this widget's timeline; the
//  entry below renders an OPTIMISTIC overlay (pending completions show as
//  checked) so the tap looks instant before the main app drains the queue.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Entry

struct AvenorTasksEntry: TimelineEntry {
    let date: Date
    let today: TodayWidgetPayload
    let routine: RoutineWidgetPayload
    let palette: WidgetPalette
    /// IDs with a queued-but-not-yet-applied completion/toggle. Used to paint
    /// the optimistic checked state.
    let pendingTaskIDs: Set<UUID>
    let pendingHabitIDs: Set<UUID>
}

// MARK: - Provider

struct AvenorTasksProvider: TimelineProvider {

    func placeholder(in context: Context) -> AvenorTasksEntry {
        AvenorTasksEntry(
            date: .now,
            today: .placeholder,
            routine: .placeholder,
            palette: .starkDark,
            pendingTaskIDs: [],
            pendingHabitIDs: []
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (AvenorTasksEntry) -> Void) {
        completion(makeEntry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AvenorTasksEntry>) -> Void) {
        // Event-driven refresh: we explicitly reload from the app (data
        // change) and from the intents (tap). The timeline itself only needs
        // a coarse fallback so the list rolls over at midnight and stale
        // "due today" items drop off. One entry now + a refresh at the next
        // midnight keeps the system from over-waking the extension.
        let now = Date.now
        let entry = makeEntry(at: now)
        let cal = Calendar.autoupdatingCurrent
        let nextMidnight = cal.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }

    private func makeEntry(at date: Date) -> AvenorTasksEntry {
        let pending = WidgetActionQueue.peek()
        let pendingTasks = Set(pending.filter { $0.kind == .completeTask }.map(\.targetID))
        let pendingHabits = Set(pending.filter { $0.kind == .toggleHabit }.map(\.targetID))
        return AvenorTasksEntry(
            date: date,
            today: WidgetSnapshotIO.readToday(),
            routine: WidgetSnapshotIO.readRoutine(),
            palette: .current(),
            pendingTaskIDs: pendingTasks,
            pendingHabitIDs: pendingHabits
        )
    }
}

// MARK: - Widget declaration

struct AvenorTasksWidget: Widget {
    let kind: String = "AvenorTasksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AvenorTasksProvider()) { entry in
            AvenorTasksEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetCanvasView(palette: entry.palette)
                }
        }
        .configurationDisplayName("Tasks & Routines")
        .description("Your urgent tasks and routine loops — tap to complete without opening Avenor.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

// MARK: - Entry view

struct AvenorTasksEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AvenorTasksEntry

    var body: some View {
        let p = entry.palette
        layout
            .foregroundColor(p.textPrimary)
            .tint(p.accent)
            .environment(\.colorScheme, p.colorScheme)
    }

    @ViewBuilder
    private var layout: some View {
        switch family {
        case .systemMedium: TasksMediumView(entry: entry)
        default:            TasksSmallView(entry: entry)
        }
    }
}

// MARK: - Unified urgent item

/// A normalized row model so the Small family can interleave tasks and
/// routine loops in one ranked list.
private struct UrgentItem: Identifiable {
    enum Kind { case task, habit }
    let id: UUID
    let kind: Kind
    let title: String
    let typeRaw: String        // task type for the rail color; "habit" for loops
    let isComplete: Bool
    let metaLabel: String      // due time / streak
}

private func urgentItems(from entry: AvenorTasksEntry, limit: Int) -> [UrgentItem] {
    var items: [UrgentItem] = []

    for t in entry.today.items {
        let complete = entry.pendingTaskIDs.contains(t.id)
        let meta: String
        if let due = t.dueDate {
            meta = due.formatted(date: .omitted, time: .shortened)
        } else {
            meta = t.typeRaw.uppercased()
        }
        items.append(UrgentItem(id: t.id, kind: .task, title: t.title,
                                typeRaw: t.typeRaw, isComplete: complete, metaLabel: meta))
    }
    for h in entry.routine.habits {
        let toggled = entry.pendingHabitIDs.contains(h.id)
        let complete = toggled ? !h.isCompletedToday : h.isCompletedToday
        items.append(UrgentItem(id: h.id, kind: .habit, title: h.title,
                                typeRaw: "habit", isComplete: complete,
                                metaLabel: "\(h.streakCount) DAY STREAK"))
    }
    // Incomplete first, then by original order (tasks already sorted by due).
    return Array(items.sorted { !$0.isComplete && $1.isComplete }.prefix(limit))
}

// MARK: - Small (2x2)

private struct TasksSmallView: View {
    let entry: AvenorTasksEntry

    var body: some View {
        let p = entry.palette
        let items = urgentItems(from: entry, limit: 2)

        WidgetThemedCard(palette: p) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text("UP NEXT")
                        .font(p.font(.micro))
                        .tracking(p.microTracking)
                        .foregroundStyle(p.textSecondary)
                    Spacer(minLength: 0)
                    Text("\(entry.today.totalDueToday)")
                        .font(p.font(.micro))
                        .monospacedDigit()
                        .foregroundStyle(p.textTertiary)
                }
                .padding(.bottom, 10)

                if items.isEmpty {
                    Spacer(minLength: 0)
                    Text("All clear.")
                        .font(p.font(.body))
                        .foregroundStyle(p.textTertiary)
                    Spacer(minLength: 0)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(items) { item in
                            InteractiveItemRow(palette: p, item: item, compact: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
        }
    }
}

// MARK: - Medium (4x2)

private struct TasksMediumView: View {
    let entry: AvenorTasksEntry

    var body: some View {
        let p = entry.palette
        WidgetThemedCard(palette: p) {
            HStack(alignment: .top, spacing: 0) {
                routineColumn(palette: p)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                Rectangle()
                    .fill(p.hairline)
                    .frame(width: 0.5)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 2)

                taskColumn(palette: p)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
        }
    }

    // Left: routine loops + live streaks.
    @ViewBuilder
    private func routineColumn(palette p: WidgetPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ROUTINES")
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .foregroundStyle(p.textSecondary)

            if entry.routine.habits.isEmpty {
                Text("No loops yet.")
                    .font(p.font(.caption))
                    .foregroundStyle(p.textTertiary)
            } else {
                ForEach(entry.routine.habits.prefix(3)) { habit in
                    let toggled = entry.pendingHabitIDs.contains(habit.id)
                    let done = toggled ? !habit.isCompletedToday : habit.isCompletedToday
                    HabitLoopRow(palette: p, habit: habit, doneToday: done)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.trailing, 12)
    }

    // Right: top 3 uncompleted tasks.
    @ViewBuilder
    private func taskColumn(palette p: WidgetPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("TASKS")
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .foregroundStyle(p.textSecondary)
                Spacer(minLength: 0)
                Text("\(entry.today.totalDueToday)")
                    .font(p.font(.micro))
                    .monospacedDigit()
                    .foregroundStyle(p.textTertiary)
            }

            let visible = entry.today.items.prefix(3)
            if visible.isEmpty {
                Text("Nothing due.")
                    .font(p.font(.caption))
                    .foregroundStyle(p.textTertiary)
            } else {
                ForEach(visible) { item in
                    let complete = entry.pendingTaskIDs.contains(item.id)
                    let urgent = UrgentItem(id: item.id, kind: .task, title: item.title,
                                            typeRaw: item.typeRaw, isComplete: complete,
                                            metaLabel: item.dueDate?.formatted(date: .omitted, time: .shortened) ?? "")
                    InteractiveItemRow(palette: p, item: urgent, compact: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 12)
    }
}

// MARK: - Interactive rows

/// A task / generic urgent row with a tappable completion glyph.
private struct InteractiveItemRow: View {
    let palette: WidgetPalette
    let item: UrgentItem
    let compact: Bool

    var body: some View {
        let p = palette
        HStack(alignment: .top, spacing: 8) {
            completionButton(palette: p)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(p.font(.body))
                    .foregroundStyle(item.isComplete ? p.textTertiary : p.textPrimary)
                    .strikethrough(item.isComplete, color: p.textTertiary)
                    .lineLimit(1)
                if !item.metaLabel.isEmpty {
                    Text(item.metaLabel)
                        .font(p.font(.micro))
                        .tracking(p.microTracking)
                        .monospacedDigit()
                        .foregroundStyle(p.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func completionButton(palette p: WidgetPalette) -> some View {
        // The intent differs per kind. Both render a flat square that
        // fills + check-marks when complete (matches the in-app checkbox).
        let glyph = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Group {
            switch item.kind {
            case .task:
                Button(intent: CompleteTaskIntent(taskID: item.id)) {
                    checkboxLabel(shape: glyph, palette: p)
                }
            case .habit:
                Button(intent: ToggleHabitIntent(habitID: item.id)) {
                    checkboxLabel(shape: glyph, palette: p)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func checkboxLabel(shape: RoundedRectangle, palette p: WidgetPalette) -> some View {
        shape
            .stroke(item.isComplete ? Color.clear : p.textSecondary, lineWidth: 1.2)
            .background(item.isComplete ? shape.fill(railColor(p)) : shape.fill(Color.clear))
            .frame(width: 18, height: 18)
            .overlay {
                if item.isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(p.colorScheme == .dark ? Color.black : Color.white)
                }
            }
    }

    private func railColor(_ p: WidgetPalette) -> Color {
        switch item.typeRaw {
        case "todo":     return Color(red: 0.55, green: 0.85, blue: 0.78)
        case "reminder": return Color(red: 0.92, green: 0.74, blue: 0.52)
        case "idea":     return Color(red: 0.78, green: 0.76, blue: 0.92)
        case "habit":    return p.accent
        default:         return p.accent
        }
    }
}

/// A routine loop row: tappable ring glyph + title + streak.
private struct HabitLoopRow: View {
    let palette: WidgetPalette
    let habit: HabitWidgetItem
    let doneToday: Bool

    var body: some View {
        let p = palette
        HStack(alignment: .center, spacing: 8) {
            Button(intent: ToggleHabitIntent(habitID: habit.id)) {
                ZStack {
                    Circle()
                        .stroke(doneToday ? Color.clear : p.textSecondary, lineWidth: 1.4)
                        .background(doneToday ? Circle().fill(p.accent) : Circle().fill(Color.clear))
                        .frame(width: 18, height: 18)
                    if doneToday {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(p.colorScheme == .dark ? Color.black : Color.white)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(habit.title)
                    .font(p.font(.body))
                    .foregroundStyle(doneToday ? p.textTertiary : p.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(p.textTertiary)
                    Text("\(habit.streakCount)")
                        .font(p.font(.micro))
                        .monospacedDigit()
                        .foregroundStyle(p.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Previews

#Preview("Small — Dark", as: .systemSmall) {
    AvenorTasksWidget()
} timeline: {
    AvenorTasksEntry(date: .now, today: .placeholder, routine: .placeholder,
                     palette: .starkDark, pendingTaskIDs: [], pendingHabitIDs: [])
}

#Preview("Medium — Calm Earth", as: .systemMedium) {
    AvenorTasksWidget()
} timeline: {
    AvenorTasksEntry(date: .now, today: .placeholder, routine: .placeholder,
                     palette: .calmEarth, pendingTaskIDs: [], pendingHabitIDs: [])
}

#Preview("Medium — Liquid Glass", as: .systemMedium) {
    AvenorTasksWidget()
} timeline: {
    AvenorTasksEntry(date: .now, today: .placeholder, routine: .placeholder,
                     palette: .liquidGlass, pendingTaskIDs: [], pendingHabitIDs: [])
}
