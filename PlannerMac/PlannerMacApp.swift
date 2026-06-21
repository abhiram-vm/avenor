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

    /// The active window's nav state, surfaced from `Mac_ContentView` via
    /// `focusedSceneValue`. Drives the global menu commands (⌘1/2/3, ⌘N).
    @FocusedValue(\.macNav) private var nav

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
                    // Global mint accent — kills every system-blue selection /
                    // focus state app-wide. No native control keeps blue.
                    .tint(Mac_Accent.mint)
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
                    DesignTokens.Surface.canvas.ignoresSafeArea()
                    Text("Something went wrong. Please restart Avenor.")
                        .foregroundStyle(.white.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
        }
        .defaultSize(width: 1180, height: 780)
        // Blend the title bar into the canvas — no default chrome separation.
        .windowStyle(.hiddenTitleBar)
        .commands { macCommands }

        Settings {
            Mac_SettingsView()
                .environment(theme)
        }
    }

    // MARK: Global keyboard shortcuts
    //
    // Pane switching and capture focus drive the scene-level `Mac_NavState`
    // exposed via `focusedSceneValue`. ⌘F (search) is intentionally omitted:
    // no Mac pane currently has a search field, and the brief gates it on one
    // existing. Escape is handled per-sheet via `.cancelAction` Cancel buttons.

    @CommandsBuilder
    private var macCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            // ⌘N is context-aware: in the Notes pane it creates a new note;
            // everywhere else it focuses the capture bar.
            Button("New") {
                if nav?.selection == .notes {
                    nav?.newNoteToken = true
                } else {
                    nav?.captureFocusToken = true
                }
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        CommandMenu("View") {
            Button("Overview") { nav?.selection = .overview }
                .keyboardShortcut("1", modifiers: .command)
            Button("Tasks") { nav?.selection = .tasks }
                .keyboardShortcut("2", modifiers: .command)
            Button("Goals") { nav?.selection = .goals }
                .keyboardShortcut("3", modifiers: .command)
            Button("Notes") { nav?.selection = .notes }
                .keyboardShortcut("4", modifiers: .command)
            Button("Calendar") { nav?.selection = .calendar }
                .keyboardShortcut("5", modifiers: .command)
            Button("Routines") { nav?.selection = .routines }
                .keyboardShortcut("6", modifiers: .command)

            Divider()

            // ⌘F is context-aware (mirrors ⌘N): the Tasks pane focuses its
            // inline search; the Notes pane focuses its search field. Inert
            // elsewhere — both are nav tokens the destination pane resets.
            Button("Find") {
                if nav?.selection == .tasks {
                    nav?.tasksFocusSearchToken = true
                } else {
                    nav?.notesFocusSearchToken = true
                }
            }
            .keyboardShortcut("f", modifiers: .command)
            Button("Toggle Backlinks") { nav?.notesShowBacklinks.toggle() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            Button("Reading Mode") { nav?.notesReadingMode.toggle() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
}
