import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

// MARK: - TaskRow (Sophisticated Stark)
//
// Brutally minimalist. No pill chips, no material blurs, no glyph circles.
// Anatomy (top → bottom):
//   1. 2pt accent rail (left edge), tinted with the type accent
//   2. Uppercase tracked meta strip: TYPE · DATE · #TAG
//   3. Title row: optional checkbox + bound TextField + plain chevron
//   4. Optional details preview (collapsed) / full editor (expanded)
//
// Row fill is the page canvas so swipes reveal the backdrop cleanly.
// Hairline bottom border is painted by the page, not the row.

struct TaskRow: View {
    @Environment(ThemeStore.self) private var theme
    @Bindable var task: PersistedTask
    var isExpanded: Bool
    var onToggleExpanded: () -> Void
    var onDelete: () -> Void

    @FocusState private var isTitleFocused: Bool
    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        HStack(spacing: 0) {
            accentRail
            content
        }
        .background(theme.palette.rowFill)
        .contextMenu {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        // `.task` fires after the first render, which is when the field is
        // attachable — focusing a brand-new empty row without a timing hack.
        .task {
            if task.title.isEmpty { isTitleFocused = true }
        }
        // Inline deadline edits flow straight into SwiftData via @Bindable;
        // re-schedule the local notification whenever the value settles.
        .onChange(of: task.dueDate) { _, _ in
            NotificationManager.shared.schedule(for: task)
        }
        .onChange(of: task.isDone) { _, _ in
            NotificationManager.shared.schedule(for: task)
        }
        // Idea-interaction tracking. The decay engine reads `updatedAt`
        // to bucket stale ideas — bump it on every meaningful edit so a
        // user actively iterating on an idea never sees it drift into the
        // marinating section.
        .onChange(of: task.ideaStatus) { _, _ in TaskMutator.markInteracted(task) }
        .onChange(of: task.ideaTag) { _, _ in TaskMutator.markInteracted(task) }
        .onChange(of: task.title) { _, _ in TaskMutator.markInteracted(task) }
        .onChange(of: task.details) { _, _ in TaskMutator.markInteracted(task) }
    }

    // MARK: Accent rail
    //
    // Ideas that haven't been touched in 7 days lose their chromatic rail
    // and decay to a structural charcoal. This is the visual signal the
    // user reads to know the idea has gone stale and slipped into the
    // "Marinating" sub-section.

    private var accentRail: some View {
        Rectangle()
            .fill(railColor)
            .frame(width: isHighPriority ? 3 : 2)
            .frame(maxHeight: .infinity)
            .shadow(
                color: isHighPriority ? theme.palette.accent.opacity(0.75) : .clear,
                radius: isHighPriority ? 5 : 0
            )
    }

    private var railColor: Color {
        if LifecycleAutomation.isIdeaStale(task) {
            return theme.palette.textTertiary
        }
        if isHighPriority {
            return theme.palette.accent
        }
        return task.type.tint.opacity(0.85)
    }

    /// A live (non-stale) P1 task earns a glowing accent rail — the only
    /// chromatic-weight signal that elevates an item above the type tint.
    private var isHighPriority: Bool {
        !LifecycleAutomation.isIdeaStale(task) && task.priorityLevel == .p1
    }

    // MARK: Content

