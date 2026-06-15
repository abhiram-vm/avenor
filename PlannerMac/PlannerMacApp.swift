import SwiftUI
import SwiftData
import os

// MARK: - PlannerMacApp
//
// macOS entry point for Avenor. Mirrors `PlannerApp` (iOS): the SAME four
// SwiftData models, the SAME default `ModelContainer`, and the SAME
// `ThemeStore`, so the two platforms share one schema. The Mac build omits the
// iOS-only launch hooks (Live Activities, widget timeline reloads) — those are
// compiled out of the Mac target.
//
// ⚠️ Target membership: this file belongs to the macOS target ONLY. The iOS
//    `PlannerApp.swift` (its own `@main`) must NOT be a member of the Mac
//    target, and this file must NOT be a member of the iOS target — otherwise
//    the build sees two `@main` App types.
//
// ⚠️ CloudKit sync: this target's container is CloudKit-backed
//    (`cloudKitDatabase: .automatic`), resolving to `iCloud.com.avenor.planner`
//    via the entitlements file. Sync becomes bidirectional ONLY once the iOS
//    target ALSO moves to a CloudKit-backed ModelConfiguration AND gains the
//    matching iCloud entitlement — both of which are out of scope here (the iOS
//    `PlannerApp.swift` stays untouched). Until then the Mac writes to the
//    private CloudKit DB and iOS writes to its local store; they will not meet.

private let macLaunchLog = Logger(subsystem: "com.avenor.planner", category: "launch.mac")

@main
struct PlannerMacApp: App {
    @State private var theme = ThemeStore()

    // Created eagerly so a schema failure surfaces before any view renders.
    private let container: ModelContainer?

    init() {
        do {
            let schema = Schema([
                PersistedTask.self,
                PersistedNote.self,
                PersistedGoal.self,
                PersistedHabit.self
            ])
            // `.automatic` adopts the container declared in PlannerMac.entitlements
            // (`iCloud.com.avenor.planner`).
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            macLaunchLog.fault(
                "ModelContainer creation failed — showing error screen. Error: \(error.localizedDescription, privacy: .public)"
            )
            container = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                Mac_ContentView()
                    .environment(theme)
                    .task {
                        // One-shot, system-cached after the first prompt.
                        await NotificationManager.shared.requestAuthorization()
                    }
                    .task {
                        // Same launch maintenance as iOS, minus the widget /
                        // Live Activity side effects. Runs on the main actor
                        // (the service layer is @MainActor-isolated).
                        let context = container.mainContext
                        ConflictResolver.reconcile(in: context)
                        LifecycleAutomation.runDailyMaintenance(in: context)
                    }
                    .modelContainer(container)
            } else {
                ZStack {
                    Color.black.ignoresSafeArea()
                    Text("Something went wrong. Please restart Avenor.")
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
        }
        .defaultSize(width: 980, height: 640)

        Settings {
            Mac_SettingsView()
                .environment(theme)
        }
    }
}
