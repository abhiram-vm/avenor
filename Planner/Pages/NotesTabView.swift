import SwiftUI
import SwiftData

// MARK: - NotesTabView (Sophisticated Stark)
//
// Same `ScrollView + LazyVStack + StarkSwipeRow` pattern as Tasks.
// Leading swipe: Duplicate. Trailing swipe: Delete. All monochrome.

struct NotesTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeStore.self) private var theme

    @Query(sort: \PersistedNote.sortOrder) private var notes: [PersistedNote]

    @State private var expandedNoteID: UUID? = nil
    @State private var searchText: String = ""

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

                        if visibleNotes.isEmpty {
                            emptyState
                                .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
                                .padding(.top, 24)
                                .padding(.bottom, DesignTokens.Spacing.pageBottom)
                        } else {
                            RowSeparator()
                            ForEach(visibleNotes) { note in
                                StarkSwipeRow(
                                    leading: StarkSwipeAction(
                                        systemImage: "doc.on.doc",
                                        label: "Duplicate",
                                        perform: { duplicate(note) }
                                    ),
                                    trailing: StarkSwipeAction(
                                        systemImage: "trash",
                                        label: "Delete",
                                        perform: { delete(note) }
                                    )
                                ) {
                                    NoteRow(
                                        note: note,
                                        isExpanded: expandedNoteID == note.id,
                                        onToggleExpanded: { toggleExpanded(note) },
                                        onDelete: { delete(note) }
                                    )
                                }
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity
                                ))
                                RowSeparator()
                            }
                            Spacer(minLength: DesignTokens.Spacing.pageBottom)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .animation(spring, value: visibleNotes.map(\.id))
                .animation(spring, value: expandedNoteID)
            }
            .navigationTitle("Notes")
            .avenorInlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .avenorTrailing) { plusButton }
            }
        }
        #if os(iOS)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search notes"
        )
        #else
        .searchable(text: $searchText, prompt: "Search notes")
        #endif
    }

    // MARK: Header

    private var header: some View {
        let p = theme.palette
        return VStack(alignment: .leading, spacing: 10) {
            Text("Notes")
                .font(p.font(.display))
                .tracking(p.displayTracking)
                .foregroundStyle(p.textPrimary)

            Text("\(visibleNotes.count) note\(visibleNotes.count == 1 ? "" : "s")")
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .textCase(.uppercase)
                .monospacedDigit()
                .foregroundStyle(p.textSecondary)
        }
    }

    // MARK: Plus

    private var plusButton: some View {
        let p = theme.palette
        return Button {
            addNote()
            AppHaptic.tap()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(p.textPrimary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(p.chromeSurface))
                .overlay(Circle().strokeBorder(p.prominent, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: Empty state

    private var emptyState: some View {
        StarkEmptyState(
            notes.isEmpty ? "Empty." : "No matches.",
            footnote: notes.isEmpty ? "Tap + to write your first note." : "Try a different search."
        )
    }

    // MARK: Helpers

    private var visibleNotes: [PersistedNote] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return notes }
        return notes.filter { n in
            n.title.localizedCaseInsensitiveContains(q) ||
            n.details.localizedCaseInsensitiveContains(q)
        }
    }

    private func toggleExpanded(_ note: PersistedNote) {
        withAnimation(spring) {
            expandedNoteID = (expandedNoteID == note.id) ? nil : note.id
        }
        AppHaptic.tap()
    }

    private func addNote() {
        let note = PersistedNote(title: "", details: "")
        withAnimation(spring) {
            modelContext.insert(note)
            expandedNoteID = note.id
        }
    }

    private func duplicate(_ note: PersistedNote) {
        let copy = PersistedNote(title: note.title, details: note.details)
        withAnimation(spring) {
            modelContext.insert(copy)
        }
    }

    private func delete(_ note: PersistedNote) {
        if expandedNoteID == note.id { expandedNoteID = nil }
        withAnimation(spring) {
            modelContext.delete(note)
        }
    }
}

#Preview {
    NotesTabView()
        .environment(ThemeStore())
        .modelContainer(
            for: [PersistedTask.self, PersistedNote.self, PersistedGoal.self],
            inMemory: true
        )
        .preferredColorScheme(.dark)
}
