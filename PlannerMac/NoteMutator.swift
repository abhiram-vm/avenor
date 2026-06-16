import Foundation
import SwiftData
import SwiftUI

// MARK: - NoteMutator
//
// Single entry point for every write to `PersistedNote` on macOS. Mirrors the
// `TaskMutator` / `GoalMutator` discipline: a stateless `@MainActor` enum of
// static methods. The Mac knowledge-layer views (notes list, editor, context
// menu) route ALL mutations through here so SwiftData is never touched from a
// view, and so `updatedAt` — the timestamp CloudKit uses for last-writer-wins
// conflict resolution — is bumped on every single write.
//
// iOS deliberately does NOT use this service: `NotesTabView` predates it and
// mutates inline, and that file is out of scope for this work. The note schema
// is shared, but this mutator is a Mac-target file only.
//
// CloudKit-safety lives in the model (`PersistedNote`): no `@Attribute(.unique)`,
// no `@Relationship`, every field defaulted. This layer's only sync obligation
// is the `updatedAt = .now` stamp on each mutation, which every method honors.
//
// Callers own persistence + animation: each method performs the in-memory
// mutation, and the caller decides when to `try? context.save()` (matching the
// existing Mac panes, which save explicitly after a mutator call).

@MainActor
enum NoteMutator {

    /// Insert a fresh note. `createdAt` and `updatedAt` are stamped to now;
    /// pin / archive default off. Returns the inserted note so the caller can
    /// immediately select it (⌘N → focus title).
    @discardableResult
    static func create(title: String = "", body: String = "", in context: ModelContext) -> PersistedNote {
        let now = Date.now
        let note = PersistedNote(
            title: title,
            details: body,
            isPinned: false,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            lastEditedAt: now
        )
        context.insert(note)
        return note
    }

    /// Write the markdown body. Stamps `updatedAt` (conflict clock) and
    /// `lastEditedAt` (user-facing "edited" time). No-op-safe: writing an
    /// identical body still refreshes the timestamps, which is correct — the
    /// auto-save debounce only fires after a real keystroke.
    static func updateBody(_ note: PersistedNote, newBody: String, in context: ModelContext) {
        let now = Date.now
        note.details = newBody
        note.updatedAt = now
        note.lastEditedAt = now
    }

    /// Write the title. Same timestamp discipline as `updateBody`.
    static func updateTitle(_ note: PersistedNote, newTitle: String, in context: ModelContext) {
        let now = Date.now
        note.title = newTitle
        note.updatedAt = now
        note.lastEditedAt = now
    }

    static func pin(_ note: PersistedNote, in context: ModelContext) {
        note.isPinned = true
        note.updatedAt = .now
    }

    static func unpin(_ note: PersistedNote, in context: ModelContext) {
        note.isPinned = false
        note.updatedAt = .now
    }

    /// Non-destructive archive — hides the note from the active list while
    /// preserving its content for CloudKit and any future un-archive path.
    static func archive(_ note: PersistedNote, in context: ModelContext) {
        note.isArchived = true
        note.updatedAt = .now
    }

    /// Duplicate a note's content into a fresh row (new identity / timestamps).
    /// Pin state is intentionally NOT copied; the duplicate starts unpinned.
    @discardableResult
    static func duplicate(_ note: PersistedNote, in context: ModelContext) -> PersistedNote {
        create(title: note.title, body: note.details, in: context)
    }

    /// Hard delete. There is no notification / widget side effect for notes,
    /// so this is a straight context removal (unlike `TaskMutator.delete`).
    static func delete(_ note: PersistedNote, in context: ModelContext) {
        context.delete(note)
    }
}