    private var content: some View {
        let p = theme.palette
        return VStack(alignment: .leading, spacing: 10) {
            metaStrip
            titleRow

            if !task.details.isEmpty && !isExpanded {
                Text(task.details)
                    .font(p.font(.body))
                    .foregroundStyle(p.textSecondary)
                    .lineSpacing(2)
                    .lineLimit(2)
            }

            if isExpanded {
                expandedBlock
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Meta strip — TYPE · DATE · #TAG
    //
    // Uppercase, micro-tracked, monospaced for digits. One line. Quiet.

    private var metaStrip: some View {
        HStack(spacing: 0) {
            metaToken(task.type.displayName)

            if let dateMeta = dateMetaText {
                separator
                metaToken(dateMeta, monospaced: true)
            }

            if task.type == .idea, let tag = task.ideaTag, !tag.isEmpty {
                separator
                metaToken("#\(tag)")
            }

            Spacer(minLength: 0)
        }
    }

    private func metaToken(_ text: String, monospaced: Bool = false) -> some View {
        let p = theme.palette
        return Text(text)
            .font(p.font(.micro))
            .tracking(p.microTracking)
            .textCase(.uppercase)
            .conditionalMonospaced(monospaced)
            .foregroundStyle(p.textSecondary)
            .lineLimit(1)
    }

    private var separator: some View {
        let p = theme.palette
        return Text("·")
            .font(p.font(.micro))
            .foregroundStyle(p.textTertiary)
            .padding(.horizontal, 8)
    }

    // MARK: Title row

    private var titleRow: some View {
        let p = theme.palette
        return HStack(alignment: .center, spacing: 12) {
            if task.type == .todo {
                checkbox
            }

            TextField("\(task.type.displayName.capitalized) title…", text: $task.title)
                .focused($isTitleFocused)
                .font(p.font(.headline))
                .tracking(p.headlineTracking)
                .foregroundStyle(p.textPrimary)
                .textInputAutocapitalization(.sentences)
                .strikethrough(task.type == .todo && (task.isDone ?? false), color: p.textTertiary)

            Spacer(minLength: 0)

            chevron
        }
    }

    private var checkbox: some View {
        let p = theme.palette
        return Button {
            let wasDone = task.isDone ?? false
            task.isDone = !wasDone
            wasDone ? AppHaptic.tap() : AppHaptic.success()
        } label: {
            Image(systemName: (task.isDone ?? false) ? "checkmark.square.fill" : "square")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle((task.isDone ?? false) ? p.textPrimary : p.textTertiary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
    }

    private var chevron: some View {
        let p = theme.palette
        return Button { onToggleExpanded() } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(p.textTertiary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Date meta string

    private var dateMetaText: String? {
        switch task.type {
        case .reminder, .todo:
            if let due = task.dueDate { return "Due \(TaskDateFormatter.friendlyDue(due))" }
            return (task.type == .todo && (task.isDone ?? false)) ? "Done" : nil
        case .idea:
            return task.ideaStatus?.displayName
        }
    }

    // MARK: Expanded block

    private var expandedBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch task.type {
            case .reminder, .todo: deadlineControls
            case .idea:            ideaExpandedControls
            }

            goalLinkControl

            detailsEditor
        }
        .padding(.top, 4)
    }

    // MARK: Goal link
    //
    // Loose foreign key into `PersistedGoal.id`. We use `@Query` on the
    // expanded row rather than passing goals in from the page so the picker
    // stays self-contained and SwiftData drives row reactivity for free.
    // CloudKit-safe: no `@Relationship` macro — we mutate `parentGoalID`
    // directly. Selecting "None" un-links the task.

    private var goalLinkControl: some View {
        GoalLinkPicker(parentGoalID: $task.parentGoalID)
    }

    // MARK: Inputs (flat, hairline)

    private func sectionLabel(_ text: String) -> some View {
        let p = theme.palette
        return Text(text)
            .font(p.font(.micro))
            .tracking(p.microTracking)
            .textCase(.uppercase)
            .foregroundStyle(p.textSecondary)
    }

    private var detailsEditor: some View {
        let p = theme.palette
        return VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Notes")

            ZStack(alignment: .topLeading) {
                if task.details.isEmpty {
                    Text(detailsPlaceholder)
                        .font(p.font(.body))
                        .foregroundStyle(p.textTertiary)
                        .padding(.top, 8)
                        .padding(.leading, 6)
                }
                TextEditor(text: $task.details)
                    .scrollContentBackground(.hidden)
                    .font(p.font(.body))
                    .foregroundStyle(p.textPrimary)
                    .frame(minHeight: 84)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .fill(p.chromeSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .strokeBorder(p.hairline, lineWidth: 0.5)
            )
        }
    }

    private var detailsPlaceholder: String {
        switch task.type {
        case .todo:     return "Notes, subtasks, context…"
        case .idea:     return "Expand on the idea…"
        case .reminder: return "Reminder details…"
        }
    }

    // Unified deadline editor for both `.reminder` and `.todo`.
    // Time component is meaningful for reminders (alert moment) and harmless
    // for todos (treated as end-of-deadline-day in display logic).
    private var deadlineControls: some View {
        let p = theme.palette
        return VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Deadline")
            HStack(spacing: 10) {
                pickerBox {
                    DatePicker("", selection: bindingPreservingTime(), displayedComponents: [.date])
                        .labelsHidden().datePickerStyle(.compact).tint(p.controlTint)
                }
                pickerBox {
                    DatePicker("", selection: bindingPreservingDate(), displayedComponents: [.hourAndMinute])
                        .labelsHidden().datePickerStyle(.compact).tint(p.controlTint)
                }
            }
        }
    }

    private var ideaExpandedControls: some View {
        let p = theme.palette
        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Status")
            HStack(spacing: 8) {
                ForEach(IdeaStatus.allCases) { s in
                    let selected = ((task.ideaStatus ?? .thinking) == s)
                    Button {
                        withAnimation(DesignTokens.Motion.snappy) { task.ideaStatus = s }
                        AppHaptic.tap()
                    } label: {
                        Text(s.shortLabel)
                            .font(p.font(.micro))
                            .tracking(p.microTracking)
                            .textCase(.uppercase)
                            .foregroundStyle(selected ? p.textPrimary : p.textTertiary)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                                    .fill(selected ? p.chromeSurface : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                                    .strokeBorder(
                                        selected ? p.prominent : p.hairline,
                                        lineWidth: 0.5
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            sectionLabel("Tag")
            TextField("e.g. UI, ML, App…", text: Binding(
                get: { task.ideaTag ?? "" },
                set: { task.ideaTag = String($0.prefix(10)).isEmpty ? nil : String($0.prefix(10)) }
            ))
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .foregroundStyle(p.textPrimary)
            .font(p.font(.body))
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .fill(p.chromeSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .strokeBorder(p.hairline, lineWidth: 0.5)
            )
        }
    }

    private func pickerBox<P: View>(@ViewBuilder picker: () -> P) -> some View {
        let p = theme.palette
        return picker()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .fill(p.chromeSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .strokeBorder(p.hairline, lineWidth: 0.5)
            )
    }

    // MARK: Date bindings (preserve time when editing date, and vice versa)

    private func bindingPreservingTime() -> Binding<Date> {
        Binding(
            get: { task.dueDate ?? .now },
            set: { newValue in
                let old = task.dueDate ?? .now
                let time = calendar.dateComponents([.hour, .minute], from: old)
                let date = calendar.dateComponents([.year, .month, .day], from: newValue)
                task.dueDate = calendar.date(from: DateComponents(
                    year: date.year, month: date.month, day: date.day,
                    hour: time.hour, minute: time.minute
                )) ?? newValue
            }
        )
    }

    private func bindingPreservingDate() -> Binding<Date> {
        Binding(
            get: { task.dueDate ?? .now },
            set: { newValue in
                let old = task.dueDate ?? .now
                let date = calendar.dateComponents([.year, .month, .day], from: old)
                let time = calendar.dateComponents([.hour, .minute], from: newValue)
                task.dueDate = calendar.date(from: DateComponents(
                    year: date.year, month: date.month, day: date.day,
                    hour: time.hour, minute: time.minute
                )) ?? newValue
            }
        )
    }
}

// MARK: - NewItemSheet
//
// Preserved from Phase 1 — sheet chrome will get its own pass later.
// Logic (draft assembly, type switching, validation) is unchanged.

struct NewItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeStore.self) private var theme

    @State private var type: TaskType
    @State private var title: String = ""
    @State private var details: String = ""

    @State private var isDone: Bool = false
    @State private var hasDeadline: Bool = false
    @State private var dueDate: Date = .now

    @State private var ideaStatus: IdeaStatus = .thinking
    @State private var ideaTag: String = ""

    /// Optional goal linkage selected at capture time. Threaded into the
    /// draft on `makeDraft()`; `nil` means the task isn't linked.
    @State private var linkedGoalID: UUID? = nil

    let onCreate: (NewTaskDraft) -> Void

    init(initialType: TaskType, onCreate: @escaping (NewTaskDraft) -> Void) {
        _type = State(initialValue: initialType)
        self.onCreate = onCreate
    }

    private var titleValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        let p = theme.palette
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignTokens.Spacing.stackLarge) {
                    typePickerCard
                    editorCard
                    goalLinkCard
                }
                .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
                .padding(.top, DesignTokens.Spacing.pageTop)
                .padding(.bottom, DesignTokens.Spacing.pageBottom)
            }
            .scrollIndicators(.hidden)
            .livingCanvas(p)
            .navigationTitle("New \(type.displayName.capitalized)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(p.textSecondary)
                }
            }
            .toolbarColorScheme(p.colorScheme, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { ctaBar }
        }
        .preferredColorScheme(p.colorScheme)
        .tint(p.controlTint)
    }

    private var ctaBar: some View {
        let p = theme.palette
        return VStack(spacing: 0) {
            Rectangle().fill(p.hairline).frame(height: 0.5)
            PrimaryActionButton(title: "Create \(type.displayName)", enabled: titleValid, palette: p) {
                onCreate(makeDraft())
                AppHaptic.success()
                dismiss()
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

    private var typePickerCard: some View {
        let p = theme.palette
        return ThemedCard(palette: p) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Type", palette: p)
                HStack(spacing: 8) {
                    ForEach(TaskType.allCases) { t in
                        KineticPill(title: t.displayName, isSelected: type == t, palette: p) {
                            withAnimation(DesignTokens.Motion.snappy) { type = t }
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.cardInset)
        }
    }

    private var editorCard: some View {
        let p = theme.palette
        return ThemedCard(palette: p) {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("Details", palette: p)
                SheetTextField(placeholder: "Title", text: $title, palette: p)
                SheetTextField(placeholder: "Notes (optional)", text: $details, palette: p,
                               axis: .vertical, lineLimit: 3...6)

                switch type {
                case .todo:     todoControls
                case .reminder: reminderControls
                case .idea:     ideaControls
                }
            }
            .padding(DesignTokens.Spacing.cardInset)
        }
    }

    // Todos and reminders share the same deadline drawer. The only
    // distinction surfaced here is the "Mark done" toggle on a todo.
    private var todoControls: some View {
        let p = theme.palette
        return VStack(alignment: .leading, spacing: 12) {
            InlineDateDrawer(title: "Due Date", isEnabled: $hasDeadline, date: $dueDate, palette: p)
            Toggle(isOn: $isDone) {
                Text("Mark done").foregroundStyle(p.textSecondary).font(p.font(.body))
            }
            .tint(p.controlTint)
        }
    }

    private var reminderControls: some View {
        InlineDateDrawer(title: "Remind Me", isEnabled: $hasDeadline, date: $dueDate, palette: theme.palette)
    }

    private var ideaControls: some View {
        let p = theme.palette
        return VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Status", palette: p)
            HStack(spacing: 8) {
                ForEach(IdeaStatus.allCases) { s in
                    KineticPill(title: s.shortLabel, isSelected: ideaStatus == s, palette: p) {
                        withAnimation(DesignTokens.Motion.snappy) { ideaStatus = s }
                    }
                }
            }

            SectionLabel("Tag", palette: p)
            SheetTextField(placeholder: "e.g. App, UI, Research…", text: $ideaTag,
                           palette: p, autocapitalization: .characters)
                .autocorrectionDisabled()
                .onChange(of: ideaTag) { _, newValue in
                    let capped = String(newValue.prefix(10))
                    if capped != newValue { ideaTag = capped }
                }
        }
    }

    private func makeDraft() -> NewTaskDraft {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var draft = NewTaskDraft(title: trimmedTitle, details: details, type: type)

        switch type {
        case .todo:
            draft.isDone = isDone
            if hasDeadline { draft.dueDate = dueDate }
        case .reminder:
            if hasDeadline { draft.dueDate = dueDate }
        case .idea:
            draft.ideaStatus = ideaStatus
            let tag = ideaTag.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.ideaTag = tag.isEmpty ? nil : tag
        }
        draft.parentGoalID = linkedGoalID
        return draft
    }

    // MARK: Goal-link card
    //
    // Standalone card under the editor so it's discoverable without crowding
    // the type-specific controls. Renders `GoalLinkPicker` inside a themed
    // card to stay seamless across all four palettes.

    private var goalLinkCard: some View {
        let p = theme.palette
        return ThemedCard(palette: p) {
            GoalLinkPicker(parentGoalID: $linkedGoalID)
                .padding(DesignTokens.Spacing.cardInset)
        }
    }
}

// MARK: - GoalLinkPicker
//
// Self-contained SwiftData-driven Picker for linking a task to a goal.
// Used by both `NewItemSheet` (capture-time linkage) and `TaskRow`
// (edit-time re-linkage / unlinkage). Source of truth is the binding the
// caller hands us — we never write into the SwiftData context directly.
//
// "None" is always the first option and represents `nil`. Abandoned goals
// are filtered out via `goal.status`. The picker label and `goal.icon +
// goal.title` rows pull tokens from `ThemeStore`, so the picker stays
// visually consistent across Stark Dark, Stark Light, Calm Earth, and
// Liquid Glass.

struct GoalLinkPicker: View {
    @Environment(ThemeStore.self) private var theme
    @Query(sort: \PersistedGoal.sortOrder) private var goals: [PersistedGoal]

    @Binding var parentGoalID: UUID?

    var body: some View {
        let p = theme.palette
        let active = goals.filter { $0.status == .active }

        return VStack(alignment: .leading, spacing: 8) {
            Text("Link to Goal")
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .textCase(.uppercase)
                .foregroundStyle(p.textSecondary)

            Picker(selection: $parentGoalID) {
                Text("None")
                    .foregroundStyle(p.textPrimary)
                    .tag(UUID?.none)

                ForEach(active) { goal in
                    Label {
                        Text(goal.title)
                    } icon: {
                        Image(systemName: goal.icon)
                    }
                    .tag(Optional(goal.id))
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.menu)
            .tint(p.controlTint)
            .labelsHidden()
            .font(p.font(.body))
            .foregroundStyle(p.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
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
    }
}
