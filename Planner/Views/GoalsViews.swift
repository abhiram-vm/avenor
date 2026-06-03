import SwiftUI
import SwiftData

// MARK: - GoalRowCell (Sophisticated Stark)
//
// Linear-style anatomy: accent rail, uppercase tracked meta with percent,
// title, optional subtitle, hairline progress bar (no system ProgressView).
// Tap opens the update sheet. No tinted circles, no colored percent chip.

struct GoalRowCell: View {
    @Environment(ThemeStore.self) private var theme
    let goal: PersistedGoal
    let onTap: () -> Void

    // MARK: Scrub-wheel state
    //
    // Long-press → vertical drag morphs the meta strip into a scrub
    // target. `scrubAnchor` is the goal value at gesture entry, so the
    // vertical drag translation maps to an absolute new value rather than
    // a relative delta — pulling back through zero returns to the anchor.
    @State private var isScrubbing: Bool = false
    @State private var scrubAnchor: Double = 0
    @State private var scrubLastQuantizedSteps: Int = 0

    /// Points-of-vertical-drag per single integer step. Slightly more than
    /// a touch-target so the user can't accidentally trip 5 units with a
    /// twitch but a deliberate flick crosses 8–10 in one motion.
    private let scrubPointsPerStep: CGFloat = 18

    var body: some View {
        let p = theme.palette
        HStack(spacing: 0) {
            Rectangle()
                .fill(goal.tint.opacity(0.85))
                .frame(width: 2)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                metaStrip
                Text(goal.title)
                    .font(p.font(.headline))
                    .tracking(p.headlineTracking)
                    .foregroundStyle(p.textPrimary)
                    .lineLimit(1)

                if !goal.subtitle.isEmpty {
                    Text(goal.subtitle)
                        .font(p.font(.body))
                        .foregroundStyle(p.textSecondary)
                        .lineSpacing(2)
                        .lineLimit(2)
                }

                progressBar

                if let note = goal.lastUpdateNote, !note.isEmpty, !isScrubbing {
                    Text(note)
                        .font(p.font(.caption))
                        .foregroundStyle(p.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(p.rowFill)
        .contentShape(Rectangle())
        // Tap routes to the update sheet. The scrub gesture below uses a
        // long-press primer, so a flat tap never accidentally trips it.
        .onTapGesture { onTap() }
        // `simultaneousGesture` so the outer `GoalIncrementSwipeRow` drag
        // and this scrub gesture coexist. Horizontal motion >8pt cancels
        // the LongPressGesture (via its maxDistance), surrendering the
        // touch to the swipe row; a still hold for 0.3s claims it here.
        .simultaneousGesture(scrubGesture)
        .animation(DesignTokens.Motion.smooth, value: goal.currentValue)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isScrubbing)
    }

    // MARK: Meta strip (morphs into scrub indicator on hold)

    @ViewBuilder
    private var metaStrip: some View {
        let p = theme.palette
        if isScrubbing {
            scrubIndicator
        } else {
            HStack(spacing: 0) {
                Text("Goal")
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(p.textSecondary)

                Text("·")
                    .font(p.font(.micro))
                    .foregroundStyle(p.textTertiary)
                    .padding(.horizontal, 8)

                Text("\(goal.currentText) / \(goal.targetText)")
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .textCase(.uppercase)
                    .monospacedDigit()
                    .foregroundStyle(p.textSecondary)

                Spacer(minLength: 0)

                Text(goal.percentText)
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .textCase(.uppercase)
                    .monospacedDigit()
                    .foregroundStyle(p.textPrimary)
            }
        }
    }

    /// Live scrub display. The current value pops to 22pt monospaced so
    /// the user can see what they're aiming at, paired with up/down chevrons
    /// signalling axis. White at full opacity — this is the moment of edit.
    private var scrubIndicator: some View {
        let p = theme.palette
        return HStack(spacing: 10) {
            Image(systemName: "chevron.up")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(p.textSecondary)

            Text(goal.currentText)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .tracking(-0.4)
                .monospacedDigit()
                .foregroundStyle(p.textPrimary)

            Text("/ \(goal.targetText)")
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .textCase(.uppercase)
                .monospacedDigit()
                .foregroundStyle(p.textTertiary)

            Spacer(minLength: 0)

            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(p.textSecondary)
        }
    }

    private var progressBar: some View {
        let p = theme.palette
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(p.hairline)
                Rectangle()
                    .fill(goal.tint.opacity(isScrubbing ? 1.0 : 0.85))
                    .frame(width: max(0, min(1, goal.progress)) * geo.size.width)
            }
        }
        .frame(height: isScrubbing ? 3 : 2)
    }

