# Avenor — Architectural Source of Truth

## 1. High-Level Core Intent & Architecture

**Purpose.** Avenor is a single-user iOS life-organizer that unifies five mental modes — *capture, action, reflection, measurement, and lookup* — behind one "Sophisticated Stark" aesthetic. The app is shipping on the App Store under the bundle identifier `com.avenor.planner` (internal target name remains `Planner`). The user interacts with one of four palettes (Dark / Light / Calm Earth / Liquid Glass) and a five-tab navigation surface; everything else is local-first state.

**Architectural pillars.**

- **SwiftData** (`@Model` classes `PersistedTask`, `PersistedNote`, `PersistedGoal`) for primary persistence, configured for CloudKit compatibility (no `@Attribute(.unique)`, all non-optional fields have defaults, no relationships yet).
- **`@Observable` state** (`ThemeStore` only). All other domain state lives in SwiftData and is read live via `@Query`.
- **Service layer (pure enums / actors).** `TaskMutator`, `GoalMutator`, `NotificationManager`, `WidgetSnapshotPublisher`, `ConflictResolver`, `LifecycleAutomation`, `MigrationService`, `CaptureParser`, `TaskCalendarService`, `MarkdownRenderer`. Views call these instead of mutating SwiftData directly, which keeps side-effects (notifications, widget reloads, completion timestamps) in lockstep.
- **App Group sharing.** `group.com.avenor.planner` carries (a) the active theme raw value under `theme.selected.v2` and (b) two Codable snapshot payloads (`widget.todayPayload.v1`, `widget.goalsPayload.v1`) consumed by the widget extension.
- **WidgetKit extension** (`AvenorWidget` target). Self-contained — does not import the main app's design system. Reads theme + snapshots from the App Group every timeline refresh.
- **Custom interaction primitives.** `StarkSwipeRow` (hand-built axis-locked rubber-band swipe with threshold haptics) and `GoalIncrementSwipeRow` (Apple-Music style +1 increment) replace SwiftUI's native `.swipeActions`.
- **Lifecycle hooks** (`PlannerApp.swift`): `ConflictResolver.reconcile` + `LifecycleAutomation.runDailyMaintenance` run on first render and again on every `.active` scene phase. `NotificationManager.requestAuthorization()` fires once at launch.

---

## 2. Global State & Data Models

### SwiftData models (`Planner/Models/PersistentModels.swift`)

**`PersistedTask`** — unified actionable item.
- Identity: `id: UUID`, `sortOrder: Int` (negative epoch-millis → newest-first under ascending sort), `createdAt`, `updatedAt`.
- Content: `title`, `details`, `typeRaw` (backed by `TaskType` enum: `.todo | .idea | .reminder`).
- State: `isDone?`, `completedAt?` (set when `isDone` flips true), `dueDate?` (unified deadline for both `todo` and `reminder`), legacy `startDate?` / `endDate?` (decode-only), `ideaStatusRaw?` (`IdeaStatus.thinking | inProgress | completed`), `ideaTag?`.
- Relationships: `parentGoalID: UUID?` (loose foreign key to `PersistedGoal.id`, CloudKit-safe).

**`PersistedNote`** — free-form text.
- `id`, `sortOrder`, `createdAt`, `updatedAt`, `lastEditedAt?` (drives Overview "RECENT BRAIN DUMPS" ordering).
- `title`, `details` (raw markdown — rendered via `MarkdownRenderer` only at read state).
- Derived: `wordCount`.

**`PersistedGoal`** — measurable outcome.
- `id`, `sortOrder`, `createdAt`.
- `title`, `subtitle`, `icon` (SF Symbol), `tintHex` (RGBA hex round-trip), `unitData` (Codable blob via `GoalUnitKindDTO`).
- `currentValue`, `targetValue`, `lastUpdateNote?`, `lastUpdatedAt?`.
- Lifecycle: `goalStatusRaw?` exposed as `status: GoalStatus (.active | .abandoned)`, `abandonedAt?`.
- Derived: `progress` (clamped 0–1), `isCompleted`, `percentText`, `currentText`, `targetText`, `associatedTasks: [PersistedTask]` (filtered fetch by `parentGoalID`).

