import SwiftUI
import SwiftData

// MARK: - Mac_GoalsPane
//
// Active goals beneath an editorial "Goals" hero. New goals are created from an
// inline mint affordance (the rail has no window toolbar); each goal is managed
// via a right-click context menu (log progress / edit / abandon / delete). Every
// lifecycle mutation routes through the shared `GoalMutator`.

struct Mac_GoalsPane: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(Mac_NavState.self) private var nav
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \PersistedGoal.sortOrder) private var goals: [PersistedGoal]

    @State private var showingAdd = false
    @State private var editingGoal: PersistedGoal?
    /// Goal id currently flashing a mint ring after a cross-pane navigation.
    @State private var flashID: UUID?
    /// Goal targeted by the ⌘+ keyboard shortcut (tracks card focus).
    @State private var selectedGoal: PersistedGoal?
    @FocusState private var focusedGoalID: UUID?

    private var activeGoals: [PersistedGoal] {
        goals.filter { $0.status == .active }
    }

    var body: some View {
        let p = theme.palette
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Mac_DisplayTitle(
                        title: "Goals",
                        metaLabel: activeGoals.isEmpty ? nil : "\(activeGoals.count) ACTIVE"
                    )
                    .padding(.bottom, 22)

                    newGoalButton(p)
                        .padding(.bottom, 28)

                    if activeGoals.isEmpty {
                        Mac_CinematicEmpty(headline: "no\nactive goals", footnote: "Add one to start tracking.")
                            .padding(.top, 8)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(activeGoals) { goal in
                                Mac_GoalCard(
                                    goal: goal,
                                    onLogProgress: { incrementGoal(goal) },
                                    onIncrement: { incrementGoal(goal) },
                                    onIncrementBy: { value in incrementGoal(goal, by: value) },
                                    onEdit: { editingGoal = goal },
                                    onAbandon: {
                                        GoalMutator.abandon(goal)
                                        try? modelContext.save()
                                    },
                                    onDelete: {
                                        GoalMutator.delete(goal, in: modelContext)
                                        try? modelContext.save()
                                    },
                                    highlighted: flashID == goal.id
                                )
                                .id(goal.id)
                                .focusable()
                                .focused($focusedGoalID, equals: goal.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 56)
                .padding(.top, 60)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: nav.pendingFocus) { _, target in
                guard case .goal(let id)? = target else { return }
                reveal(id, proxy: proxy)
            }
            .onAppear {
                if case .goal(let id)? = nav.pendingFocus { reveal(id, proxy: proxy) }
            }
        }
        .onChange(of: focusedGoalID) { _, id in
            selectedGoal = activeGoals.first { $0.id == id }
        }
        // ⌘+ increments the focused goal by one step.
        .background {
            Button("") {
                if let goal = selectedGoal ?? activeGoals.first { incrementGoal(goal) }
            }
            .keyboardShortcut("+", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .themedCanvas(p)
        .sheet(isPresented: $showingAdd) {
            Mac_AddGoalSheet()
        }
        .sheet(item: $editingGoal) { goal in
            Mac_AddGoalSheet(existing: goal)
        }
    }

    private func newGoalButton(_ p: ThemePalette) -> some View {
        Button { showingAdd = true } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text("New Goal")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .textCase(.uppercase)
            }
            .foregroundStyle(Mac_Accent.mint)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                Capsule().fill(Mac_Accent.mint.opacity(0.10))
            )
            .overlay(
                Capsule().strokeBorder(Mac_Accent.mint.opacity(0.30), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("New Goal")
    }

    /// Single-step increment (mint "+ 1" pill, context menu, ⌘+). Routes through
    /// the shared `GoalMutator` — the view never mutates SwiftData directly.
    private func incrementGoal(_ goal: PersistedGoal) {
        GoalMutator.increment(goal)
        try? modelContext.save()
    }

    /// Arbitrary increment from the inline custom field. Adds `value` onto the
    /// current progress via `GoalMutator.setValue` (clamped to the target).
    private func incrementGoal(_ goal: PersistedGoal, by value: Double) {
        guard value > 0 else { return }
        GoalMutator.setValue(goal, to: goal.currentValue + value)
        try? modelContext.save()
    }

    /// Scroll the requested goal into view, flash its ring, then clear the nav
    /// token so the same target can be requested again later.
    private func reveal(_ id: UUID, proxy: ScrollViewProxy) {
        if reduceMotion { proxy.scrollTo(id, anchor: .center) }
        else { withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) } }
        flashID = id
        nav.pendingFocus = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard flashID == id else { return }
            if reduceMotion { flashID = nil }
            else { withAnimation(.easeInOut(duration: 0.2)) { flashID = nil } }
        }
    }
}

// MARK: - Mac_GoalCard
//
// Goal row matching the iOS GoalsViews anatomy: title + percent, a 3pt
// hairline-track progress bar with the goal's damped tint, and "current /
// target" meta below. The fill animates via `scaleEffect` (a transform, never a
// layout width) on increment. Reaching 100% blooms a soft mint radial behind the
// card and gives it a brief scale pulse. Wrapped in `ThemedCard` so Liquid Glass
// inherits its material + specular edge.