    // MARK: Scrub gesture
    //
    // Composition: LongPressGesture(0.3s, max 8pt jitter) sequenced before a
    // zero-distance DragGesture. The long-press primes the gesture and only
    // then does vertical translation map to value mutations. Without the
    // primer a casual scroll would trip the scrubber.

    private var scrubGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3, maximumDistance: 8)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { state in
                switch state {
                case .first:
                    break
                case .second(true, let drag):
                    if !isScrubbing {
                        // Just entered scrub mode — anchor the current value
                        // and pop a rigid haptic so the user feels the
                        // mode switch.
                        isScrubbing = true
                        scrubAnchor = goal.currentValue
                        scrubLastQuantizedSteps = 0
                        AppHaptic.rigid()
                    }
                    if let drag {
                        applyScrub(verticalTranslation: drag.translation.height)
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                if isScrubbing {
                    isScrubbing = false
                    scrubLastQuantizedSteps = 0
                    AppHaptic.tap()
                }
            }
    }

    private func applyScrub(verticalTranslation dy: CGFloat) {
        // Drag up = increase, drag down = decrease. SwiftUI's coordinate
        // space is y-down, so we negate.
        let raw = Double(-dy / scrubPointsPerStep)
        let quantized = Int(raw.rounded())

        // Per-integer haptic tick. Only fires on the *crossing* itself,
        // not on every gesture event at the same step.
        if quantized != scrubLastQuantizedSteps {
            scrubLastQuantizedSteps = quantized
            AppHaptic.tap()
        }

        let step = GoalMutator.step(for: goal)
        let target = scrubAnchor + Double(quantized) * step
        GoalMutator.setValue(goal, to: target)
    }
}

// MARK: - Add Goal Sheet (preserved — sheet pass pending)

struct AddGoalSheet: View {
    @Binding var draft: NewGoalDraft
    var onAdd: (NewGoalDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeStore.self) private var theme

    private let colorChoices: [Color] = [.blue, .indigo, .purple, .pink, .red, .orange, .yellow, .green, .teal]

    enum UnitMode: String, CaseIterable, Identifiable {
        case preset, custom
        var id: String { rawValue }
        var label: String { self == .preset ? "Preset" : "Custom" }
    }

    @State private var unitMode: UnitMode = .preset
    @State private var selectedOptionID: String = "pages"

    // Value fields are String-backed so the smart default can render as a
    // soft placeholder (not a committed value). Empty → fall back to the
    // selected option's `defaultTarget` (target) or 0 (current) on create.
    @State private var targetText: String = ""
    @State private var currentText: String = ""

    @State private var customLabel: String = "pages"
    @State private var customSymbol: String = ""
    @State private var customAllowsDecimals: Bool = false
    @State private var customPrefix: Bool = false

    // MARK: Derived

    private var selectedOption: UnitOption {
        UnitCategory.option(id: selectedOptionID) ?? UnitCategory.focus.options[0]
    }

    private var currentUnit: GoalUnit {
        switch unitMode {
        case .preset:
            return selectedOption.goalUnit
        case .custom:
            let label = customLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            return .custom(
                label: label.isEmpty ? "unit" : label,
                symbol: customSymbol,
                allowsDecimals: customAllowsDecimals,
                isPrefixSymbol: customPrefix
            )
        }
    }

