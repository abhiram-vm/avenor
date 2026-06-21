import SwiftUI
import Observation

// MARK: - Mac_Accent
//
// The single source of truth for Avenor's brand mint (`#6EE7A8`). This color is
// intentionally theme-independent: it is the capture / focus identity accent and
// stays constant across all four palettes, exactly as the iOS app treats it.
// Every Mac surface that needs mint reads it from here. The companion violet
// (`#7C3AED`, ideas / backlinks) lives in Mac_DesignKit.swift. These two are the
// only hardcoded color literals permitted in the Mac target.
enum Mac_Accent {
    static let mint = Color(red: 110 / 255, green: 231 / 255, blue: 168 / 255)
}

// MARK: - Mac_NavState
//
// Lightweight observable that holds the active pane and a capture-focus token.
// Owned by `Mac_ContentView`, injected into the environment, and exposed to the
// scene's `.commands` via `focusedSceneValue` so global keyboard shortcuts
// (⌘1–5, ⌘N, ⌘F) can drive navigation and focus from anywhere.
@Observable
final class Mac_NavState {
    var selection: Mac_ContentView.Pane = .overview
    /// Flip to `true` to request capture-bar focus; the bar resets it to false.
    var captureFocusToken: Bool = false

    /// Cross-pane focus request, set when an @mention or a backlink row is
    /// clicked. The destination pane observes this, scrolls the matching row
    /// into view, briefly flashes it, then clears the token back to `nil`.
    var pendingFocus: Mac_FocusTarget? = nil

    // MARK: Pane-local command tokens
    //
    // Keyboard commands live in the app menu bar (the most reliable place for
    // macOS shortcuts) but act on pane-local UI. These nav-level tokens bridge
    // the two: the menu flips a token, the owning pane observes and resets it.
    // They're inert when any other pane is shown.

    /// ⌘N while the Notes pane is active → create + select a blank note.
    var newNoteToken: Bool = false
    /// ⌘F in the Tasks pane → reveal + focus the inline task search field.
    var tasksFocusSearchToken: Bool = false
    /// ⌘F in the Notes pane → focus the notes search field.
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
// macOS root layout. A narrow 48pt icon rail on the left, the active pane
// filling the center, and the glass capture bar pinned to the BOTTOM of the
// content column — the window's center of gravity. The film grain is composited
// once here, over everything, never per pane.
//
// No `NavigationSplitView`, no native `List`: the rail is a hand-built button
// column carrying the mint selection accent, and panes crossfade with a blur on
// switch. This is the "nothing like a default SwiftUI app" layer.

struct Mac_ContentView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nav = Mac_NavState()
    @State private var hoveredItem: RailItem?

    enum Pane: String, CaseIterable, Identifiable {
        case overview, tasks, goals, notes, calendar, routines
        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview:  return "Overview"
            case .tasks:     return "Tasks"
            case .goals:     return "Goals"
            case .notes:     return "Notes"
            case .calendar:  return "Calendar"
            case .routines:  return "Routines"
            }
        }

        /// Outline glyph for the inactive state.
        var glyph: String {
            switch self {
            case .overview:  return "house"
            case .tasks:     return "checkmark.circle"
            case .goals:     return "target"
            case .notes:     return "doc.text"
            case .calendar:  return "calendar"
            case .routines:  return "flame"
            }
        }

        /// Filled glyph for the selected state, where a `.fill` variant exists.
        var glyphSelected: String {
            switch self {
            case .overview:  return "house.fill"
            case .tasks:     return "checkmark.circle.fill"
            case .goals:     return "target"
            case .notes:     return "doc.text.fill"
            case .calendar:  return "calendar"
            case .routines:  return "flame.fill"
            }
        }
    }

    /// Items in the icon rail — panes plus the settings gear at the foot.
    enum RailItem: Hashable {
        case pane(Pane)
        case settings
    }

    var body: some View {
        let p = theme.palette
        ZStack {
            p.canvasView

            HStack(spacing: 0) {
                sidebar(p)

                VStack(spacing: 0) {
                    paneContent(p)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    RowSeparator()

                    Mac_CaptureBar(shouldFocus: $nav.captureFocusToken)
                }
            }

            // Film grain — composited once, over the whole window.
            Mac_FilmGrain()
        }
        .frame(minWidth: 1100, minHeight: 700)
        .environment(nav)
        .focusedSceneValue(\.macNav, nav)
    }

    // MARK: Pane content (blur-fade crossfade on switch)

    private func paneContent(_ p: ThemePalette) -> some View {
        ZStack {
            detail
                .id(nav.selection)
                .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.macBlurFade)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: nav.selection)
    }

    @ViewBuilder
    private var detail: some View {
        switch nav.selection {
        case .overview:  Mac_OverviewPane()
        case .tasks:     Mac_TasksPane()
        case .goals:     Mac_GoalsPane()
        case .notes:     Mac_NotesPane()
        case .calendar:  Mac_CalendarPane()
        case .routines:  Mac_RoutinesPane()
        }
    }

    // MARK: Sidebar — 48pt icon rail

    private func sidebar(_ p: ThemePalette) -> some View {
        VStack(spacing: 6) {
            ForEach(Pane.allCases) { pane in
                railButton(.pane(pane), palette: p)
            }
            Spacer(minLength: 0)
            railButton(.settings, palette: p)
        }
        // Top inset clears the floating traffic lights; bottom breathes.
        .padding(.top, 34)
        .padding(.bottom, 14)
        .frame(width: 48)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(p.canvasView)
        // Right-edge hairline — the rail reads as a column, not a panel.
        .overlay(alignment: .trailing) {
            Rectangle().fill(p.hairline).frame(width: 0.5)
        }
    }

    @ViewBuilder
    private func railButton(_ item: RailItem, palette p: ThemePalette) -> some View {
        let selected: Bool = {
            if case .pane(let pane) = item { return nav.selection == pane }
            return false
        }()
        let hovered = hoveredItem == item

        Button {
            switch item {
            case .pane(let pane): nav.selection = pane
            case .settings: break   // handled by the SettingsLink overlay
            }
        } label: {
            ZStack {
                // Selected fill — a mint pill behind the glyph.
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .fill(selected ? Mac_Accent.mint.opacity(0.08) : (hovered ? p.chromeSurface : .clear))
                    .frame(width: 32, height: 32)

                Image(systemName: glyph(for: item, selected: selected))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(glyphColor(for: item, selected: selected, hovered: hovered, palette: p))
            }
            .frame(width: 48, height: 38)
            // 2pt mint accent mark hugging the left edge of the selected item.
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(selected ? Mac_Accent.mint : .clear)
                    .frame(width: 2, height: 18)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText(for: item))
        .onHover { hoveredItem = $0 ? item : (hoveredItem == item ? nil : hoveredItem) }
        // Hover is a direct state — no animation, per the brief.
        .overlay {
            // SettingsLink hosts Mac_SettingsView; transparent, same hit target.
            if case .settings = item {
                SettingsLink { Color.clear.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .frame(width: 48, height: 38)
            }
        }
    }

    private func glyph(for item: RailItem, selected: Bool) -> String {
        switch item {
        case .pane(let pane): return selected ? pane.glyphSelected : pane.glyph
        case .settings: return "gearshape"
        }
    }

    private func glyphColor(for item: RailItem, selected: Bool, hovered: Bool, palette p: ThemePalette) -> Color {
        if selected { return Mac_Accent.mint }
        if hovered { return p.textSecondary }
        return p.textTertiary
    }

    private func helpText(for item: RailItem) -> String {
        switch item {
        case .pane(let pane): return pane.title
        case .settings: return "Settings"
        }
    }
}

