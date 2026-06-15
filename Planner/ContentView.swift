import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.modelContext) private var modelContext

    // Overview is the default landing surface — a ruthless global timeline.
    // Other tabs follow in priority order: actionable today (Tasks), free-form
    // capture (Notes), measurable outcomes + routines (Progress: goals &
    // habits), temporal lookup (Calendar). Held to five tabs so iOS never
    // collapses anything into the system "More" overflow.
    @State private var selectedTab: Int = 0

    /// Passes through from PlannerApp's onOpenURL handler so the capture bar
    /// can be focused externally (e.g. Action Button, Spotlight, URL scheme).
    var captureOnOpen: Binding<Bool> = .constant(false)

    // Builds OverviewTabView with the external-focus binding wired in.
    // Using the stored-property-after-init pattern so the call site in body
    // stays simple and OverviewTabView's default initializer is preserved.
    private var overviewView: some View {
        var view = OverviewTabView()
        view.shouldFocusCapture = captureOnOpen
        return view
    }

    var body: some View {
        let p = theme.palette
        TabView(selection: $selectedTab) {
            overviewView
                .tabItem { Label("Overview", systemImage: "square.grid.2x2") }
                .tag(0)

            TasksTabView()
                .tabItem { Label("Tasks", systemImage: "checkmark.square") }
                .tag(1)

            NotesTabView()
                .tabItem { Label("Notes", systemImage: "doc.text") }
                .tag(2)

            GoalsTabView()
                .tabItem { Label("Goals", systemImage: "scope") }
                .tag(3)

            CalendarTabView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(4)
        }
        .onChange(of: captureOnOpen.wrappedValue) { _, newValue in
            if newValue { selectedTab = 0 }
        }
        .tint(p.controlTint)

        // Translucent toolbar chrome tinted to the active palette's color
        // scheme so labels read correctly across light/dark themes.
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(p.colorScheme, for: .tabBar)

        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(p.colorScheme, for: .navigationBar)

        // Honor the palette's color scheme so system widgets (search bars,
        // pickers, etc.) match the active theme.
        .preferredColorScheme(p.colorScheme)

        // One-shot legacy JSON → SwiftData migration on first launch.
        // Idempotent and fail-soft — safe to call every launch.
        .task {
            MigrationService.runIfNeeded(context: modelContext)
        }
    }
}

#Preview {
    ContentView()
        .environment(ThemeStore())
        .modelContainer(
            for: [PersistedTask.self, PersistedNote.self, PersistedGoal.self, PersistedHabit.self],
            inMemory: true
        )
}
