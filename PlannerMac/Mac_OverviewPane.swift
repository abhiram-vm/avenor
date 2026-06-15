import SwiftUI
import SwiftData

// MARK: - Mac_OverviewPane
//
// Functional stub: today's open tasks, pulled live from SwiftData via @Query.
// No iOS-only modifiers. Not pixel-matched to the iOS Overview tab yet.

struct Mac_OverviewPane: View {
    @Environment(ThemeStore.self) private var theme
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
            LazyVStack(alignment: .leading, spacing: 14) {
                Text("Due Today")
                    .font(p.font(.micro))
                    .textCase(.uppercase)
                    .foregroundStyle(p.textSecondary)
                    .padding(.top, 4)

                if dueToday.isEmpty {
                    Text("No tasks due today.")
                        .font(p.font(.body))
                        .foregroundStyle(p.textTertiary)
                        .padding(.vertical, 24)
                } else {
                    ForEach(dueToday) { task in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(p.textTertiary)
                                .frame(width: 5, height: 5)
                            Text(task.title)
                                .font(p.font(.body))
                                .foregroundStyle(p.textPrimary)
                            Spacer(minLength: 0)
                            if let due = task.dueDate {
                                Text(due, format: .dateTime.hour().minute())
                                    .font(p.font(.micro))
                                    .foregroundStyle(p.textTertiary)
                            }
                        }
                        .padding(.vertical, 6)
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
