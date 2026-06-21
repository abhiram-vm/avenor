import SwiftUI
import SwiftData

// MARK: - Mac_NotesPane
//
// The macOS knowledge layer. A three-column workspace — notes list · editor ·
// backlinks — built as a hand-laid `HStack` (not a nested `NavigationSplitView`)
// so it inherits the same mint-accented, no-native-List aesthetic as the rest
// of the Mac app and composes cleanly inside `Mac_ContentView`'s outer split.
//
// Columns:
//   1. List (240pt, always visible) — search + sort + selectable note rows.
//   2. Editor (flexible) — `Mac_NoteEditorView` for the selected note.
//   3. Backlinks (240pt, ⌘⇧B) — `Mac_BacklinksPanel`.
//
// Reading mode (⌘⇧R) collapses columns 1 & 3 and expands the editor to a
// centered, distraction-free preview.
//
// Every note write routes through `NoteMutator`; the pane never mutates
// SwiftData directly. Keyboard commands arrive as `Mac_NavState` tokens set by
// the app menu bar (see PlannerMacApp.macCommands).

struct Mac_NotesPane: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(Mac_NavState.self) private var nav
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Active (non-archived) notes, newest-edit first as the base ordering.
    @Query(
        filter: #Predicate<PersistedNote> { !$0.isArchived },
        sort: [SortDescriptor(\PersistedNote.updatedAt, order: .reverse)]
    ) private var notes: [PersistedNote]

    // Backing data for @mention resolution + backlinks.
    @Query private var allTasks: [PersistedTask]
    @Query private var allGoals: [PersistedGoal]

    @State private var selectedNoteID: UUID?
    @State private var searchQuery: String = ""
    @State private var sortMode: NoteSortMode = .modified
    @State private var pendingDelete: PersistedNote?

    @FocusState private var searchFocused: Bool

    private var resolver: MentionResolver {
        MentionResolver(tasks: allTasks, goals: allGoals)
    }

    private var selectedNote: PersistedNote? {
        guard let id = selectedNoteID else { return nil }
        return notes.first { $0.id == id }
    }

    var body: some View {
        let p = theme.palette
        Group {
            if nav.notesReadingMode {
                readingLayout(p)
            } else {
                standardLayout(p)
            }
        }
        .themedCanvas(p)
        .onChange(of: nav.newNoteToken) { _, v in
            if v { nav.newNoteToken = false; createNote() }
        }
        .onChange(of: nav.notesFocusSearchToken) { _, v in
            if v { nav.notesFocusSearchToken = false; searchFocused = true }
        }
        .onChange(of: notes.map(\.id)) { _, _ in
            // Keep selection valid if the current note is archived / deleted.
            if let id = selectedNoteID, !notes.contains(where: { $0.id == id }) {
                selectedNoteID = nil
            }
        }
        .alert("Delete Note?", isPresented: deleteAlertBinding, presenting: pendingDelete) { note in
            Button("Delete", role: .destructive) { confirmDelete(note) }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("This can’t be undone.")
        }
    }

    // MARK: Layouts

    private func standardLayout(_ p: ThemePalette) -> some View {
        HStack(spacing: 0) {
            notesList(p)
                .frame(width: 240)
            Divider().overlay(p.hairline)

            Mac_NoteEditorView(
                note: selectedNote,
                resolver: resolver,
                readingMode: false,
                onOpenMention: openMention
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if nav.notesShowBacklinks {
                Divider().overlay(p.hairline)
                Mac_BacklinksPanel(note: selectedNote, onSelectNote: { selectedNoteID = $0.id })
                    .frame(width: 240)
                    .transition(reduceMotion
                        ? AnyTransition.opacity
                        : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85),
                   value: nav.notesShowBacklinks)
    }

    private func readingLayout(_ p: ThemePalette) -> some View {
        Mac_NoteEditorView(
            note: selectedNote,
            resolver: resolver,
            readingMode: true,
            onOpenMention: openMention
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            // Always-available exit affordance for reading mode.
            Button { nav.notesReadingMode = false } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(p.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                            .fill(p.chromeSurface)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .help("Exit Reading Mode (⇧⌘R)")
            .padding(16)
        }
    }

    // MARK: Notes list column

    private func notesList(_ p: ThemePalette) -> some View {
        VStack(spacing: 0) {
            listHeader(p)
            listToolbar(p)
            Divider().overlay(p.hairline)

            if displayedNotes.isEmpty {
                emptyList(p)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(displayedNotes) { note in
                            Mac_NoteListRow(
                                note: note,
                                selected: note.id == selectedNoteID,
                                snippet: snippet(for: note),
                                onSelect: { selectedNoteID = note.id },
                                onTogglePin: { togglePin(note) },
                                onDuplicate: { duplicate(note) },
                                onArchive: { archive(note) },
                                onDelete: { pendingDelete = note }
                            )
                        }
                    }
                    .padding(8)
                }
                .scrollIndicators(.hidden)
            }
            Spacer(minLength: 0)
        }
        .background(p.canvasView)
    }

    /// Editorial header for the narrow list column — the "Notes" display title
    /// scaled to fit 240pt, with an asymmetric mono count beside it.
    private func listHeader(_ p: ThemePalette) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text("Notes")
                .font(.system(size: 30, weight: .heavy, design: p.fontDesign))
                .tracking(-1.2)
                .foregroundStyle(p.textPrimary)
            Spacer(minLength: 0)
            if !notes.isEmpty {
                Text("\(notes.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(p.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    private func listToolbar(_ p: ThemePalette) -> some View {
        VStack(spacing: 10) {
            // Search field
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(p.textTertiary)
                TextField("Search", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(p.font(.body))
                    .foregroundStyle(p.textPrimary)
                    .tint(Mac_Accent.mint)
                    .focused($searchFocused)
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(p.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .fill(p.rowFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .strokeBorder(searchFocused ? Mac_Accent.mint.opacity(0.5) : p.hairline, lineWidth: 1)
            )

            // Sort + new-note
            HStack(spacing: 8) {
                Picker("", selection: $sortMode) {
                    ForEach(NoteSortMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .font(p.font(.micro))
                .tint(p.textSecondary)

                Spacer(minLength: 0)

                Button { createNote() } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(p.textPrimary)
                        .frame(width: 28, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                                .fill(p.chromeSurface)
                        )
                }
                .buttonStyle(.plain)
                .help("New Note (⌘N)")
            }
        }
        .padding(12)
    }

    private func emptyList(_ p: ThemePalette) -> some View {
        VStack(spacing: 8) {
            Text(searchQuery.isEmpty ? "No notes yet" : "No matches")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .tracking(p.microTracking)
                .foregroundStyle(p.textTertiary)
            if searchQuery.isEmpty {
                Text("Press ⌘N")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .tracking(p.microTracking)
                    .foregroundStyle(p.textTertiary)
            }
        }
        .padding(.top, 28)
        .frame(maxWidth: .infinity)
    }

    // MARK: Derived list

    /// Search-filtered, then sorted with pinned notes floated to the top.
    private var displayedNotes: [PersistedNote] {
        let filtered = NoteSearch.filter(notes, query: searchQuery)
        let sorted = filtered.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
            return sortMode.areInOrder(a, b)
        }
        return sorted
    }

    /// Row preview text — 80-char context around a body match when searching,
    /// else the first 60 characters of the body (newlines flattened).
    private func snippet(for note: PersistedNote) -> String {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty, let s = NoteSearch.contextSnippet(in: note.details, query: q) {
            return s
        }
        let flat = note.details.replacingOccurrences(of: "\n", with: " ")
        return String(flat.prefix(60))
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    // MARK: Mutations (all via NoteMutator)

    private func createNote() {
        let note = NoteMutator.create(in: modelContext)
        try? modelContext.save()
        selectedNoteID = note.id
        // Editor auto-focuses the title for a fresh, empty note.
        if nav.notesReadingMode { nav.notesReadingMode = false }
    }

    private func togglePin(_ note: PersistedNote) {
        if note.isPinned { NoteMutator.unpin(note, in: modelContext) }
        else { NoteMutator.pin(note, in: modelContext) }
        try? modelContext.save()
    }

    private func duplicate(_ note: PersistedNote) {
        let copy = NoteMutator.duplicate(note, in: modelContext)
        try? modelContext.save()
        selectedNoteID = copy.id
    }

    private func archive(_ note: PersistedNote) {
        if selectedNoteID == note.id { selectedNoteID = nil }
        if reduceMotion {
            NoteMutator.archive(note, in: modelContext)
        } else {
            withAnimation(.easeInOut(duration: 0.18)) {
                NoteMutator.archive(note, in: modelContext)
            }
        }
        try? modelContext.save()
    }

    private func confirmDelete(_ note: PersistedNote) {
        if selectedNoteID == note.id { selectedNoteID = nil }
        if reduceMotion {
            NoteMutator.delete(note, in: modelContext)
        } else {
            withAnimation(.easeInOut(duration: 0.18)) {
                NoteMutator.delete(note, in: modelContext)
            }
        }
        try? modelContext.save()
        pendingDelete = nil
    }

    // MARK: @mention navigation

    private func openMention(_ name: String) {
        guard let target = resolver.resolve(name) else { return }
        switch target {
        case .task(let t): nav.focus(.task(t.id))
        case .goal(let g): nav.focus(.goal(g.id))
        }
    }
}

// MARK: - NoteSortMode

enum NoteSortMode: String, CaseIterable, Identifiable {
    case created, modified, alphabetical
    var id: String { rawValue }

    var label: String {
        switch self {
        case .created:      return "Created"
        case .modified:     return "Modified"
        case .alphabetical: return "A–Z"
        }
    }

    func areInOrder(_ a: PersistedNote, _ b: PersistedNote) -> Bool {
        switch self {
        case .created:      return a.createdAt > b.createdAt
        case .modified:     return a.updatedAt > b.updatedAt
        case .alphabetical: return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }
}

// MARK: - NoteSearch
//
// Pure, view-agnostic search helpers. Exact case-insensitive containment first;
// when that misses, an in-order subsequence check provides forgiving "fuzzy"
// matching (the brief: "query characters appear in order within the string").
// No regex needed for the membership test — `NSString`-style containment via
// `localizedCaseInsensitiveContains` is both correct and cheap.

enum NoteSearch {

    static func filter(_ notes: [PersistedNote], query: String) -> [PersistedNote] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return notes }
        return notes.filter { matches($0, query: q) }
    }

    static func matches(_ note: PersistedNote, query q: String) -> Bool {
        if note.title.localizedCaseInsensitiveContains(q) { return true }
        if note.details.localizedCaseInsensitiveContains(q) { return true }
        // Fuzzy fallback: subsequence against title or body.
        return isSubsequence(q, of: note.title) || isSubsequence(q, of: note.details)
    }

    /// `true` when every character of `needle` appears in `haystack` in order
    /// (case-insensitive). Empty needle matches anything.
    static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        let n = Array(needle.lowercased())
        guard !n.isEmpty else { return true }
        var i = 0
        for c in haystack.lowercased() {
            if c == n[i] {
                i += 1
                if i == n.count { return true }
            }
        }
        return false
    }

    /// Extract ~80 characters of context centered on the first case-insensitive
    /// match of `query` in `text`. Returns `nil` when there's no exact match.
    static func contextSnippet(in text: String, query: String) -> String? {
        let ns = text as NSString
        let range = ns.range(of: query, options: .caseInsensitive)
        guard range.location != NSNotFound else { return nil }
        let pad = 40
        let start = max(0, range.location - pad)
        let end = min(ns.length, range.location + range.length + pad)
        var slice = ns.substring(with: NSRange(location: start, length: end - start))
        slice = slice.replacingOccurrences(of: "\n", with: " ")
        let prefix = start > 0 ? "…" : ""
        let suffix = end < ns.length ? "…" : ""
        return prefix + slice + suffix
    }
}

// MARK: - Mac_NoteListRow
//
// One row in the notes list: pin glyph + title, a dimmed preview snippet, and a
// right-aligned modified date. Selection paints a mint left rail + a surface
// lift, matching the task-row selection language. Right-click exposes the full
// management menu (pin · duplicate · archive · delete).

private struct Mac_NoteListRow: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let note: PersistedNote
    let selected: Bool
    let snippet: String
    var onSelect: () -> Void
    var onTogglePin: () -> Void
    var onDuplicate: () -> Void
    var onArchive: () -> Void
    var onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        let p = theme.palette
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
        Button(action: onSelect) {
            HStack(spacing: 0) {
                // Mint left rail — pinned notes carry it persistently; a
                // selected note also shows it (selection adds the surface lift).
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill((note.isPinned || selected) ? Mac_Accent.mint : Color.clear)
                    .frame(width: 2)
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        if note.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Mac_Accent.mint)
                        }
                        Text(note.title.isEmpty ? "Untitled" : note.title)
                            .font(.system(size: 14, weight: .medium, design: p.fontDesign))
                            .foregroundStyle(p.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }

                    if !snippet.isEmpty {
                        Text(snippet)
                            .font(.system(size: 11, weight: .regular, design: p.fontDesign))
                            .foregroundStyle(p.textTertiary)
                            .lineLimit(1)
                    }

                    Text(dateLabel)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .tracking(p.microTracking)
                        .foregroundStyle(p.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.leading, 8)
                .padding(.trailing, 10)
                .padding(.vertical, 8)
            }
            .background(shape.fill(selected ? p.chromeSurface : (hovering ? p.rowFill : Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: hovering)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: selected)
        .contextMenu {
            Button(note.isPinned ? "Unpin" : "Pin") { onTogglePin() }
            Button("Duplicate") { onDuplicate() }
            Divider()
            Button("Archive") { onArchive() }
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    private var dateLabel: String {
        note.updatedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