### Enums (`Planner/Models/Models.swift`)

- `AppThemeCase`: `dark, light, calmEarth, liquidGlass` — the persisted theme key, with `title`, `glyph`, `colorScheme` accessors.
- `TaskType`, `IdeaStatus`, `PillStyle`, `NotesPillStyle`, `GoalStatus`, `UnitPreset` (`books, miles, revenue, hours, sessions, gymLogs`), `GoalUnit` (preset vs custom).
- Drafts: `NewTaskDraft` (value carrier from sheets → page, includes `parentGoalID: UUID?`), `NewGoalDraft`.
- Legacy `ThemeTokens` struct + `AppTheme` static colors — retained for the (mostly dead) `CommonViews` path.
- Hex bridges: `Color.toHexRGBA()` / `Color.fromHexRGBA(_:)`.

### Global orchestrators

**`ThemeStore`** (`Planner/ViewModels/LocalStore.swift`).
- `@Observable final class`. Single env-injected store.
- `selected: AppThemeCase` is persisted to the **App Group** suite (`WidgetAppGroup.defaults`) under `WidgetAppGroup.themeSelectedKey`. `didSet` calls `WidgetAppGroup.defaults?.synchronize()` then `WidgetCenter.shared.reloadAllTimelines()` so the widget palette flips immediately.
- One-shot migration on init: if the App Group is empty but `UserDefaults.standard` has the legacy value, copies it across.
- Preview-safe: `XCODE_RUNNING_FOR_PREVIEWS` guard skips persistence.
- Exposes `palette: ThemePalette` (active semantic tokens) + legacy `t: ThemeTokens`.

**`Preferences`** (same file). Non-observable static accessors for `pref.hapticsEnabled`, `pref.notificationsEnabled`, `profile.displayName`, `profile.proTier`. Both feature toggles default `true`; haptics + notifications are opt-out.

**`AppHaptic`** (in `StarkSwipeRow.swift`). Single enum gating all haptics through `Preferences.hapticsEnabled`. Three calls: `.tap()` (light), `.success()` (notification success), `.rigid()` (heavy impact).

**`NotificationManager`** (`@MainActor` singleton). `UNCalendarNotificationTrigger`, identifier shape `task.<UUID>`, subsystem `com.avenor.planner`, category `notifications`. `schedule(for:)` is fail-soft and no-ops for completed tasks, ideas, or tasks without a `dueDate` — effectively doubles as `cancel`.

**`TaskMutator` / `GoalMutator`** — `@MainActor` enums that wrap `complete`, `uncomplete`, `delete`, `increment`, `abandon`. Each accepts an optional `Animation` and triggers downstream side-effects (notification reschedule, widget snapshot publish, completion stamp).

**Lifecycle / integrity services.**
- `ConflictResolver.reconcile(in:)` — dedupes CloudKit-induced duplicates by `id`, keeps newest by timestamp.
- `LifecycleAutomation.runDailyMaintenance(in:)` — sweeps stale reminders into the archive on launch + every foreground.
- `MigrationService.runIfNeeded(context:)` — one-shot legacy `planner-data.json` → SwiftData hydration, idempotent, archives source to `.bak`.

---

## 3. Complete Navigation & View Hierarchy

### `PlannerApp` → `ContentView`

`ContentView` is a `TabView` bound to `selectedTab: Int`. The active palette drives `.tint(p.controlTint)`, `.toolbarColorScheme(p.colorScheme, for: .tabBar/.navigationBar)`, and `.preferredColorScheme(p.colorScheme)`. Tab bar + nav bar are `.ultraThinMaterial` backgrounds.

The five tabs (in tag order):

### Tab 0 — `OverviewTabView` (default landing surface; "Command Center")

