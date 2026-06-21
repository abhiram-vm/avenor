import SwiftUI
import SwiftData

// MARK: - Mac_CaptureBar
//
// The hero element: the glass capture bar pinned to the bottom of the content
// column. Free text runs through `CaptureParser.parse(_:)` on Return and routes
// to the matching model insert — byte-for-byte the same routing as iOS
// `OverviewTabView.commitCapture`, minus the iOS-only Live Activity countdown.
//
// This is one of the app's two sanctioned glass moments: `.ultraThinMaterial`
// with a hairline specular top edge. Idle it sits quiet; focus blooms a soft
// mint radial behind it and lights the border mint; a successful capture pulses
// the border to full mint and bounces the `>` glyph, then settles back to idle.

struct Mac_CaptureBar: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeStore.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// External focus trigger (⌘N). Set to true to focus the bar; the bar
    /// resets it to false immediately after acquiring focus.
    var shouldFocus: Binding<Bool> = .constant(false)

    @State private var text = ""
    /// Brief mint border flash on a successful capture, then fades out.
    @State private var flash = false
    /// Goal awaiting a unit choice — drives the unit-picker sheet.
    @State private var pendingGoal: Mac_PendingGoal?
    @State private var particleView = MetalParticleView()
    @FocusState private var focused: Bool

    var body: some View {
        let p = theme.palette
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)

        HStack(spacing: 14) {
            // CLI prompt glyph — the brand mint `>`, large and always visible.
            Text(">")
                .font(.system(size: 19, weight: .bold, design: .monospaced))
                .foregroundStyle(Mac_Accent.mint)
                .scaleEffect(flash ? 1.12 : 1.0)

            TextField("", text: $text, prompt: prompt(p))
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .regular, design: p.fontDesign))
                .foregroundStyle(p.textPrimary)
                .tint(Mac_Accent.mint)
                .focused($focused)
                .autocorrectionDisabled()
                .onSubmit(commit)
        }
        .padding(.horizontal, 22)
        .frame(height: 60)
        .background {
            // Mint focus bloom — a soft radial behind the glass, idle-invisible.
            shape
                .fill(
                    RadialGradient(
                        colors: [Mac_Accent.mint.opacity(focused ? 0.10 : 0),
                                 Mac_Accent.mint.opacity(0)],
                        center: .leading,
                        startRadius: 0,
                        endRadius: 360
                    )
                )
                .blur(radius: 18)
                .padding(-8)
        }
        .background(shape.fill(.ultraThinMaterial))
        .background(
            MetalParticleViewRepresentable(view: particleView, reduceMotion: reduceMotion)
                .allowsHitTesting(false)
                .clipShape(shape)
        )
        .overlay(specular(shape))
        .overlay(shape.strokeBorder(borderColor(p), lineWidth: flash ? 1.5 : 1))
        .clipShape(shape)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: focused)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: flash)
        .onAppear { focused = true }
        .onChange(of: focused) { _, isFocused in
            isFocused ? particleView.triggerFocus() : particleView.triggerIdle()
        }
        .onChange(of: shouldFocus.wrappedValue) { _, newValue in
            if newValue {
                focused = true
                shouldFocus.wrappedValue = false
            }
        }
        .sheet(item: $pendingGoal) { pending in
            Mac_GoalUnitPickerSheet(pending: pending) { unit in
                let goal = PersistedGoal(
                    title: pending.title,
                    unit: unit,
                    currentValue: 0,
                    targetValue: pending.targetValue
                )
                modelContext.insert(goal)
                try? modelContext.save()
                flash = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { flash = false }
            }
        }
    }

    // MARK: Glass specular top edge

    private func specular(_ shape: RoundedRectangle) -> some View {
        shape
            .stroke(
                LinearGradient(
                    colors: [.white.opacity(0.05), .clear],
                    startPoint: .top,
                    endPoint: .center
                ),
                lineWidth: 1
            )
            .allowsHitTesting(false)
    }

    // MARK: Prompt + border

    /// Space-Mono-feel placeholder: monospaced, wide tracking, whisper opacity.
    private func prompt(_ p: ThemePalette) -> Text {
        Text("Capture a task, idea, goal, or note…")
            .font(.system(size: 14, weight: .regular, design: .monospaced))
            .tracking(0.8)
            .foregroundColor(p.textTertiary)
    }

    private func borderColor(_ p: ThemePalette) -> Color {
        if flash { return Mac_Accent.mint }
        return focused ? Mac_Accent.mint.opacity(0.55) : p.hairline
    }

    // MARK: Capture routing (mirrors OverviewTabView.commitCapture)

    private func commit() {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let intent = CaptureParser.parse(raw) else { return }

        switch intent {
        case .todo(let title, let dueDate, let priority):
            let task = PersistedTask(title: title, type: .todo, dueDate: dueDate, priority: priority)
            modelContext.insert(task)
            NotificationManager.shared.schedule(for: task)

        case .idea(let title, let tag, let priority):
            let task = PersistedTask(
                title: title,
                type: .idea,
                ideaStatus: .thinking,
                ideaTag: tag.isEmpty ? nil : tag,
                priority: priority
            )
            modelContext.insert(task)

        case .reminder(let title, let dueDate, let priority):
            let task = PersistedTask(title: title, type: .reminder, dueDate: dueDate, priority: priority)
            modelContext.insert(task)
            NotificationManager.shared.schedule(for: task)

        case .note(let title, let body):
            let note = PersistedNote(title: title, details: body, lastEditedAt: .now)
            modelContext.insert(note)

        case .habit(let title, let rule, let anchor, let tag, let priority):
            let habit = PersistedHabit(
                title: title,
                recurrence: rule,
                anchorDate: anchor,
                tag: tag,
                priority: priority
            )
            modelContext.insert(habit)

        case .calendar(let title, let startDate, let duration):
            // Calendar events live in EventKit, not SwiftData. Silent create on
            // the default calendar (no app-switch). A failed create (e.g. access
            // not yet granted) leaves the text in place and skips the flash.
            let created = EventKitService.shared.createEvent(
                title: title,
                startDate: startDate,
                duration: duration,
                context: modelContext
            )
            if !created { return }

        case .goal(let title, let targetValue, let unit, let dueDate):
            // A detected unit creates the goal straight away; an ambiguous one
            // defers to the unit-picker sheet (which owns the insert). Goal
            // creation is a fresh insert, not a mutation, so it bypasses
            // GoalMutator — same pattern as Mac_AddGoalSheet.
            if let unit {
                let goal = PersistedGoal(
                    title: title,
                    unit: Mac_GoalUnitCatalog.unit(for: unit),
                    currentValue: 0,
                    targetValue: targetValue
                )
                modelContext.insert(goal)
            } else {
                pendingGoal = Mac_PendingGoal(title: title, targetValue: targetValue, dueDate: dueDate)
                text = ""
                return  // sheet completes the capture; skip the common save/flash
            }
        }

        // Commit immediately so @Query-backed panes update without waiting for
        // the autosave coalescing window.
        try? modelContext.save()
        text = ""

        // Mint capture flash + particle burst, then fade back to idle.
        flash = true
        particleView.triggerCapture()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            flash = false
        }
    }
}
