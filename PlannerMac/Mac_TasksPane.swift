import SwiftUI
import SwiftData

// MARK: - Mac_TasksPane
//
// Functional stub: every actionable task, sorted by `sortOrder` (negative
// epoch-millis, ascending → newest first). Completion routes through the
// shared `TaskMutator` service — views never mutate SwiftData directly.
// Standard macOS row interactions for now (no StarkSwipeRow).

struct Mac_TasksPane: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PersistedTask.sortOrder, order: .forward) private var tasks: [PersistedTask]

    var body: some View {
        let p = theme.palette
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if tasks.isEmpty {
                    Text("No tasks yet. Capture one above.")
                        .font(p.font(.body))
                        .foregroundStyle(p.textTertiary)
                        .padding(.vertical, 28)
                } else {
                    ForEach(tasks) { task in
                        row(task, palette: p)
                        Divider().opacity(0.25)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .themedCanvas(p)
        .navigationTitle("Tasks")
    }

    @ViewBuilder
    private func row(_ task: PersistedTask, palette p: ThemePalette) -> some View {
        let isDone = task.isDone ?? false
        HStack(spacing: 12) {
            Button {
                if isDone {
                    TaskMutator.uncomplete(task, in: modelContext)
                } else {
                    TaskMutator.complete(task, in: modelContext)
                }
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isDone ? p.textTertiary : p.textSecondary)
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(p.font(.body))
                .foregroundStyle(isDone ? p.textTertiary : p.textPrimary)
                .strikethrough(isDone, color: p.textTertiary)

            Spacer(minLength: 0)

            Text(task.type.pillTitle)
                .font(p.font(.micro))
                .foregroundStyle(p.textTertiary)
        }
        .padding(.vertical, 9)
    }
}