- **Header**: `Command` display title + meta strip (locale-formatted date · `Registry Status: Active`).
- **`StarkCaptureBar`** wired to `commitCapture(_:)` → `CaptureParser.parse` → inserts the parsed model with a spring animation.
- **`DUE TODAY`** section: filtered `tasks` (todo/reminder, not done, `dueDate` in same day as `.now`), each row in a `StarkSwipeRow` wrapping a `TaskRow`.
- **`ACTIVE METRICS`** section: `goals` filtered to `!isCompleted && !isAbandoned`, each row in a `GoalIncrementSwipeRow` wrapping a `CompactGoalMetricRow` (lives in this file).
- **`RECENT BRAIN DUMPS`** section: top 3 notes by `effectiveEdit(_:)`, rendered as `RecentDumpRow` (also in this file).
- Empty states use `StarkEmptyState`. Sheet: `SettingsView` (gear button in header).

### Tab 1 — `TasksTabView`

- `ScrollView + LazyVStack + StarkSwipeRow` pattern (no native `List`).
- **`TodayHeader`** with task-count meta strip.
- **Filter row**: capsule menu for `TaskType?` (all / todo / idea / reminder).
- **Search field** (`searchText`).
- Two row groups: `liveTasks` and `marinatingIdeas` (the latter is a separate header for stale ideas).
- Swipe actions: leading = complete (type-aware label "Done"/"Ack"/"Shipped"), trailing = delete.
- Toolbar: archive button (`ArchiveTaskListView` sheet) + plus button (`NewItemSheet`).
- Row component: `TaskRow` (in `TasksViews.swift`) — 2pt accent rail, meta strip (`TODO · DUE MAR 4 · #UI`), title + checkbox glyph, chevron, expandable controls (deadline pickers, idea status, tag input, **goal link picker**).
- Sheets: `NewItemSheet` (includes goal-link picker), `ArchiveTaskListView`.

### Tab 2 — `NotesTabView`

- Same pattern. Leading swipe = duplicate, trailing = delete.
- Row component: `NoteRow` (`NotesViews.swift`) — neutral charcoal rail, meta `NOTE · N WORDS · EDITED [DATE]`, title TextField, expand → editor toggle. Body has two modes: rendered (`MarkdownRenderer.render`) and raw (`TextEditor`), with focus-driven swap.
- Header + search; new note via inline plus action (no separate sheet — notes are created blank then edited inline).

### Tab 3 — `GoalsTabView`

- Same pattern. Leading swipe = +1 increment (or +0.1 for decimal units), capped at target; trailing = delete.
- Filter: `Filter` enum (`all | current | completed`), default `.current`.
- Toolbar: archive (`GoalsArchiveView` for abandoned/completed) + plus.
- Row component: `GoalRowCell` — accent rail (goal tint), meta `GOAL · current / target · percent`, title, hairline progress bar. Tap → `UpdateGoalSheet`.
- Sheets: `AddGoalSheet` (with `colorChoices` palette + `UnitPreset` menu), `UpdateGoalSheet` (**includes linked-tasks card**), `GoalsArchiveView`.

### Tab 4 — `CalendarTabView`

Two stacked sections inside one `ScrollView`:

- **Part A — Month grid**: `LazyVGrid(7 columns)` of day cells. Each cell shows the day number, today-marker border, and up to 3 type-colored task dots (overflow = muted dot). Header navigation with month-shift buttons. Uses `TaskCalendarService` + `CalendarFormatter.monthGrid(containing:)`.
- **Part B — Daily task list**: tasks for `selectedDay` rendered as `StarkSwipeRow → TaskRow`, with the same swipe actions and animations as `TasksTabView`. Mutations reactively update the dot count on the grid.

### Sheets registered across tabs