struct Mac_GoalCard: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let goal: PersistedGoal
    var onLogProgress: () -> Void
    /// Single-step "+ 1" increment.
    var onIncrement: () -> Void
    /// Arbitrary increment from the inline custom field.
    var onIncrementBy: (Double) -> Void
    var onEdit: () -> Void
    var onAbandon: () -> Void
    var onDelete: () -> Void
    /// Mint ring flash when navigated to via an @mention / backlink.
    var highlighted: Bool = false

    @State private var hovering = false
    @State private var bloom = false
    @State private var pulse = false
    /// Soft mint bloom pulsed on every increment (distinct from the 100% bloom).
    @State private var incBloom = false
    /// Inline custom-increment field reveal + its text.
    @State private var showingCustom = false
    @State private var customText = ""
    @FocusState private var customFieldFocused: Bool

    private var clampedProgress: CGFloat { max(0, min(1, CGFloat(goal.progress))) }

    var body: some View {
        let p = theme.palette
        ThemedCard(palette: p) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(goal.title)
                        .font(.system(size: 16, weight: .semibold, design: p.fontDesign))
                        .tracking(p.headlineTracking)
                        .foregroundStyle(p.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(goal.percentText)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .monospacedDigit()
                        .foregroundStyle(clampedProgress >= 1 ? Mac_Accent.mint : p.textPrimary)
                }

                // 3pt progress bar — full-width fill scaled on the x axis.
                ZStack(alignment: .leading) {
                    Capsule().fill(p.hairline)
                    Capsule()
                        .fill(goal.displayTint)
                        .scaleEffect(x: clampedProgress, anchor: .leading)
                }
                .frame(height: 3)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: clampedProgress)

                HStack(alignment: .center, spacing: 10) {
                    Text("\(goal.currentText) / \(goal.targetText)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .monospacedDigit()
                        .foregroundStyle(p.textTertiary)

                    Spacer(minLength: 0)

                    incrementControls(p)
                }

                if showingCustom {
                    customIncrementField(p)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? p.chromeSurface : Color.clear)
        }
        // Increment bloom — a soft mint radial pulsed behind the card on each +.
        .background {
            RoundedRectangle(cornerRadius: p.cardRadius, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [Mac_Accent.mint.opacity(incBloom ? 0.08 : 0), .clear],
                        center: .center, startRadius: 0, endRadius: 200
                    )
                )
                .blur(radius: 18)
                .padding(-10)
        }
        // Completion bloom — a soft mint radial behind the whole card.
        .background {
            RoundedRectangle(cornerRadius: p.cardRadius, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [Mac_Accent.mint.opacity(bloom ? 0.22 : 0), .clear],
                        center: .center, startRadius: 0, endRadius: 220
                    )
                )
                .blur(radius: 20)
                .padding(-10)
        }
        .overlay(
            RoundedRectangle(cornerRadius: p.cardRadius, style: .continuous)
                .strokeBorder(highlighted ? Mac_Accent.mint : Color.clear, lineWidth: 1.5)
        )
        .scaleEffect(pulse ? 1.02 : 1.0)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: hovering)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: highlighted)
        .onChange(of: clampedProgress) { old, new in
            if new >= 1 && old < 1 { celebrate() }
        }
        .contextMenu {
            Button("Log Progress") { onLogProgress() }
            Button("Edit…") { onEdit() }
            Divider()
            Button("Abandon") { onAbandon() }
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    // MARK: Increment controls

    /// The "···" custom toggle + the mint "+ 1" pill, right-aligned in the card.
    @ViewBuilder
    private func incrementControls(_ p: ThemePalette) -> some View {
        HStack(spacing: 8) {
            Button { toggleCustom() } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Mac_Accent.mint)
                    .frame(width: 28, height: 22)
                    .background(Capsule().fill(Mac_Accent.mint.opacity(0.10)))
                    .overlay(Capsule().strokeBorder(Mac_Accent.mint.opacity(0.30), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Custom increment")

            Button { performIncrement() } label: {
                Text("+ 1")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(Mac_Accent.mint)
                    .frame(width: 32, height: 22)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Mac_Accent.mint.opacity(0.10)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Mac_Accent.mint.opacity(0.30), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Add one")
        }
    }

    /// Inline numeric increment field, revealed beneath the controls row.
    @ViewBuilder
    private func customIncrementField(_ p: ThemePalette) -> some View {
        HStack(spacing: 8) {
            TextField("increment by", text: $customText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(p.textPrimary)
                .tint(Mac_Accent.mint)
                .focused($customFieldFocused)
                .onSubmit { confirmCustom() }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous).fill(p.rowFill))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous).strokeBorder(p.hairline))

            Button { confirmCustom() } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Mac_Accent.mint)
                    .frame(width: 28, height: 26)
                    .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous).fill(Mac_Accent.mint.opacity(0.10)))
                    .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous).strokeBorder(Mac_Accent.mint.opacity(0.30), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .onExitCommand { dismissCustom() }
        .transition(.opacity)
    }

    private func toggleCustom() {
        if reduceMotion { showingCustom.toggle() }
        else { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showingCustom.toggle() } }
        if showingCustom { customFieldFocused = true }
    }

    private func dismissCustom() {
        customText = ""
        if reduceMotion { showingCustom = false }
        else { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showingCustom = false } }
    }

    private func confirmCustom() {
        let trimmed = customText.trimmingCharacters(in: .whitespaces)
        if let value = Double(trimmed), value > 0 {
            onIncrementBy(value)
            pulseIncrementBloom()
        }
        dismissCustom()
    }

    private func performIncrement() {
        onIncrement()
        pulseIncrementBloom()
    }

    /// Soft mint bloom on each increment. No-op under reduce motion.
    private func pulseIncrementBloom() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { incBloom = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            withAnimation(.easeOut(duration: 0.4)) { incBloom = false }
        }
    }

    /// Bloom + scale pulse on reaching 100%. No-op under reduce motion.
    private func celebrate() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            bloom = true
            pulse = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { pulse = false }
            try? await Task.sleep(nanoseconds: 300_000_000)
            withAnimation(.easeOut(duration: 0.4)) { bloom = false }
        }
    }
}