    private var targetPlaceholder: String {
        unitMode == .preset ? formatValue(selectedOption.defaultTarget) : "10"
    }

    private var titleValid: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        let p = theme.palette
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignTokens.Spacing.stackLarge) {
                    detailsCard
                    unitCard
                    valuesCard
                    colorCard
                    iconCard
                }
                .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
                .padding(.top, DesignTokens.Spacing.pageTop)
                .padding(.bottom, DesignTokens.Spacing.pageBottom)
            }
            .scrollIndicators(.hidden)
            .livingCanvas(p)
            .navigationTitle("New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(p.textSecondary)
                }
            }
            .toolbarColorScheme(p.colorScheme, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { ctaBar }
        }
        .preferredColorScheme(p.colorScheme)
        .tint(p.controlTint)
        .onAppear { draft.unit = currentUnit }
    }

    // MARK: CTA

    private var ctaBar: some View {
        let p = theme.palette
        return VStack(spacing: 0) {
            Rectangle().fill(p.hairline).frame(height: 0.5)
            PrimaryActionButton(title: "Create Goal", enabled: titleValid, palette: p) {
                commit()
            }
            .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(ctaBackground)
    }

    @ViewBuilder
    private var ctaBackground: some View {
        let p = theme.palette
        if p.id == .liquidGlass {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
        } else {
            p.sheetBackground.ignoresSafeArea()
        }
    }

    // MARK: Cards

    private var detailsCard: some View {
        let p = theme.palette
        return ThemedCard(palette: p) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Goal Details", palette: p)
                SheetTextField(placeholder: "Title", text: $draft.title, palette: p)
                SheetTextField(placeholder: "Subtitle (optional)", text: $draft.subtitle, palette: p)
            }
            .padding(DesignTokens.Spacing.cardInset)
        }
    }

    private var unitCard: some View {
        let p = theme.palette
        return ThemedCard(palette: p) {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("Measure In", palette: p)

                HStack(spacing: 8) {
                    ForEach(UnitMode.allCases) { mode in
                        KineticPill(title: mode.label, isSelected: unitMode == mode, palette: p) {
                            withAnimation(DesignTokens.Motion.snappy) { unitMode = mode }
                            draft.unit = currentUnit
                        }
                    }
                }

                if unitMode == .preset { presetCatalog } else { customUnitControls }
            }
            .padding(DesignTokens.Spacing.cardInset)
        }
    }

    private var presetCatalog: some View {
        let p = theme.palette
        return VStack(alignment: .leading, spacing: 16) {
            ForEach(UnitCategory.allCases) { category in
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(category.rawValue, palette: p)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(category.options) { option in
                                KineticPill(
                                    title: option.title,
                                    isSelected: selectedOptionID == option.id,
                                    palette: p,
                                    fillWidth: false
                                ) {
                                    withAnimation(DesignTokens.Motion.snappy) {
                                        selectedOptionID = option.id
                                    }
                                    draft.unit = option.goalUnit
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var customUnitControls: some View {
        let p = theme.palette
        return VStack(alignment: .leading, spacing: 10) {
            SheetTextField(placeholder: "Unit label (e.g. pages, sessions)", text: $customLabel, palette: p)
            SheetTextField(placeholder: "Symbol (optional, e.g. $, km)", text: $customSymbol,
                           palette: p, autocapitalization: .never)
                .autocorrectionDisabled()

            Toggle(isOn: $customAllowsDecimals) {
                Text("Allow decimals").foregroundStyle(p.textSecondary).font(p.font(.body))
            }.tint(p.controlTint)

            Toggle(isOn: $customPrefix) {
                Text("Symbol before number").foregroundStyle(p.textSecondary).font(p.font(.body))
            }
            .tint(p.controlTint)
            .onChange(of: customLabel) { _, _ in draft.unit = currentUnit }
            .onChange(of: customSymbol) { _, _ in draft.unit = currentUnit }
            .onChange(of: customAllowsDecimals) { _, _ in draft.unit = currentUnit }
            .onChange(of: customPrefix) { _, _ in draft.unit = currentUnit }
        }
    }

    private var valuesCard: some View {
        let p = theme.palette
        return ThemedCard(palette: p) {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("Target Goal", palette: p)
                HStack(spacing: 10) {
                    SheetTextField(placeholder: targetPlaceholder, text: $targetText, palette: p,
                                   keyboard: currentUnit.allowsDecimals ? .decimalPad : .numberPad,
                                   monospaced: true)
                    unitChip
                }

                SectionLabel("Starting Value", palette: p)
                HStack(spacing: 10) {
                    SheetTextField(placeholder: "0", text: $currentText, palette: p,
                                   keyboard: currentUnit.allowsDecimals ? .decimalPad : .numberPad,
                                   monospaced: true)
                    unitChip
                }
            }
            .padding(DesignTokens.Spacing.cardInset)
        }
    }

    private var unitChip: some View {
        let p = theme.palette
        return Text(currentUnit.symbol)
            .font(p.font(.body).weight(.semibold))
            .foregroundStyle(p.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .inputSurface(p)
    }

    private var colorCard: some View {
        let p = theme.palette
        return ThemedCard(palette: p) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Accent Color", palette: p)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(colorChoices, id: \.self) { color in
                            Circle()
                                .fill(color)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle().strokeBorder(
                                        p.textPrimary.opacity(draft.tint == color ? 0.9 : 0),
                                        lineWidth: 2
                                    )
                                )
                                .onTapGesture {
                                    AppHaptic.tap()
                                    draft.tint = color
                                }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding(DesignTokens.Spacing.cardInset)
        }
    }

    private var iconCard: some View {
        let p = theme.palette
        return ThemedCard(palette: p) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Icon", palette: p)

                let icons = [
                    "target", "book.fill", "figure.run", "banknote.fill", "swift", "graduationcap.fill",
                    "dumbbell.fill", "heart.fill", "leaf.fill", "sun.max.fill", "moon.stars.fill", "paintpalette.fill",
                    "pencil.and.outline", "briefcase.fill", "clock.fill", "calendar", "cart.fill", "globe.americas.fill"
                ]

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                    ForEach(icons, id: \.self) { name in
                        iconButton(name: name)
                    }
                }
                .padding(.top, 4)
            }
            .padding(DesignTokens.Spacing.cardInset)
        }
    }

    private func iconButton(name: String) -> some View {
        let p = theme.palette
        let isSelected = draft.icon == name
        return Button {
            AppHaptic.tap()
            draft.icon = name
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                    .fill(isSelected ? p.chromeSurface : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                            .strokeBorder(
                                isSelected ? p.prominent : p.hairline,
                                lineWidth: isSelected ? 1 : 0.5
                            )
                    )
                Image(systemName: name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? p.textPrimary : p.textSecondary)
                    .padding(10)
            }
            .frame(height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(name))
    }

    // MARK: Commit

    private func commit() {
        let trimmed = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draft.title = trimmed
        draft.unit = currentUnit
        draft.targetValue = parseValue(targetText)
            ?? (unitMode == .preset ? selectedOption.defaultTarget : 10)
        draft.currentValue = parseValue(currentText) ?? 0
        onAdd(draft)
        AppHaptic.success()
        dismiss()
    }

    /// Bulletproof string → Double. Strips any unit symbols, currency
    /// glyphs, or stray spaces the user may have typed, normalizes the
    /// decimal separator, and only then attempts the cast. Returns nil when
    /// nothing numeric remains so the caller can fall back to a default.
    private func parseValue(_ s: String) -> Double? {
        let normalized = s.replacingOccurrences(of: ",", with: ".")
        let filtered = normalized.filter { $0.isNumber || $0 == "." || $0 == "-" }
        guard !filtered.isEmpty else { return nil }
        return Double(filtered)
    }

    private func formatValue(_ v: Double) -> String {
        v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v)
    }
}