`NewItemSheet`, `AddGoalSheet`, `UpdateGoalSheet`, `SettingsView`, `ArchiveTaskListView`, `GoalsArchiveView`. All wrap their cards in `ThemedCard(palette: p) { … }` and apply `.presentationBackground(p.sheetBackground) + .preferredColorScheme(p.colorScheme) + .tint(p.controlTint)`.

### Shared view primitives

`StarkSwipeRow`, `StarkSwipeAction`, `GoalIncrementSwipeRow`, `StarkEmptyState`, `ThemedCard`, `WidgetCanvasView` (widget-side), `MarkdownRenderer.render(_:) -> AttributedString`, `GoalLinkPicker`, `LinkedTasksCard`.

---

## 4. The Design System & Token Layer (Phase 6 Architecture)

### Two layers, one read

1. **`DesignTokens.swift`** — the *physical* token layer. Static color/spacing/radius/typography constants (`Surface.canvas = #0A0A0C`, `Stroke.hairline`, `Radius.card`, `Spacing.pageHorizontal`, `Tracking.display/headline/micro`, `Accent.todo/idea/reminder/note`). Legacy direct reads still exist in a handful of sites that pre-date palette migration; new code should not add them.

2. **`ThemePalette.swift`** — the *semantic* token layer. The factory `ThemePalette.make(for: AppThemeCase)` returns a struct of theme-resolved tokens. Views read `theme.palette` (let `p = theme.palette`) instead of `DesignTokens.*` so they automatically inherit whichever theme is active.

### The `ThemePalette` shape

```
id, displayName, glyph, colorScheme
canvas: CanvasKind (.solid | .gradient)
cardSurface: SurfaceKind (.flat(fill:) | .material(_, specular:))
cardBorder, cardBorderWidth, cardRadius
chromeSurface, rowFill, hairline, prominent
textPrimary / textSecondary / textTertiary
accent, controlTint
fontDesign: Font.Design
displayTracking, headlineTracking, microTracking
```

Plus computed: `sheetBackground` (solid fallback for gradient canvases) and `font(_ role: TypographyRole) -> Font`.

### The four active themes

| Theme | Canvas | Card surface | Font.Design | Color scheme | Distinctive |
|---|---|---|---|---|---|
| **Stark Dark** | `.solid(#0A0A0C)` | `.flat(#101013)` | `.default` | `.dark` | Hairline white borders (0.06–0.16 opacity), monochromatic accent (`.white`) |
| **Stark Light** | `.solid(#F9F9F9)` | `.flat(.white)` | `.default` | `.light` | Deep slate text, black-opacity borders |
| **Calm Earth** | `.solid(cream)` | `.flat(lighter cream)` | `.rounded` | `.light` | Olive accents, 20pt card radius, softer tracking |
| **Liquid Glass** | `.gradient(lavender→teal)` | `.material(.ultraThinMaterial, specular: true)` | `.rounded` | `.dark` | 22pt card radius, top-edge specular gradient stroke with `.blendMode(.plusLighter)` |

### Rendering primitives that consume the palette

- **`.themedCanvas(palette)`** — view modifier; switches on `palette.canvas` to install either a solid color or `LinearGradient` background that ignores safe areas. Used at the outermost container of each tab.

- **`ThemedCard<Content> { … }`** — view; switches on `palette.cardSurface` to render either `shape.fill(color)` (Stark/Earth) or `shape.fill(.ultraThinMaterial)` (Glass). Always overlays `strokeBorder(cardBorder, lineWidth: cardBorderWidth)`. When the surface is `.material(_, specular: true)`, additionally overlays a top→bottom white-to-clear gradient stroke with `.plusLighter` blend for the glossy edge. Always clips to its `RoundedRectangle(cardRadius)` shape.

- **Typography**: `palette.font(.display | .title | .headline | .body | .caption | .micro)` returns a `Font` with the palette's `fontDesign`. Tracking is exposed as separate `displayTracking` / `headlineTracking` / `microTracking` because SwiftUI applies `.tracking(_:)` on `Text`, not inside `Font`.

