import Foundation
import SwiftData
import SwiftUI
import os

// MARK: - JSON → SwiftData migration
//
// One-shot migration from the legacy `planner-data.json` blob (Application
// Support directory) into the SwiftData container.
//
// Invariants:
//   • Idempotent — guarded by a UserDefaults flag and a "container is already
//     populated?" check, so re-running on a healthy device does nothing.
//   • Non-destructive — the legacy JSON is renamed to `planner-data.json.bak`
//     after a successful migration rather than deleted, so a rollback build
//     (or this build, post-bug) can still recover user data. We can prune
//     `.bak` files in a future version once we're confident.
//   • Fail-soft — on any error, we leave the JSON untouched and log via
//     `Logger` (production-safe, redaction-aware). The user keeps their data
//     on disk and we will try again next launch.

enum MigrationService {
    private static let migrationFlagKey = "avenor.migration.jsonToSwiftData.completed.v1"

    private static let logger = Logger(subsystem: "com.remyavipindas.avenor", category: "migration")

    static func runIfNeeded(context: ModelContext) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: migrationFlagKey) { return }

        // If SwiftData already has rows, treat the migration as complete.
        // Avoids double-importing if the user (or a reinstall) ends up here
        // with both data sources present.
        if hasExistingSwiftDataRows(context: context) {
            defaults.set(true, forKey: migrationFlagKey)
            return
        }

        guard let payload = LegacyJSONStore.load() else {
            // No legacy file — fresh install. Mark complete so we don't keep
            // hitting the disk on every launch.
            defaults.set(true, forKey: migrationFlagKey)
            return
        }

        do {
            try migrate(payload: payload, into: context)
            try context.save()
            LegacyJSONStore.archive()
            defaults.set(true, forKey: migrationFlagKey)
        } catch {
            // Swallow: leave the JSON, leave the flag unset, retry next launch.
            // SwiftData inserts in this scope are not persisted because we
            // don't call save() before the throw.
            logger.error("Migration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func hasExistingSwiftDataRows(context: ModelContext) -> Bool {
        var taskDescriptor = FetchDescriptor<PersistedTask>()
        taskDescriptor.fetchLimit = 1
        if let count = try? context.fetchCount(taskDescriptor), count > 0 { return true }

        var noteDescriptor = FetchDescriptor<PersistedNote>()
        noteDescriptor.fetchLimit = 1
        if let count = try? context.fetchCount(noteDescriptor), count > 0 { return true }

        var goalDescriptor = FetchDescriptor<PersistedGoal>()
        goalDescriptor.fetchLimit = 1
        if let count = try? context.fetchCount(goalDescriptor), count > 0 { return true }

        return false
    }

    private static func migrate(payload: PersistedAppData, into context: ModelContext) throws {
        // Preserve user's manual order (top-of-list = first in JSON array) by
        // assigning descending sortOrder values.
        let now = Date.now

        for (index, dto) in payload.tasks.enumerated() {
            let task = PersistedTask(
                id: dto.id,
                title: dto.title,
                details: dto.details,
                type: dto.type,
                isDone: dto.isDone,
                dueDate: dto.dueDate,
                startDate: dto.startDate,
                endDate: dto.endDate,
                ideaStatus: dto.ideaStatus,
                ideaTag: dto.ideaTag,
                sortOrder: -index,
                createdAt: now,
                updatedAt: now
            )
            context.insert(task)
        }

        for (index, dto) in payload.notes.enumerated() {
            let note = PersistedNote(
                id: dto.id,
                title: dto.title,
                details: dto.details,
                sortOrder: -index,
                createdAt: now,
                updatedAt: now
            )
            context.insert(note)
        }

        for (index, dto) in payload.goals.enumerated() {
            let goal = PersistedGoal(
                id: dto.id,
                title: dto.title,
                subtitle: dto.subtitle,
                icon: dto.icon,
                tint: Color.fromHexRGBA(dto.tintHex),
                unit: dto.unitKind.toModel(),
                currentValue: dto.currentValue,
                targetValue: dto.targetValue,
                lastUpdateNote: dto.lastUpdateNote,
                lastUpdatedAt: dto.lastUpdatedAt,
                sortOrder: -index,
                createdAt: now
            )
            context.insert(goal)
        }
    }
}

// MARK: - Legacy JSON access
//
// Mirrors the existing `LocalStore` URL/format, isolated here so the rest of
// the app no longer needs to know about the JSON shape. After Phase 1 lands,
// `LocalStore`'s persistence functions can be deleted; this file is the only
// reader the app needs going forward.

enum LegacyJSONStore {
    private static let fileName = "planner-data.json"
    private static let backupFileName = "planner-data.json.bak"

    private static var baseDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static var url: URL { baseDirectory.appendingPathComponent(fileName) }
    static var backupURL: URL { baseDirectory.appendingPathComponent(backupFileName) }

    static func load() -> PersistedAppData? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PersistedAppData.self, from: data)
    }

    /// Renames the legacy JSON to a `.bak` sibling. If a previous backup
    /// exists, it is overwritten — only the most recent migration is kept.
    static func archive() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        try? fm.removeItem(at: backupURL)
        try? fm.moveItem(at: url, to: backupURL)
    }
}
