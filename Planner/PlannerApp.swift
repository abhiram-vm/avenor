import SwiftUI
import SwiftData
import os

@main
struct PlannerApp: App {
    @State private var theme = ThemeStore()

    init() {
        #if DEBUG
        // Internal-beta safety net: force the SwiftData model graph to
        // validate on launch so a broken schema / migration surfaces in
        // DEBUG + TestFlight smoke runs rather than on a user's device.
        SchemaValidator.validateOnLaunch()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(theme)
                .task {
                    // Fire-and-forget: iOS caches the user's decision after
                    // the first prompt, so subsequent launches are cheap.
                    await NotificationManager.shared.requestAuthorization()
                }
                .modelContext { context in
                    // Reconcile any CloudKit-induced duplicates on entry,
                    // then run the lifecycle maintenance sweep (dead
                    // reminders → archive). Finally drain any taps the user
                    // made from the interactive widget while the app was
                    // closed.
                    ConflictResolver.reconcile(in: context)
                    LifecycleAutomation.runDailyMaintenance(in: context)
                    WidgetActionApplier.drainAndApply(in: context)
                }
                .onScenePhaseChange { phase, context in
                    switch phase {
                    case .active:
                        // Re-sweep on every foreground transition. The user
                        // may have left the app open for days; this keeps the
                        // workspace fresh the instant they return.
                        LifecycleAutomation.runDailyMaintenance(in: context)
                        // Apply widget taps journaled while backgrounded, and
                        // retire any countdown whose event has already begun.
                        WidgetActionApplier.drainAndApply(in: context)
                        EventLiveActivityManager.endExpired()
                    case .inactive, .background:
                        // Prune stale countdowns when leaving the foreground
                        // too, so an expired Live Activity never lingers on the
                        // Lock Screen / Dynamic Island after the event passed.
                        EventLiveActivityManager.endExpired()
                    @unknown default:
                        break
                    }
                }
        }
        .modelContainer(for: [
            PersistedTask.self,
            PersistedNote.self,
            PersistedGoal.self,
            PersistedHabit.self
        ])
    }
}

private extension View {
    /// Pulls the `ModelContext` out of the environment so we can hand it to
    /// non-view services on first render.
    func modelContext(_ run: @escaping (ModelContext) -> Void) -> some View {
        modifier(ModelContextHook(run: run))
    }
}

private struct ModelContextHook: ViewModifier {
    @Environment(\.modelContext) private var context
    let run: (ModelContext) -> Void
    func body(content: Content) -> some View {
        content.task { run(context) }
    }
}

// MARK: - Scene-phase + context bridge
//
// Routes scene-phase transitions into the same closure shape as
// `modelContext(_:)`. Avoids re-implementing the model-context environment
// extraction in every call site.

private extension View {
    func onScenePhaseChange(_ run: @escaping (ScenePhase, ModelContext) -> Void) -> some View {
        modifier(ScenePhaseContextHook(run: run))
    }
}

private struct ScenePhaseContextHook: ViewModifier {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    let run: (ScenePhase, ModelContext) -> Void
    func body(content: Content) -> some View {
        content.onChange(of: scenePhase) { _, newPhase in
            run(newPhase, context)
        }
    }
}

// MARK: - SchemaValidator (DEBUG / internal beta only)
//
// Forces a full SwiftData model-graph validation at launch by materializing
// the schema into a throwaway in-memory container. Any migration / schema
// error throws here — loudly, in DEBUG — instead of corrupting a real store
// in the field. Compiled out of Release builds entirely.
//
// ⚠️ This deliberately does NOT call a CloudKit schema-initialization API:
// the project ships with no iCloud / CloudKit entitlement (bundle
// `com.remyavipindas.avenor`), so a CloudKit-backed init would throw
// `loadIssueModelContainer` and crash at launch — the opposite of a safety
// net. SwiftData enables CloudKit mirroring only once the entitlement +
// container exist; until then, in-memory schema validation is the correct,
// crash-free readiness check.

#if DEBUG
private enum SchemaValidator {
    private static let logger = Logger(subsystem: "com.remyavipindas.avenor", category: "schema")

    static func validateOnLaunch() {
        let schema = Schema([
            PersistedTask.self,
            PersistedNote.self,
            PersistedGoal.self,
            PersistedHabit.self
        ])
        do {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            _ = try ModelContainer(for: schema, configurations: [config])
            logger.debug("Schema validation passed — \(schema.entities.count, privacy: .public) entities.")
        } catch {
            logger.error("Schema validation FAILED: \(error.localizedDescription, privacy: .public)")
            assertionFailure("SwiftData schema validation failed: \(error)")
        }
    }
}
#endif
