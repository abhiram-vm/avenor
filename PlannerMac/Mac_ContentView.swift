import SwiftUI
import Observation

// MARK: - Mac_Accent
//
// The single source of truth for Avenor's brand mint (`#6EE7A8`). This color
// is intentionally theme-independent: it is the capture / focus identity
// accent and stays constant across all four palettes, exactly as the iOS app
// treats it. Every Mac surface that needs mint reads it from here — there are
// no other mint literals in the Mac target.
//
// (Long-term home would be `DesignTokens.swift`, but that file is out of scope
// for this design pass; this is the centralized within-scope resolution.)
enum Mac_Accent {
    static let mint = Color(red: 110 / 255, green: 231 / 255, blue: 168 / 255)
}

// MARK: - Mac_NavState
//
// Lightweight observable that holds the active pane and a capture-focus token.
// Owned by `Mac_ContentView`, injected into the environment, and exposed to the
// scene's `.commands` via `focusedSceneValue` so global keyboard shortcuts
// (⌘1/2/3, ⌘N) can drive navigation and focus the capture bar from anywhere.
@Observable
final class Mac_NavState {
    var selection: Mac_ContentView.Pane = .overview
    /// Flip to `true` to request capture-bar focus; the bar resets it to false.
    var captureFocusToken: Bool = false

    /// Cross-pane focus request, set when an @mention or a backlink row is
    /// clicked. The destination pane observes this, scrolls the matching row
    /// into view, briefly flashes it, then clears the token back to `nil`.
    var pendingFocus: Mac_FocusTarget? = nil

    // MARK: Notes-pane command tokens
    //
    // The Notes pane's keyboard commands live in the app menu bar (the most
    // reliable place for macOS shortcuts) but act on pane-local UI. These
    // nav-level tokens bridge the two: the menu flips a token, the Notes pane
    // observes it and resets it. They're inert when any other pane is shown.

    /// ⌘N while the Notes pane is active → create + select a blank note.
    var newNoteToken: Bool = false
    /// ⌘F → focus the notes search field.
    var notesFocusSearchToken: Bool = false
    /// ⌘⇧B → show / hide the backlinks column.
    var notesShowBacklinks: Bool = false
    /// ⌘⇧R → distraction-free reading mode.
    var notesReadingMode: Bool = false

    /// Switch to the pane that owns `target` and request a scroll-to-focus.
    func focus(_ target: Mac_FocusTarget) {
        switch target {
        case .task: selection = .tasks
        case .goal: selection = .goals
        }
        pendingFocus = target
    }
}

// MARK: - Mac_FocusTarget
//
// A request to reveal a specific task or goal in its pane. Carries the item id
// so the pane can `scrollTo(_:)` it and flash a mint ring. Drives @mention and
// backlink navigation across the Notes pane.
enum Mac_FocusTarget: Equatable {
    case task(UUID)
    case goal(UUID)

    var id: UUID {
        switch self {
        case .task(let id), .goal(let id): return id
        }
    }
}

// MARK: FocusedValue plumbing (scene → commands)

struct MacNavFocusedKey: FocusedValueKey {
    typealias Value = Mac_NavState
}

extension FocusedValues {
    var macNav: Mac_NavState? {
        get { self[MacNavFocusedKey.self] }
        set { self[MacNavFocusedKey.self] = newValue }
    }
}

// MARK: - Mac_ContentView
//
// macOS root layout. Replaces the iOS `TabView` (ContentView) with a custom
// sidebar split. The natural-language capture bar sits ABOVE the split so it's
// always reachable, exactly like the iOS overview bar.
//
// The sidebar is a hand-built button rail — NOT a native `List(selection:)` —
// so it carries the mint selection accent instead of the system-blue highlight,
// in keeping with Avenor's "no native List" ethos.
//
// First Mac release scope: Capture + Overview + Tasks + Goals. Notes and
// Calendar are deferred, so the sidebar intentionally lists only three panes.

struct Mac_ContentView: View {
    @Environment(ThemeStore.self) private var theme
    @State private var nav = Mac_NavState()
    @State private var hoveredPane: Pane?

