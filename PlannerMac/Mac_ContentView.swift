import SwiftUI

// MARK: - Mac_ContentView
//
// macOS root layout. Replaces the iOS `TabView` (ContentView) with a
// `NavigationSplitView` sidebar. The natural-language capture bar sits ABOVE
// the split so it's always reachable, exactly like the iOS overview bar.
//
// First Mac release scope: Capture + Tasks + Goals. Notes and Calendar are
// deferred, so the sidebar intentionally lists only three destinations.

struct Mac_ContentView: View {
    @Environment(ThemeStore.self) private var theme
    @State private var selection: Pane? = .overview

    enum Pane: String, CaseIterable, Identifiable {
        case overview, tasks, goals
        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: return "Overview"
            case .tasks:    return "Tasks"
            case .goals:    return "Goals"
            }
        }
        var glyph: String {
            switch self {
            case .overview: return "square.grid.2x2"
            case .tasks:    return "checklist"
            case .goals:    return "target"
            }
        }
    }

    var body: some View {
        let p = theme.palette
        VStack(spacing: 0) {
            Mac_CaptureBar()
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider().opacity(0.4)

            NavigationSplitView {
                List(Pane.allCases, selection: $selection) { pane in
                    Label(pane.title, systemImage: pane.glyph)
                        .tag(pane)
                }
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
            } detail: {
                switch selection ?? .overview {
                case .overview: Mac_OverviewPane()
                case .tasks:    Mac_TasksPane()
                case .goals:    Mac_GoalsPane()
                }
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .themedCanvas(p)
    }
}
