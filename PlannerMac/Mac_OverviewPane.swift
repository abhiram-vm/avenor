import SwiftUI
import SwiftData

// MARK: - Mac_OverviewPane
//
// Today's open tasks, pulled live from SwiftData via @Query. Each row is
// completable in place via the leading checkbox, routing through the shared
// `TaskMutator` (a completed task drops off the "Due Today" list on the next
// query pass). No iOS-only modifiers.

struct Mac_OverviewPane: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [PersistedTask]

    private let calendar = Calendar.autoupdatingCurrent

    private var dueToday: [PersistedTask] {
        tasks
            .filter { t in
                guard !(t.isDone ?? false), let due = t.dueDate else { return false }
                return calendar.isDate(due, inSameDayAs: .now)
            }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var body: some View {
        let p = theme.palette
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                // Display hero — large tight-tracked title, matching the iOS
                // tab heroes (TodayHeader).
                Text("Overview")
                    .font(p.font(.display))
                    .tracking(p.displayTracking)
                    .foregroundStyle(p.textPrimary)
                    .padding(.bottom, 8)

                Text("Due Today")
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(p.textTertiary)
                    .padding(.bottom, 2)

                if dueToday.isEmpty {
                    StarkEmptyState("No tasks due today.")
                } else {
                    ForEach(dueToday) { task in
                        Mac_TaskRow(
                            task: task,
                            onToggleComplete: { TaskMutator.complete(task, in: modelContext) },
                            onDelete: {
                                TaskMutator.delete(task, in: modelContext)
                                try? modelContext.save()
                            }
                        )
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .themedCanvas(p)
        .navigationTitle("Overview")
    }
}