- **Sheets**: every sheet applies `.presentationBackground(p.sheetBackground)` + `.preferredColorScheme(p.colorScheme)` + `.tint(p.controlTint)`, and wraps each visual card in `ThemedCard(palette: p) { content.padding(DesignTokens.Spacing.cardInset) }`.

---

## 5. Critical Input & System Features

### The `StarkCaptureBar` capture engine

Terminal-style single-line input rendered as a flat field with a `>` monospaced prompt and `CAPTURE INTENT…` placeholder. Lives on the Overview tab. The bar itself is dumb — it hands raw text to its `onSubmit` closure and self-clears on commit (keeping focus so the user can rip off multiple captures in a row). All theming flows through `@Environment(ThemeStore.self)`.

The intelligence lives in **`CaptureParser.parse(_:)`**, which routes a string to one of three intents in this priority order:

1. **Priority extraction** → trailing `!`, `!!`, `!!!` are stripped and mapped to priority 1 (highest), 2, 3 respectively. Requires whitespace gate (so `wow!` inside a sentence is safe). Used by todos and ideas.

2. **Hashtag wins** → `.idea(title: stripped, tag: cappedTag, priority:)`. Tag is the alphanumeric run after `#`, uppercased, capped at 10 chars.

3. **Time token** → `.todo(title: stripped, dueDate: parsed, priority:)`.
   - Explicit form: `@5pm`, `@5:30pm`, `@17:00` — composes today's date with the parsed hour/minute.
   - Bare keywords: `today` (9 AM), `tomorrow` (9 AM, +1 day), `tonight` (8 PM). Whole-word matched, case-insensitive.
   - Day-of-week: `[on|this|next] monday`...`sunday`. Resolves to next occurrence at 9 AM. "this monday" rolls forward 7 days if today is Monday; "next monday" always adds +7 from the base occurrence.
   - Relative shorthand: `in N days` / `in N weeks`, case-insensitive, whole-word gated. Resolves to 9 AM on the target date.

4. **Long-form (>3 words, no tokens)** → `.note(title: firstSentence, body: rest)`. Splits on `.`, `!`, `?`, or newline.

5. **Fallback (short, unmarked)** → `.todo(title:, dueDate: nil, priority: nil)`.

The Overview commit handler (`commitCapture`) inserts the parsed model into SwiftData with a spring animation and, for todos with a deadline, calls `NotificationManager.shared.schedule(for: task)`. For todos and ideas with a priority, the priority is rendered into `details` as `P1` / `P2` / `P3` for visibility.

### WidgetKit extension (`AvenorWidget` target)

- **One widget**, three sizes. `AvenorWidget` is a `StaticConfiguration` registered as the sole entry in `AvenorWidgetBundle`. The Apple-template `AvenorWidgetControl`, `AvenorWidgetLiveActivity`, and Phase-4 `TodayGlanceWidget` / `GoalProgressWidget` source files remain in the target but are intentionally unregistered.

- **Layouts** (switched via `@Environment(\.widgetFamily)`):
  - **Small**: `Text(date, style: .time)` in `palette.font(.display)` + weekday + abbreviated date.
  - **Medium**: date block + `CaptureIntentLink` (deep-links `avenor://capture`).
  - **Large**: header (weekday/date + clock) + `CaptureIntentLink` + hairline divider + `UPCOMING · N DUE TODAY` + up to 4 task rows pulled from `WidgetSnapshotIO.readToday()`. Each row uses a 2pt accent rail mirroring the in-app row anatomy.

- **Theme.** `WidgetPalette.current()` calls `defaults.synchronize()` then reads `theme.selected.v2` from the App Group on every timeline request and resolves to one of four self-contained palettes (`starkDark`, `starkLight`, `calmEarth`, `liquidGlass`) with values mirrored from the main app's `ThemePalette`. `WidgetThemedCard` resolves to `.flat` for Stark themes and `.material(.ultraThinMaterial, specular: true)` for Liquid Glass.

