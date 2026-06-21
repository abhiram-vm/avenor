import SwiftUI
import SwiftData

// MARK: - Mac_BacklinksPanel
//
// The right column of the Notes pane (~240pt), toggled with ⌘⇧B. Shows what
// "references" the selected note, computed two ways:
//   • Tasks & Goals whose title text appears inside the note's body.
//   • Other notes whose body contains the selected note's title.
//
// This is a lightweight, link-graph-free heuristic (plain case-insensitive
// substring containment) — no schema, no stored edges, recomputed live from
// the current `@Query` results. Clicking a task/goal routes through the shared
// `Mac_NavState.focus(_:)` (switch pane + scroll-flash); clicking a note asks
// the parent pane to select it via `onSelectNote`.

struct Mac_BacklinksPanel: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(Mac_NavState.self) private var nav

    @Query private var allTasks: [PersistedTask]
    @Query private var allGoals: [PersistedGoal]
    @Query private var allNotes: [PersistedNote]

    let note: PersistedNote?
    var onSelectNote: (PersistedNote) -> Void

    var body: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: 0) {
            header(p)
            Divider().overlay(p.hairline)

            if note == nil {
                placeholder("Select a note", p)
            } else if referencingTasks.isEmpty && referencingGoals.isEmpty && referencingNotes.isEmpty {
                placeholder("No references yet", p)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !referencingTasks.isEmpty || !referencingGoals.isEmpty {
                            section("Tasks & Goals", p) {
                                ForEach(referencingTasks) { task in
                                    row(task.title.isEmpty ? "Untitled" : task.title,
                                        icon: task.type.icon,
                                        tint: task.type.tint,
                                        palette: p) {
                                        nav.focus(.task(task.id))
                                    }
                                }
                                ForEach(referencingGoals) { goal in
                                    row(goal.title.isEmpty ? "Untitled" : goal.title,
                                        icon: "target",
                                        tint: goal.displayTint,
                                        palette: p) {
                                        nav.focus(.goal(goal.id))
                                    }
                                }
                            }
                        }
                        if !referencingNotes.isEmpty {
                            section("Notes", p) {
                                ForEach(referencingNotes) { other in
                                    row(other.title.isEmpty ? "Untitled" : other.title,
                                        icon: "doc.text",
                                        tint: DesignTokens.Accent.note,
                                        palette: p) {
                                        onSelectNote(other)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                }
                .scrollIndicators(.hidden)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The Notes pane's second sanctioned glass moment: ultra-thin material
        // with a hairline specular top edge.
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.04))
                .frame(height: 1)
                .allowsHitTesting(false)
        }
    }

    // MARK: Header

    private func header(_ p: ThemePalette) -> some View {
        Text("Referenced By")
            .font(p.font(.micro))
            .tracking(p.microTracking)
            .textCase(.uppercase)
            .foregroundStyle(p.textTertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func placeholder(_ text: String, _ p: ThemePalette) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .tracking(p.microTracking)
            .foregroundStyle(p.textTertiary)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Section + row

    private func section<Content: View>(_ label: String, _ p: ThemePalette, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(Mac_Accent.violet)
                .padding(.bottom, 2)
            content()
        }
    }

    private func row(_ title: String, icon: String, tint: Color, palette p: ThemePalette, action: @escaping () -> Void) -> some View {
        Mac_BacklinkRow(title: title, icon: icon, tint: tint, action: action)
    }

    // MARK: Backlink computation

    private var referencingTasks: [PersistedTask] {
        guard let note else { return [] }
        let body = note.details
        guard !body.isEmpty else { return [] }
        return allTasks.filter { t in
            let title = t.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.count >= 2 && body.localizedCaseInsensitiveContains(title)
        }
    }

    private var referencingGoals: [PersistedGoal] {
        guard let note else { return [] }
        let body = note.details
        guard !body.isEmpty else { return [] }
        return allGoals.filter { g in
            let title = g.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.count >= 2 && body.localizedCaseInsensitiveContains(title)
        }
    }

    private var referencingNotes: [PersistedNote] {
        guard let note else { return [] }
        let myTitle = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard myTitle.count >= 2 else { return [] }
        return allNotes.filter { other in
            other.id != note.id
                && !other.isArchived
                && other.details.localizedCaseInsensitiveContains(myTitle)
        }
    }
}

// MARK: - Mac_BacklinkRow

private struct Mac_BacklinkRow: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let icon: String
    let tint: Color
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        let p = theme.palette
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.85))
                    .frame(width: 16)
                Text(title)
                    .font(p.font(.body))
                    .foregroundStyle(p.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .fill(hovering ? p.chromeSurface : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: hovering)
    }
}
