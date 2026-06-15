import SwiftUI
import SwiftData

// MARK: - ArchiveTaskListView (Sophisticated Stark)
//
// Read-only historical stream of every completed task. Rows are visually
// demoted (white.opacity ≈ 0.40) but keep monospaced "COMPLETED [DATE]"
// timestamps so the user can read their history at a glance.
//
// Leading swipe = UNARCHIVE: rolls back `isDone`, clears `completedAt`,
// and animates the row back into the active workspace via SwiftData.
// Trailing swipe permanently deletes from SwiftData (rigid haptic).
// Tap-to-restore is also exposed via the context menu as a fallback.

struct ArchiveTaskListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeStore.self) private var theme

    @Query(sort: \PersistedTask.completedAt, order: .reverse) private var allTasks: [PersistedTask]

    private let spring = Animation.spring(response: 0.35, dampingFraction: 0.7)

    var body: some View {
        let p = theme.palette
        NavigationStack {
            ZStack {
                p.canvasView

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        header
                            .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
                            .padding(.top, DesignTokens.Spacing.pageTop)
                            .padding(.bottom, DesignTokens.Spacing.stackLarge)

                        if archived.isEmpty {
                            StarkEmptyState(
                                "Archive empty.",
                                footnote: "Completed tasks land here."
                            )
                            .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
                        } else {
                            separator
                            ForEach(archived) { task in
                                StarkSwipeRow(
                                    leading: StarkSwipeAction(
                                        systemImage: "arrow.uturn.backward",
                                        label: "Unarchive",
                                        perform: { restore(task) }
                                    ),
                                    trailing: StarkSwipeAction(
                                        systemImage: "trash",
                                        label: "Purge",
                                        perform: { purge(task) }
                                    )
                                ) {
                                    ArchivedTaskRow(task: task, onRestore: { restore(task) })
                                }
                                .transition(.asymmetric(
                                    insertion: .opacity,
                                    removal: .opacity.combined(with: .move(edge: .leading))
                                ))
                                separator
                            }
                            Spacer(minLength: DesignTokens.Spacing.pageBottom)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .animation(spring, value: archived.map(\.id))
            }
            .navigationTitle("Archive")
            .avenorInlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .avenorTrailing) {
                    Button("Close") { dismiss() }
                        .font(p.font(.micro))
                        .tracking(p.microTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(p.textPrimary)
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        let p = theme.palette
        return VStack(alignment: .leading, spacing: 10) {
            Text("Archive")
                .font(p.font(.display))
                .tracking(p.displayTracking)
                .foregroundStyle(p.textPrimary)

            HStack(spacing: 0) {
                Text("Completed")
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(p.textSecondary)

                Text("·")
                    .font(p.font(.micro))
                    .foregroundStyle(p.textTertiary)
                    .padding(.horizontal, 8)

                Text("\(archived.count) record\(archived.count == 1 ? "" : "s")")
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .textCase(.uppercase)
                    .monospacedDigit()
                    .foregroundStyle(p.textSecondary)

                Spacer(minLength: 0)
            }
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(theme.palette.hairline)
            .frame(height: 0.5)
    }

    // MARK: Data

    private var archived: [PersistedTask] {
        allTasks.filter { t in
            switch t.type {
            case .todo, .reminder: return (t.isDone ?? false) == true
            case .idea:            return (t.ideaStatus ?? .thinking) == .completed
            }
        }
    }

    // MARK: Mutations

    private func purge(_ task: PersistedTask) {
        TaskMutator.delete(task, in: modelContext, with: spring)
    }

    private func restore(_ task: PersistedTask) {
        TaskMutator.uncomplete(task, in: modelContext, with: spring)
    }
}

// MARK: - ArchivedTaskRow
//
// Demoted variant of the active TaskRow. Same anatomy (rail + meta + title)
// but everything sits at ≈0.40 opacity so the page reads as past tense.

struct ArchivedTaskRow: View {
    @Environment(ThemeStore.self) private var theme
    let task: PersistedTask
    let onRestore: () -> Void

    private static let completionFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("MMMd jmm")
        return f
    }()

    var body: some View {
        let p = theme.palette
        HStack(spacing: 0) {
            Rectangle()
                .fill(task.type.tint.opacity(0.40))
                .frame(width: 2)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                metaStrip
                Text(task.title.isEmpty ? "Untitled" : task.title)
                    .font(p.font(.headline))
                    .tracking(p.headlineTracking)
                    .foregroundStyle(p.textTertiary)
                    .strikethrough(true, color: p.textTertiary)
                    .lineLimit(1)
            }
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(p.rowFill)
        .contextMenu {
            Button {
                onRestore()
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
        }
    }

    private var metaStrip: some View {
        HStack(spacing: 0) {
            metaToken(task.type.displayName)

            separator
            metaToken(completionText, monospaced: true)

            if task.type == .idea, let tag = task.ideaTag, !tag.isEmpty {
                separator
                metaToken("#\(tag)")
            }

            Spacer(minLength: 0)
        }
    }

    private func metaToken(_ text: String, monospaced: Bool = false) -> some View {
        let p = theme.palette
        return Text(text)
            .font(p.font(.micro))
            .tracking(p.microTracking)
            .textCase(.uppercase)
            .conditionalMonospaced(monospaced)
            .foregroundStyle(p.textTertiary)
            .lineLimit(1)
    }

    private var separator: some View {
        let p = theme.palette
        return Text("·")
            .font(p.font(.micro))
            .foregroundStyle(p.textTertiary)
            .padding(.horizontal, 8)
    }

    private var completionText: String {
        if let completedAt = task.completedAt {
            return "Completed \(Self.completionFormatter.string(from: completedAt))"
        }
        return "Completed"
    }
}

#Preview {
    ArchiveTaskListView()
        .environment(ThemeStore())
        .modelContainer(
            for: [PersistedTask.self, PersistedNote.self, PersistedGoal.self],
            inMemory: true
        )
        .preferredColorScheme(.dark)
}