// MARK: - Mac_TaskRow
//
// Shared task row consumed by the Tasks and Overview panes. (Defined here, in
// Mac_ContentView.swift, by design — not split into its own file.) Anatomy
// mirrors the iOS `TaskRow`, scaled up for the Mac pointer: a 2pt type-colored
// rail flush to the left edge, an uppercase micro meta strip, a square checkbox,
// the title, and a trailing chevron. Hover lifts the surface; completing fades
// the row to 60% and bounces the checkmark. Right-click exposes complete / edit
// / delete. All mutation routes through the caller's closures (the service
// layer); the row never touches SwiftData.

struct Mac_TaskRow: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .frame(minHeight: 56)
        .background(shape.fill(hovering ? p.chromeSurface : p.rowFill))
        .overlay(shape.strokeBorder(highlighted ? Mac_Accent.mint : p.hairline,
                                    lineWidth: highlighted ? 1.5 : 1))
        .clipShape(shape)
        .opacity(isDone ? 0.6 : 1)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: isDone)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: highlighted)
        .contextMenu {
            Button { onToggleComplete() } label: {
                Label(isDone ? "Mark Incomplete" : "Complete", systemImage: "checkmark")
            }
            if let onEdit { Button("Edit…") { onEdit() } }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    // MARK: Accent rail (2pt; 3pt for a live P1)

    private func rail(_ p: ThemePalette) -> some View {
        Rectangle()
            .fill(railColor(p))
            .frame(width: isHighPriority ? 3 : 2)
            .frame(maxHeight: .infinity)
    }

    /// todo → mint, idea → violet (brand literals); reminder → token amber.
    /// Done rows go tertiary; a live P1 takes the palette accent.
    private func railColor(_ p: ThemePalette) -> Color {
        if isDone { return p.textTertiary }
        if isHighPriority { return p.accent }
        switch task.type {
        case .todo: return Mac_Accent.mint
        case .idea: return Mac_Accent.violet
        case .reminder: return DesignTokens.Accent.reminder
        }
    }

    // MARK: Content

    private func content(_ p: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            metaStrip(p)
            titleRow(p)
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
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
                metaToken(dateMeta, palette: p)
            }
            Spacer(minLength: 0)
        }
    }

    private func metaToken(_ text: String, palette p: ThemePalette) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1.4)
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
                    .foregroundStyle(isDone ? Mac_Accent.mint : p.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: isDone)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)

            Text(task.title.isEmpty ? "Untitled" : task.title)
                .font(.system(size: 16, weight: .medium, design: p.fontDesign))
                .tracking(p.headlineTracking)
                .foregroundStyle(isDone ? p.textTertiary : p.textPrimary)
                .strikethrough(isDone, color: p.textTertiary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(p.textTertiary)
                .opacity(hovering ? 1 : 0.55)
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
