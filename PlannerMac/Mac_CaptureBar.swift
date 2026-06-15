import SwiftUI
import SwiftData

// MARK: - Mac_CaptureBar
//
// macOS adaptation of `StarkCaptureBar`. Same contract: free text runs through
// `CaptureParser.parse(_:)` on Return and routes to the matching model insert —
// byte-for-byte the same routing as iOS `OverviewTabView.commitCapture`, minus
// the iOS-only Live Activity countdown. Keeps the terminal `>` prompt as a
// visual identity element. No haptics, no keyboard toolbar, no autocapitalize.

struct Mac_CaptureBar: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeStore.self) private var theme

    @State private var text = ""
    @FocusState private var focused: Bool

    /// Accent Mint `#6EE7A8` — the same capture accent used across all themes.
    private let mint = Color(red: 110 / 255, green: 231 / 255, blue: 168 / 255)

    var body: some View {
        let p = theme.palette
        HStack(spacing: 10) {
            Text(">")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(mint)

            TextField("Capture a task, idea, goal, or note…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundStyle(p.textPrimary)
                .tint(mint)
                .focused($focused)
                .autocorrectionDisabled()
                .onSubmit(commit)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(p.rowFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(focused ? mint.opacity(0.55) : Color.white.opacity(0.07))
        )
        .animation(.easeInOut(duration: 0.15), value: focused)
        .onAppear { focused = true }
    }

    // MARK: Capture routing (mirrors OverviewTabView.commitCapture)

    private func commit() {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let intent = CaptureParser.parse(raw) else { return }

        switch intent {
        case .todo(let title, let dueDate, let priority):
            let task = PersistedTask(title: title, type: .todo, dueDate: dueDate, priority: priority)
            modelContext.insert(task)
            NotificationManager.shared.schedule(for: task)

        case .idea(let title, let tag, let priority):
            let task = PersistedTask(
                title: title,
                type: .idea,
                ideaStatus: .thinking,
                ideaTag: tag.isEmpty ? nil : tag,
                priority: priority
            )
            modelContext.insert(task)

        case .reminder(let title, let dueDate, let priority):
            let task = PersistedTask(title: title, type: .reminder, dueDate: dueDate, priority: priority)
            modelContext.insert(task)
            NotificationManager.shared.schedule(for: task)

        case .note(let title, let body):
            let note = PersistedNote(title: title, details: body, lastEditedAt: .now)
            modelContext.insert(note)

        case .habit(let title, let rule, let anchor, let tag, let priority):
            let habit = PersistedHabit(
                title: title,
                recurrence: rule,
                anchorDate: anchor,
                tag: tag,
                priority: priority
            )
            modelContext.insert(habit)
        }

        // Commit immediately so @Query-backed panes update without waiting for
        // the autosave coalescing window.
        try? modelContext.save()
        text = ""
    }
}