// MARK: - Update Goal Sheet

struct UpdateGoalSheet: View {
    @Bindable var goal: PersistedGoal
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeStore.self) private var theme

    @State private var setCurrentText: String = ""
    @State private var note: String = ""

    var body: some View {
        let p = theme.palette
        NavigationStack {
            ZStack {
                canvasLayer(p)

                ScrollView {
                    VStack(spacing: DesignTokens.Spacing.stack) {
                        headerCard
                        setCurrentCard
                        linkedTasksCard
                    }
                    .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
                    .padding(.top, DesignTokens.Spacing.pageTop)
                    .padding(.bottom, DesignTokens.Spacing.pageBottom)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Update Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(p.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        applySetCurrentIfValid()
                        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        goal.lastUpdateNote = trimmed.isEmpty ? nil : trimmed
                        goal.lastUpdatedAt = .now
                        dismiss()
                    }
                    .font(p.font(.body).weight(.semibold))
                    .foregroundStyle(p.textPrimary)
                }
            }
            .toolbarColorScheme(p.colorScheme, for: .navigationBar)
            .onAppear {
                setCurrentText = normalizedText(goal.currentValue, allowsDecimals: goal.unit.allowsDecimals)
                note = goal.lastUpdateNote ?? ""
            }
        }
        .presentationBackground(p.sheetBackground)
        .preferredColorScheme(p.colorScheme)
        .tint(p.controlTint)
    }

    @ViewBuilder
    private func canvasLayer(_ p: ThemePalette) -> some View {
        switch p.canvas {
        case .solid(let c):
            c.ignoresSafeArea()
        case .gradient(let stops, let start, let end):
            LinearGradient(stops: stops, startPoint: start, endPoint: end)
                .ignoresSafeArea()
        }
    }

    private var headerCard: some View {
        let p = theme.palette
        return ThemedCard(palette: p) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 0) {
                    Text("Goal")
                        .font(p.font(.micro))
                        .tracking(p.microTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(p.textSecondary)
                    Text("·")
                        .font(p.font(.micro))
                        .foregroundStyle(p.textTertiary)
                        .padding(.horizontal, 8)
                    Text(goal.percentText)
                        .font(p.font(.micro))
                        .tracking(p.microTracking)
                        .textCase(.uppercase)
                        .monospacedDigit()
                        .foregroundStyle(p.textPrimary)
                    Spacer()
                }

                Text(goal.title)
                    .font(p.font(.title))
                    .tracking(p.headlineTracking)
                    .foregroundStyle(p.textPrimary)

                if !goal.subtitle.isEmpty {
                    Text(goal.subtitle)
                        .font(p.font(.body))
                        .foregroundStyle(p.textSecondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(p.hairline)
                        Rectangle()
                            .fill(goal.tint.opacity(0.85))
                            .frame(width: max(0, min(1, goal.progress)) * geo.size.width)
                    }
                }
                .frame(height: 2)

                Text("\(goal.currentText) / \(goal.targetText)")
                    .font(p.font(.caption))
                    .monospacedDigit()
                    .foregroundStyle(p.textSecondary)
            }
            .padding(DesignTokens.Spacing.cardInset)
        }
    }

    private var setCurrentCard: some View {
        let p = theme.palette
        return ThemedCard(palette: p) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Set current")
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(p.textSecondary)

                HStack(spacing: 10) {
                    TextField("0", text: $setCurrentText)
                        .keyboardType(goal.unit.allowsDecimals ? .decimalPad : .numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(p.textPrimary)
                        .font(p.font(.body))
                        .monospacedDigit()
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                                .fill(p.chromeSurface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                                .strokeBorder(p.hairline, lineWidth: 0.5)
                        )

                    Text(goal.unit.symbol)
                        .font(p.font(.body).weight(.semibold))
                        .foregroundStyle(p.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                                .fill(p.chromeSurface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                                .strokeBorder(p.hairline, lineWidth: 0.5)
                        )
                }

                TextField("Update note (optional)", text: $note)
                    .foregroundStyle(p.textPrimary)
                    .font(p.font(.body))
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                            .fill(p.chromeSurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                            .strokeBorder(p.hairline, lineWidth: 0.5)
                    )
            }
            .padding(DesignTokens.Spacing.cardInset)
        }
    }

    // MARK: Linked tasks
    //
    // Delegated to `LinkedTasksCard` (below) so SwiftData's `@Query` can
    // drive reactivity. A computed property here would not observe task
    // mutations triggered from the row's own checkbox.

    @ViewBuilder
    private var linkedTasksCard: some View {
        LinkedTasksCard(goalID: goal.id)
    }

    private func applySetCurrentIfValid() {
        let cleaned = setCurrentText.replacingOccurrences(of: ",", with: ".")
        guard let v = Double(cleaned) else { return }
        goal.currentValue = max(0, v)
    }

    private func normalizedText(_ v: Double, allowsDecimals: Bool) -> String {
        if allowsDecimals {
            if v.rounded() == v { return String(Int(v)) }
            return String(format: "%.1f", v)
        } else {
            return String(Int(v.rounded()))
        }
    }
}

