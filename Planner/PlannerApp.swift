import SwiftUI
import SwiftData
import os

private let launchLog = Logger(subsystem: "com.avenor.planner", category: "launch")

@main
struct PlannerApp: App {
    @State private var theme = ThemeStore()

    // Created eagerly in init() so failure is caught before any view renders.
    // nil means creation threw; body shows the error screen instead.
    private let container: ModelContainer?

    init() {
        #if DEBUG
        // Internal-beta safety net: force the SwiftData model graph to
        // validate on launch so a broken schema / migration surfaces in
        // DEBUG + TestFlight smoke runs rather than on a user's device.
        SchemaValidator.validateOnLaunch()
        #endif

        // Explicit container creation with error surfacing. Previously the
        // scene-level .modelContainer(for:) modifier swallowed failures
        // silently, leaving every downstream try? context.save() swallowing
        // the symptom. A fault-level log entry here gives a clear crash
        // trail in Instruments / Console even on release builds.
        do {
            container = try ModelContainer(
                for: PersistedTask.self,
                     PersistedNote.self,
                     PersistedGoal.self,
                     PersistedHabit.self
            )
        } catch {
            launchLog.fault(
                "ModelContainer creation failed — showing error screen. Error: \(error.localizedDescription, privacy: .public)"
            )
            container = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
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

                        // One-time "Convert & Retire" bridge: mint a habit per
                        // active legacy goal, then flip the goal to `.converted`.
                        //
                        // Guard: probe the PersistedHabit entity with a limit-1
                        // fetch before attempting any mutations. If the store
                        // hasn't settled its additive schema migration for
                        // PersistedHabit yet, this fetch throws — we skip the
                        // migration entirely and retry on the next launch.
                        // Inserting into an unsettled context is undefined
                        // behaviour in SwiftData and can cause a silent assertion
                        // crash or data loss with no recoverable error surface.
                        do {
                            var habitProbe = FetchDescriptor<PersistedHabit>()
                            habitProbe.fetchLimit = 1
                            _ = try context.fetch(habitProbe)
                            GoalConversionMigration.runIfNeeded(in: context)
                        } catch {
                            launchLog.error(
                                "PersistedHabit store not settled — skipping GoalConversionMigration this launch. Will retry. Error: \(error.localizedDescription, privacy: .public)"
                            )
                            // Deliberately do NOT set the UserDefaults guard flag.
                            // runIfNeeded checks the flag itself; leaving it unset
                            // guarantees a retry on the next launch.
                        }

                        LifecycleAutomation.runDailyMaintenance(in: context)
                        WidgetActionApplier.drainAndApply(in: context)

                        // Seed the widget's App Group payload immediately on
                        // launch. Without this the snapshot stays empty until
                        // the user first visits the Tasks tab, so the widget
                        // renders its header but zero tasks. Publish after the
                        // drain above so any widget taps applied this launch are
                        // already reflected.
                        let tasks = try? context.fetch(FetchDescriptor<PersistedTask>())
                        WidgetSnapshotPublisher.publishToday(tasks: tasks ?? [])
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
                            // Refresh the widget payload on every foreground
                            // return so the snapshot reflects edits made in
                            // other sessions / on other devices since launch.
                            let tasks = try? context.fetch(FetchDescriptor<PersistedTask>())
                            WidgetSnapshotPublisher.publishToday(tasks: tasks ?? [])
                        case .inactive, .background:
                            // Prune stale countdowns when leaving the foreground
                            // too, so an expired Live Activity never lingers on the
                            // Lock Screen / Dynamic Island after the event passed.
                            EventLiveActivityManager.endExpired()
                        @unknown default:
                            break
                        }
                    }
                    .modelContainer(container)
            } else {
                // ModelContainer failed to open. Show a minimal, user-friendly
                // screen. No retry — a broken container needs a restart (or an
                // OS-level store repair) before any SwiftData access is safe.
                ZStack {
                    Color.black.ignoresSafeArea()
                    Text("Something went wrong. Please restart Avenor.")
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
        }
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
