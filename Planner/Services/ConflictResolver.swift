import Foundation
import SwiftData
import os

// MARK: - ConflictResolver
//
// Last-writer-wins resolution keyed on the model's own timestamp:
//   • PersistedTask   → `updatedAt`
//   • PersistedNote   → `lastEditedAt`
//   • PersistedGoal   → `lastUpdatedAt`
//
// CloudKit-backed SwiftData stores will surface duplicate records when two
// devices mutate the same logical entity offline. Our `id` is no longer
// `@Attribute(.unique)` (CloudKit forbids that), so this resolver runs as
// a background reconciliation pass: dedupes by `id`, keeping the row with
// the most recent timestamp and deleting the rest.
//
// Run it on app launch (after the model container is wired) and/or when
// the app becomes active. It is idempotent and safe to call repeatedly.

@MainActor
enum ConflictResolver {

    private static let logger = Logger(subsystem: "com.remyavipindas.avenor", category: "sync.conflict")

    // MARK: Entry point

    /// Reconciles all three model types in a single pass.
    static func reconcile(in context: ModelContext) {
        do {
            try reconcileTasks(in: context)
            try reconcileNotes(in: context)
            try reconcileGoals(in: context)
            try context.save()
        } catch {
            logger.error("Reconcile failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Tasks

    private static func reconcileTasks(in context: ModelContext) throws {
        let all = try context.fetch(FetchDescriptor<PersistedTask>())
        let groups = Dictionary(grouping: all, by: { $0.id })
        var pruned = 0
        for (_, group) in groups where group.count > 1 {
            let winner = group.max(by: { $0.updatedAt < $1.updatedAt })!
            for loser in group where loser !== winner {
                context.delete(loser)
                pruned += 1
            }
        }
        if pruned > 0 { logger.info("Pruned \(pruned, privacy: .public) duplicate task(s).") }
    }

    // MARK: Notes

    private static func reconcileNotes(in context: ModelContext) throws {
        let all = try context.fetch(FetchDescriptor<PersistedNote>())
        let groups = Dictionary(grouping: all, by: { $0.id })
        var pruned = 0
        for (_, group) in groups where group.count > 1 {
            // Notes prefer `lastEditedAt`; fall back to `updatedAt`.
            let winner = group.max(by: { lhs, rhs in
                (lhs.lastEditedAt ?? lhs.updatedAt) < (rhs.lastEditedAt ?? rhs.updatedAt)
            })!
            for loser in group where loser !== winner {
                context.delete(loser)
                pruned += 1
            }
        }
        if pruned > 0 { logger.info("Pruned \(pruned, privacy: .public) duplicate note(s).") }
    }

    // MARK: Goals

    private static func reconcileGoals(in context: ModelContext) throws {
        let all = try context.fetch(FetchDescriptor<PersistedGoal>())
        let groups = Dictionary(grouping: all, by: { $0.id })
        var pruned = 0
        for (_, group) in groups where group.count > 1 {
            // Goals prefer `lastUpdatedAt`; fall back to `createdAt`.
            let winner = group.max(by: { lhs, rhs in
                (lhs.lastUpdatedAt ?? lhs.createdAt) < (rhs.lastUpdatedAt ?? rhs.createdAt)
            })!
            for loser in group where loser !== winner {
                context.delete(loser)
                pruned += 1
            }
        }
        if pruned > 0 { logger.info("Pruned \(pruned, privacy: .public) duplicate goal(s).") }
    }
}

// MARK: - SyncTelemetry
//
// Lightweight observability sidecar — counts saves, conflicts pruned, and
// last reconcile time. Hook this into a debug overlay or surface from the
// future iCloud settings panel if you ever want users to see sync health.

@MainActor
@Observable
final class SyncTelemetry {
    static let shared = SyncTelemetry()

    private(set) var lastReconcileAt: Date?
    private(set) var totalSaves: Int = 0

    private init() {}

    func recordSave() { totalSaves += 1 }
    func recordReconcile() { lastReconcileAt = .now }
}