// MARK: - LinkedTasksCard
//
// Reactive list of tasks loosely linked to a goal via `parentGoalID`.
// We use `@Query` (rather than reading `goal.associatedTasks` as a
// computed property) so that toggling a task's checkbox inside this
// card triggers a re-render — SwiftData observes the filtered fetch
// and pushes updates whenever any matching task mutates.
//
// CloudKit-safe: no `@Relationship`, just a `#Predicate` over the
// scalar `parentGoalID` column. Empty result → card hidden entirely.

private struct LinkedTasksCard: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.modelContext) private var modelContext
    @Query private var linkedTasks: [PersistedTask]

    init(goalID: UUID) {
        _linkedTasks = Query(
            filter: #Predicate<PersistedTask> { $0.parentGoalID == goalID },
            sort: [SortDescriptor(\.sortOrder)]
        )
    }

    var body: some View {
        let p = theme.palette
        if !linkedTasks.isEmpty {
            ThemedCard(palette: p) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Linked Tasks")
                        .font(p.font(.micro))
                        .tracking(p.microTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(p.textSecondary)

                    VStack(spacing: 0) {
                        ForEach(Array(linkedTasks.enumerated()), id: \.element.id) { idx, task in
                            row(task)
                            if idx < linkedTasks.count - 1 {
                                Rectangle()
                                    .fill(p.hairline)
                                    .frame(height: 0.5)
                            }
                        }
                    }
                }
                .padding(DesignTokens.Spacing.cardInset)
            }
        }
    }

    @ViewBuilder
    private func row(_ task: PersistedTask) -> some View {
        let p = theme.palette
        let done = task.isDone ?? false
        HStack(spacing: 12) {
            Button {
                AppHaptic.tap()
                if done {
                    TaskMutator.uncomplete(task, in: modelContext, with: DesignTokens.Motion.snappy)
                } else {
                    TaskMutator.complete(task, in: modelContext, with: DesignTokens.Motion.snappy)
                }
            } label: {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(done ? p.controlTint : p.textTertiary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title.isEmpty ? "Untitled" : task.title)
                    .font(p.font(.body))
                    .foregroundStyle(done ? p.textTertiary : p.textPrimary)
                    .strikethrough(done, color: p.textTertiary)
                    .lineLimit(2)

                if let due = task.dueDate {
                    Text(dueText(due))
                        .font(p.font(.micro))
                        .tracking(p.microTracking)
                        .textCase(.uppercase)
                        .monospacedDigit()
                        .foregroundStyle(p.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func dueText(_ date: Date) -> String {
        let cal = Calendar.autoupdatingCurrent
        let f = DateFormatter()
        if cal.isDateInToday(date) {
            f.dateFormat = "'TODAY' · h:mma"
        } else if cal.isDateInTomorrow(date) {
            f.dateFormat = "'TOMORROW' · h:mma"
        } else {
            f.dateFormat = "MMM d · h:mma"
        }
        return f.string(from: date).uppercased()
    }
}
