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

    /// External focus trigger (⌘N). Set to true to focus the bar; the bar
    /// resets it to false immediately after acquiring focus. Mirrors the iOS
    /// `StarkCaptureBar.shouldFocus` contract.
    var shouldFocus: Binding<Bool> = .constant(false)

    @State private var text = ""
    /// Brief mint border flash on a successful capture, then fades out.
    @State private var flash = false
    @FocusState private var focused: Bool

    var body: some View {
        let p = theme.palette
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
        HStack(spacing: 10) {
            // CLI prompt glyph — the brand mint `>`, constant across themes.
            Text(">")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Mac_Accent.mint)

            TextField("", text: $text, prompt: prompt(p))
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundStyle(p.textPrimary)
                .tint(Mac_Accent.mint)
                .focused($focused)
                .autocorrectionDisabled()
                .onSubmit(commit)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(shape.fill(p.rowFill))
        .overlay(shape.strokeBorder(borderColor(p), lineWidth: 1))
        .animation(.easeInOut(duration: 0.15), value: focused)
        .animation(.easeInOut(duration: 0.18), value: flash)
        .onAppear { focused = true }
        .onChange(of: shouldFocus.wrappedValue) { _, newValue in
            if newValue {
                focused = true
                shouldFocus.wrappedValue = false
            }
        }
    }

    // MARK: Prompt + border

    /// Space-Mono-feel placeholder: monospaced, wide tracking, whisper opacity —
    /// matching the iOS `StarkCaptureBar` prompt.
    private func prompt(_ p: ThemePalette) -> Text {
        Text("Capture a task, idea, goal, or note…")
            .font(.system(size: 14, weight: .regular, design: .monospaced))
            .tracking(0.6)
            .foregroundColor(p.textTertiary)
    }

    private func borderColor(_ p: ThemePalette) -> Color {
        if flash { return Mac_Accent.mint }
        return focused ? Mac_Accent.mint.opacity(0.55) : p.hairline
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

        case .calendar(let title, let startDate, let duration):
            // Calendar events live in EventKit, not SwiftData. Silent create
            // on the default calendar (no app-switch) — the same shared store
            // the Calendar pane reads, so the new event surfaces on its next
            // fetch. Confirmation is the mint flash below, matching every other
            // capture type. A failed create (e.g. access not yet granted) is
            // logged by the service and simply skips the flash.
            let created = EventKitService.shared.createEvent(
                title: title,
                startDate: startDate,
                duration: duration,
                context: modelContext
            )
            if !created {
                // No SwiftData write and no flash — leave the text in place so
                // the user can retry once calendar access is granted.
                return
            }
        }

        // Commit immediately so @Query-backed panes update without waiting for
        // the autosave coalescing window.
        try? modelContext.save()
        text = ""

        // Brief mint border flash to confirm the capture, then fade back.
        flash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            flash = false
        }
    }
}
