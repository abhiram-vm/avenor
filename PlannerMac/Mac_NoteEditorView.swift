import SwiftUI
import SwiftData

// MARK: - Mac_NoteEditorView
//
// The center column of the Notes pane. Two responsibilities:
//   • When a note is selected → render `Mac_NoteEditorBody`, keyed by note id
//     so its local draft state resets cleanly on every selection change.
//   • When nothing is selected → a centered empty state.
//
// Reading mode (Phase 4) forces the rendered markdown preview and hides the
// raw editor + chrome, regardless of the per-note edit/preview toggle.

struct Mac_NoteEditorView: View {
    @Environment(ThemeStore.self) private var theme

    let note: PersistedNote?
    /// Live mention resolver built from the pane's task/goal queries.
    var resolver: MentionResolver
    /// Phase 4: distraction-free reading mode.
    var readingMode: Bool = false
    /// Phase 3: invoked when a resolved @mention is clicked.
    var onOpenMention: (String) -> Void = { _ in }

    var body: some View {
        let p = theme.palette
        Group {
            if let note {
                Mac_NoteEditorBody(
                    note: note,
                    resolver: resolver,
                    readingMode: readingMode,
                    onOpenMention: onOpenMention
                )
                .id(note.id)
            } else {
                emptyState(p)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedCanvas(p)
    }

    private func emptyState(_ p: ThemePalette) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text")
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(Mac_Accent.mint)
            Text("Select a note or press ⌘N")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .tracking(p.microTracking)
                .foregroundStyle(p.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Mac_NoteEditorBody
//
// The actual editing surface for one note. Holds local `title` / `body` draft
// state seeded from the model, and pushes changes back through `NoteMutator`
// on a 0.5s debounce — no Save button, no dirty indicator. Edit ↔ preview is a
// per-note toggle (⌘E or the toolbar glyph). The status bar shows a live word
// count + 200-wpm reading estimate.

private struct Mac_NoteEditorBody: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    let note: PersistedNote
    var resolver: MentionResolver
    var readingMode: Bool
    var onOpenMention: (String) -> Void

    @State private var title: String
    @State private var bodyText: String
    @State private var isPreview: Bool = false

    // Debounce handles — cancelled and replaced on each keystroke.
    @State private var titleSaveTask: Task<Void, Never>?
    @State private var bodySaveTask: Task<Void, Never>?

    @FocusState private var titleFocused: Bool

    /// Reading mode always shows the rendered preview.
    private var showingPreview: Bool { readingMode || isPreview }

    init(note: PersistedNote, resolver: MentionResolver, readingMode: Bool, onOpenMention: @escaping (String) -> Void) {
        self.note = note
        self.resolver = resolver
        self.readingMode = readingMode
        self.onOpenMention = onOpenMention
        _title = State(initialValue: note.title)
        _bodyText = State(initialValue: note.details)
    }

    var body: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: 0) {
            if !readingMode {
                header(p)
                Divider().overlay(p.hairline)
            }
            content(p)
            if !readingMode {
                Divider().overlay(p.hairline)
                statusBar(p)
            }
        }
        .onAppear {
            // New, empty notes land focused on the title (⌘N → type immediately).
            if title.isEmpty && bodyText.isEmpty { titleFocused = true }
        }
        .onChange(of: title) { _, newValue in scheduleTitleSave(newValue) }
        .onChange(of: bodyText) { _, newValue in scheduleBodySave(newValue) }
        .environment(\.openURL, OpenURLAction { url in
            handleURL(url)
        })
    }

    // MARK: Header — title field + edit/preview toggle

    private func header(_ p: ThemePalette) -> some View {
        HStack(alignment: .center, spacing: 12) {
            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(p.font(.title))
                .fontWeight(.heavy)
                .tracking(p.displayTracking)
                .foregroundStyle(p.textPrimary)
                .tint(Mac_Accent.mint)
                .focused($titleFocused)

            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isPreview.toggle() }
            } label: {
                Image(systemName: isPreview ? "eye.fill" : "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isPreview ? Mac_Accent.mint : p.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                            .fill(p.chromeSurface)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("e", modifiers: .command)
            .help(isPreview ? "Edit (⌘E)" : "Preview (⌘E)")
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    // MARK: Content — raw editor or rendered preview

    @ViewBuilder
    private func content(_ p: ThemePalette) -> some View {
        if showingPreview {
            preview(p)
        } else {
            TextEditor(text: $bodyText)
                .textEditorStyle(.plain)
                .scrollContentBackground(.hidden)
                .font(p.font(.body))
                .foregroundStyle(p.textPrimary)
                .tint(Mac_Accent.mint)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func preview(_ p: ThemePalette) -> some View {
        ScrollView {
            Text(MarkdownParser.render(
                bodyText,
                palette: p,
                baseSize: readingMode ? 17 : 15,
                resolver: resolver
            ))
            .lineSpacing(readingMode ? 7 : 4)
            .textSelection(.enabled)
            .frame(maxWidth: readingMode ? 680 : .infinity, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: readingMode ? .center : .leading)
            .padding(.horizontal, readingMode ? 40 : 28)
            .padding(.vertical, readingMode ? 40 : 20)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Status bar — word count + reading time

    private func statusBar(_ p: ThemePalette) -> some View {
        HStack(spacing: 14) {
            Text("\(wordCount) WORD\(wordCount == 1 ? "" : "S")")
            Text(readingTimeLabel)
            Spacer(minLength: 0)
        }
        .font(.system(size: 9, weight: .regular, design: .monospaced))
        .tracking(p.microTracking)
        .foregroundStyle(p.textTertiary)
        .padding(.horizontal, 28)
        .padding(.vertical, 9)
    }

    private var wordCount: Int {
        bodyText.split { $0.isWhitespace || $0.isNewline }.count
    }

    private var readingTimeLabel: String {
        guard wordCount > 0 else { return "0 MIN READ" }
        let minutes = max(1, Int((Double(wordCount) / 200.0).rounded(.up)))
        return "\(minutes) MIN READ"
    }

    // MARK: Auto-save (0.5s debounce)

    private func scheduleTitleSave(_ newValue: String) {
        titleSaveTask?.cancel()
        titleSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            NoteMutator.updateTitle(note, newTitle: newValue, in: modelContext)
            try? modelContext.save()
        }
    }

    private func scheduleBodySave(_ newValue: String) {
        bodySaveTask?.cancel()
        bodySaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            NoteMutator.updateBody(note, newBody: newValue, in: modelContext)
            try? modelContext.save()
        }
    }

    // MARK: Link handling — intercept internal @mention links

    private func handleURL(_ url: URL) -> OpenURLAction.Result {
        if url.scheme == MarkdownParser.mentionScheme {
            let name = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !name.isEmpty { onOpenMention(name) }
            return .handled
        }
        return .systemAction
    }
}