    enum Pane: String, CaseIterable, Identifiable {
        case overview, tasks, goals, notes, calendar
        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: return "Overview"
            case .tasks:    return "Tasks"
            case .goals:    return "Goals"
            case .notes:    return "Notes"
            case .calendar: return "Calendar"
            }
        }

        /// Outline glyph for the inactive state.
        var glyph: String {
            switch self {
            case .overview: return "square.grid.2x2"
            case .tasks:    return "checklist"
            case .goals:    return "target"
            case .notes:    return "doc.text"
            case .calendar: return "calendar"
            }
        }

        /// Filled glyph for the selected state, where a `.fill` variant exists.
        var glyphSelected: String {
            switch self {
            case .overview: return "square.grid.2x2.fill"
            case .tasks:    return "checklist"   // no filled variant
            case .goals:    return "target"      // no filled variant
            case .notes:    return "doc.text.fill"
            case .calendar: return "calendar"    // no filled variant
            }
        }
    }

    var body: some View {
        let p = theme.palette
        VStack(spacing: 0) {
            Mac_CaptureBar(shouldFocus: $nav.captureFocusToken)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            RowSeparator()

            NavigationSplitView {
                sidebar(p)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            } detail: {
                detail
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .themedCanvas(p)
        .environment(nav)
        .focusedSceneValue(\.macNav, nav)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch nav.selection {
        case .overview: Mac_OverviewPane()
        case .tasks:    Mac_TasksPane()
        case .goals:    Mac_GoalsPane()
        case .notes:    Mac_NotesPane()
        case .calendar: Mac_CalendarPane()
        }
    }

    // MARK: Sidebar (custom button rail)

    private func sidebar(_ p: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Pane.allCases) { pane in
                navButton(pane, palette: p)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(p.canvasView)
    }

    private func navButton(_ pane: Pane, palette p: ThemePalette) -> some View {
        let selected = nav.selection == pane
        let hovered = hoveredPane == pane
        return Button {
            nav.selection = pane
        } label: {
            HStack(spacing: 10) {
                // Mint left accent mark for the selected pane (mirrors the iOS
                // task-row rail as the "this is active" signal).
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(selected ? Mac_Accent.mint : Color.clear)
                    .frame(width: 2, height: 16)

                Image(systemName: selected ? pane.glyphSelected : pane.glyph)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? Mac_Accent.mint : p.textSecondary)
                    .frame(width: 20)

                Text(pane.title)
                    .font(p.font(.body))
                    .foregroundStyle(selected ? Mac_Accent.mint : p.textSecondary)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .padding(.trailing, 8)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .fill(
                        selected
                            ? Mac_Accent.mint.opacity(0.12)
                            : (hovered ? p.chromeSurface : Color.clear)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredPane = $0 ? pane : (hoveredPane == pane ? nil : hoveredPane) }
        .animation(.easeInOut(duration: 0.12), value: selected)
        .animation(.easeInOut(duration: 0.12), value: hovered)
    }
}

// MARK: - Mac_TaskRow
//
// Shared task row consumed by both the Tasks and Overview panes. Copies the
// iOS `TaskRow` anatomy (Planner/Views/TasksViews.swift) — 2pt type-colored
// left rail, uppercase micro-tracked meta strip, square checkbox, trailing
// chevron — translated to a self-contained Mac card with a hover lift and a
// right-click context menu. All mutation routes through the caller's closures
// (which call the shared service layer); the row never touches SwiftData.

struct Mac_TaskRow: View {
    @Environment(ThemeStore.self) private var theme
    let task: PersistedTask
    var onToggleComplete: () -> Void
    var onEdit: (() -> Void)? = nil
    var onDelete: () -> Void
    /// Mint ring flash when navigated to via an @mention / backlink.
    var highlighted: Bool = false

    @State private var hovering = false

    private var isDone: Bool { task.isDone ?? false }
    private var isHighPriority: Bool { task.priorityLevel == .p1 }

    var body: some View {
        let p = theme.palette
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
        HStack(spacing: 0) {
            rail(p)
            content(p)
        }
        .background(shape.fill(hovering ? p.chromeSurface : p.rowFill))
        .overlay(shape.strokeBorder(highlighted ? Mac_Accent.mint : p.hairline, lineWidth: highlighted ? 1.5 : 1))
        .clipShape(shape)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovering)
        .animation(.easeInOut(duration: 0.2), value: highlighted)
        .contextMenu {
            Button(isDone ? "Mark Incomplete" : "Complete") { onToggleComplete() }
            if let onEdit { Button("Edit…") { onEdit() } }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    // MARK: Accent rail (2pt; 3pt + accent glow for a live P1)

    private func rail(_ p: ThemePalette) -> some View {
        Rectangle()
            .fill(railColor(p))
            .frame(width: isHighPriority ? 3 : 2)
            .frame(maxHeight: .infinity)
    }

    private func railColor(_ p: ThemePalette) -> Color {
        if isDone { return p.textTertiary }
        if isHighPriority { return p.accent }
        return task.type.tint.opacity(0.85)
    }

    // MARK: Content

    private func content(_ p: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            metaStrip(p)
            titleRow(p)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Meta strip — TYPE · DATE

    private func metaStrip(_ p: ThemePalette) -> some View {
        HStack(spacing: 0) {
            metaToken(task.type.pillTitle, palette: p)

            if let dateMeta {
                Text("·")
                    .font(p.font(.micro))
                    .foregroundStyle(p.textTertiary)
                    .padding(.horizontal, 8)
                metaToken(dateMeta, palette: p, monospaced: true)
            }

            Spacer(minLength: 0)
        }
    }

    private func metaToken(_ text: String, palette p: ThemePalette, monospaced: Bool = false) -> some View {
        Text(text)
            .font(p.font(.micro))
            .tracking(p.microTracking)
            .textCase(.uppercase)
            .monospacedDigit()
            .foregroundStyle(p.textTertiary)
            .lineLimit(1)
    }

    // MARK: Title row — checkbox + title + chevron

    private func titleRow(_ p: ThemePalette) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onToggleComplete) {
                Image(systemName: isDone ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(isDone ? p.textPrimary : p.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)

            Text(task.title.isEmpty ? "Untitled" : task.title)
                .font(p.font(.headline))
                .tracking(p.headlineTracking)
                .foregroundStyle(isDone ? p.textTertiary : p.textPrimary)
                .strikethrough(isDone, color: p.textTertiary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(p.textTertiary)
        }
    }

    // MARK: Date meta string

    private var dateMeta: String? {
        guard let due = task.dueDate else { return nil }
        let cal = Calendar.autoupdatingCurrent
        if cal.isDateInToday(due) { return "Due Today" }
        if cal.isDateInTomorrow(due) { return "Tomorrow" }
        return due.formatted(.dateTime.month(.abbreviated).day())
    }
}