- **Background.** `.containerBackground(for: .widget) { WidgetCanvasView(palette:) }` paints the canvas (solid or gradient) full-bleed behind all content.

- **Timeline.** 16 entries spaced 15 minutes apart over the next 4 hours, policy `.atEnd`. Time displays use `Text(date, style: .time)` so they auto-tick between reloads.

### App Group persistence sharing (`group.com.avenor.planner`)

Defined in `WidgetSharedModels.swift` as `WidgetAppGroup`:
- `themeSelectedKey = "theme.selected.v2"` — written by `ThemeStore.didSet`, read by `WidgetPalette.current()`.
- `todayPayloadKey = "widget.todayPayload.v1"` — `TodayWidgetPayload` (ordered `[TodayWidgetItem]` + `totalDueToday` + `generatedAt`).
- `goalsPayloadKey = "widget.goalsPayload.v1"` — `GoalsWidgetPayload` ( `[GoalWidgetItem]` + `generatedAt`).
- `WidgetSnapshotIO` handles ISO-8601 `JSONEncoder/Decoder` round-trip. Placeholders are exposed for previews.
- `WidgetSnapshotPublisher` (`@MainActor` enum on the app side) computes payloads from SwiftData on mutation and calls `WidgetCenter.shared.reloadTimelines(ofKind: "AvenorWidget")`. Wired into `TasksTabView` / `GoalsTabView` / `OverviewTabView` `.onChange` + `.onAppear`.

### `NotificationManager`

`@MainActor` singleton, `UNUserNotificationCenter` + `UNCalendarNotificationTrigger`, identifier `task.<UUID>`. `requestAuthorization()` is idempotent and called once from `PlannerApp.task`. `schedule(for:)` is the single mutator — fail-soft, gated on `Preferences.notificationsEnabled`, and effectively acts as `cancel` for completed/idea/no-deadline tasks. `TaskMutator.complete/uncomplete/delete` invoke it after every state change.

### Goal-Task Relationships (Phase 7 scaffold)

- **`PersistedTask.parentGoalID: UUID?`** — loose foreign key (no `@Relationship` macro for CloudKit safety). `nil` means unlinked.
- **`PersistedGoal.associatedTasks: [PersistedTask]`** — computed property using `FetchDescriptor` + `#Predicate { $0.parentGoalID == goalID }`. Fail-soft (returns `[]` if model is detached).
- **`NewItemSheet`** renders a `GoalLinkPicker` (self-contained `@Query`-backed Picker) that filters to active goals, displays goal icon + title. Selected goal ID threads into the draft and then into the persisted task.
- **`TaskRow.expandedBlock`** includes the same `GoalLinkPicker` bound to `$task.parentGoalID` for in-place re-linking.
- **`UpdateGoalSheet`** wraps in `ScrollView` and renders a `LinkedTasksCard` (`@Query`-backed, reads `parentGoalID == goalID`). Each linked task row shows checkbox (toggles via `TaskMutator.complete/uncomplete`), title, optional due date. Card hidden when empty.

### Other system integrations

- **CloudKit-backed SwiftData** (`.modelContainer(for: [PersistedTask.self, PersistedNote.self, PersistedGoal.self])` in `PlannerApp`). Constraints respected: no `@Attribute(.unique)`, init defaults on every non-optional property, no relationships yet defined.
- **`ConflictResolver.reconcile(in:)`** runs on first render and dedupes any CloudKit-induced duplicate UUIDs, last-writer-wins by timestamp.
- **`LifecycleAutomation.runDailyMaintenance(in:)`** runs at first render + every `.active` scene phase, sweeping dead reminders into the archived state without user intervention.
- **`MigrationService.runIfNeeded`** — one-shot legacy `planner-data.json` decode pass to SwiftData, idempotent, archives source.

---

## Summary

This is the complete current state of the codebase. No features above are aspirational; every file/type referenced exists on disk and was read or directly authored during the recent session.
