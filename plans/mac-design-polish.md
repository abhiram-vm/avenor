# Plan — PlannerMac Design Polish ("Sophisticated Stark" on macOS)

**Design read:** Reading this as: a Mac companion app for an existing iOS power-user
audience, translating the iOS "Sophisticated Stark" editorial-dark design language to
macOS, leaning toward a custom-token, keyboard-forward SwiftUI aesthetic (Linear/Vercel
restraint) that rejects native List/sidebar chrome.

> **Mode:** This is a plan only. No Swift files were modified producing it. Each phase
> below is self-contained and cites exact source locations to copy from.

---

## Phase 0 — Discovery / Allowed APIs (consolidated, verified)

All facts below were read directly from source. Use these — do not invent palette fields,
token names, or model accessors.

### Theme + palette access (read from `ThemePalette.swift`, `LocalStore.swift`)
- `@Environment(ThemeStore.self) private var theme` → `let p = theme.palette`.
- Settable selection (Settings): `@Bindable var theme = theme; $theme.selected` (`AppThemeCase`).
- Palette fields (exact names): `canvas`, `cardSurface`, `cardBorder`, `cardBorderWidth`,
  `cardRadius`, `chromeSurface`, `rowFill`, `hairline`, `prominent`,
  `textPrimary`, `textSecondary`, `textTertiary`, `accent`, `controlTint`,
  `fontDesign`, `displayTracking`, `headlineTracking`, `microTracking`.
- Fonts: `p.font(.display | .title | .headline | .body | .caption | .micro)` — honors
  the active theme's `fontDesign`. **Always use `p.font(...)`, never `Font.system(...)`**
  except for the fixed monospaced `>` glyph and monospaced digits.
- Canvas: `.themedCanvas(p)` modifier OR `p.canvasView` sibling. `p.sheetBackground` for sheets.
- Components available to reuse: `ThemedCard(palette:) { }`, `RowSeparator` (reads env),
  `StarkEmptyState(_ headline:, footnote:)` (reads env) — `Planner/Views/StarkEmptyState.swift`.

### Physical tokens (read from `DesignTokens.swift`) — for values not on the palette
- `DesignTokens.Radius.small = 8`, `.medium = 12`, `.card = 16`, `.sheet = 24`.
- `DesignTokens.Stroke.hairline = white.06`, `.prominent = white.10`, `.interactive = white.16`.
- `DesignTokens.Spacing.pageHorizontal = 20`, `.cardInset = 18`, `.stack = 16`.
- Type tints live in `DesignTokens.Accent.todo / .idea / .reminder`.

### Model accessors (verified — read from `Models.swift`, `PersistentModels.swift`)
- **TaskType has only `.todo`, `.idea`, `.reminder`.** No `.note`/`.habit` case on tasks.
  - `task.type.tint` → `DesignTokens.Accent.todo/idea/reminder` (mint / pale lilac / clay amber).
  - `task.type.pillTitle` → `"TODO" | "IDEA" | "REMINDER"` (already uppercase — use for meta strip).
  - `task.type.displayName` → `"Todo" | "Idea" | "Reminder"`.
  - `task.priorityLevel == .p1` → high-priority signal (iOS widens rail to 3pt + accent glow).
  - `task.completionVerb`, `task.isDone`.
- Goal: `goal.title`, `goal.subtitle`, `goal.progress` (0…1), `goal.currentText`,
  `goal.targetText`, `goal.percentText`, `goal.displayTint` (= `tint.opacity(0.85)`), `goal.status`.

### iOS anatomy reference locations (copy structure, not measurements — do NOT modify these)
- **Task row:** `Planner/Views/TasksViews.swift:19` (`struct TaskRow`). Anatomy:
  `HStack(spacing:0){ accentRail; content }`; rail = `Rectangle().fill(railColor).frame(width: 2)`
  (3pt + accent glow when P1); content = `VStack(spacing:10){ metaStrip; titleRow; ... }`,
  padded `.leading 16 / .trailing 14 / .vertical 16`; row background `p.rowFill`.
  Meta strip (`:128`) = uppercase micro-tracked `TYPE · DATE` with `·` separators.
  Checkbox (`:190`) = `square` / `checkmark.square.fill` (NOT `circle`). Chevron (`:206`)
  = `chevron.down`, `p.textTertiary`, rotates on expand.
- **Goal row:** `Planner/Views/GoalsViews.swift` (`progressBar` at `:152`): two stacked
  `Rectangle()`s — track `p.hairline`, fill `goal.displayTint`, `.frame(height: 2)`. Meta
  strip = `GOAL · current / target … percent` micro-tracked uppercase monospaced digits.
- **Capture bar:** `Planner/Views/StarkCaptureBar.swift` — `>` glyph `:128`, focus border
  swap `barBorder :194` (`isFocused ? p.prominent : p.hairline`), prompt styling `:261`
  (monospaced, `tracking(0.6)`, `p.textTertiary`). External focus: `shouldFocus: Binding<Bool>`
  prop `:50` + `.onChange` reset `:81` — copy this pattern for ⌘N.
- **Overview hero:** `Planner/Pages/TasksTabView.swift:463` (`TodayHeader`) — display title via
  `p.font(.display)` + `p.displayTracking`; count labels with micro uppercase sublabels.

### The mint conflict — a real decision baked into this plan
`#6EE7A8` mint is **not** in the token system. `DesignTokens.Accent.todo` is a *different*
"clinical mint" (`0.62,0.84,0.71`). The Mac files currently each redeclare
`let mint = Color(red: 110/255, green: 231/255, blue: 168/255)` locally (4 copies:
`Mac_CaptureBar:20`, `Mac_AddGoalSheet:31`, `Mac_EditTaskSheet:109`). The brief says
"no hardcoded colors" **and** "the mint `>` is non-negotiable." Resolution adopted here:
- Define the brand mint **once** as `enum Mac_Accent { static let mint = Color(...) }` (single
  literal, top of `Mac_ContentView.swift`). Treat it as an intentional theme-independent brand
  token (the capture/focus identity color), exactly as iOS treats it as a fixed identity.
- Replace all 4 scattered literals with `Mac_Accent.mint`.
- This satisfies "one source of truth" within scope. Promoting it into `DesignTokens.swift`
  is the correct long-term home but is **out of scope** (do not modify DesignTokens). Flagged.

### Anti-patterns to avoid (these APIs are wrong / banned)
- `.windowToolbarStyle(.unified(showsTitle: false))` — **no such parameter.** Correct API to
  blend the title bar is `.windowStyle(.hiddenTitleBar)` on the `WindowGroup`.
- Native `List(selection:)` for the sidebar — produces the system-blue highlight Avenor bans.
  Build a custom button rail instead (Avenor forbids native List app-wide).
- `Color.white.opacity(...)`, raw `Color(red:…)`, `cornerRadius: 10`, `Divider().opacity(…)`,
  `Color.black` — all present in current Mac files; all must become palette/token reads.
- `circle` / `checkmark.circle.fill` checkboxes — iOS uses `square` / `checkmark.square.fill`.

### Pre-work caveat (from project memory — verify, don't assume)
Memory `macos-port-state` says the Xcode Mac target may not be fully wired. **Before adding any
new `.swift` file**, confirm Mac target membership. To stay safe, this plan places all new
shared types **inside already-tracked files** (`Mac_ContentView.swift`) rather than new files,
avoiding `.pbxproj` membership edits. If the target is confirmed wired, a dedicated
`PlannerMac/Mac_Components.swift` is the cleaner home (orchestrator's call at execution time).

---

## Phase 1 — Foundation: brand token, shared task row, shared nav state

**Goal:** Build the reusable pieces both Overview and Tasks depend on, so later phases just consume them.

**What to implement (all inside `Mac_ContentView.swift` to avoid pbxproj edits):**
1. `enum Mac_Accent { static let mint = Color(red: 110/255, green: 231/255, blue: 168/255) }`.
2. `@Observable final class Mac_NavState` holding `var selection: Mac_ContentView.Pane = .overview`
   and `var captureFocusToken: Bool = false` (flip to request capture-bar focus, mirroring iOS
   `StarkCaptureBar.shouldFocus`). Inject via `.environment(...)`.
3. `struct Mac_TaskRow: View` — the shared row, copying anatomy from `TasksViews.swift:19`:
   - `HStack(spacing: 0) { rail; content }`, `.background(p.rowFill)`, corner-clipped at
     `DesignTokens.Radius.medium` with a `p.hairline` `strokeBorder` (card treatment).
   - **2pt left rail** `Rectangle().fill(task.type.tint.opacity(0.85)).frame(width: 2).frame(maxHeight:.infinity)`
     (widen to 3pt + `p.accent` when `task.priorityLevel == .p1`, matching iOS `railColor`).
   - **Meta strip:** `Text(task.type.pillTitle)` + optional `· DUE TODAY/date`, `p.font(.micro)`,
     `.tracking(p.microTracking)`, `.textCase(.uppercase)`, `p.textTertiary`, monospaced digits.
   - **Title:** `p.font(.headline)`, `.tracking(p.headlineTracking)`, `p.textPrimary`,
     `.strikethrough` + `p.textTertiary` when done.
   - **Leading checkbox:** `square` / `checkmark.square.fill`, `.contentTransition(.symbolEffect(.replace))`,
     routed through `TaskMutator.complete/uncomplete`.
   - **Trailing chevron:** `chevron.right`, `p.textTertiary`.
   - **Hover:** `@State private var hovering`; `.onHover`; background lifts `p.rowFill` →
     `p.chromeSurface`; `.animation(.easeInOut(duration: 0.12), value: hovering)` (opacity/fill only).
   - **Context menu:** Complete / Edit… / Delete (destructive), same actions as `Mac_TasksPane:70`.
   - Accept closures: `onToggleComplete`, `onEdit`, `onDelete` so each pane wires its own handlers.

**Docs to copy from:** `TasksViews.swift:19-217` (rail, meta, checkbox, chevron),
`StarkCaptureBar.swift:50-87` (focus-token pattern).

**Verification:** File compiles; `Mac_TaskRow` previews in all four themes (add `#Preview`s seeding
`ThemeStore().selected`). Grep `Mac_ContentView.swift` for `Color.white.opacity` / `Color(red` →
only the single `Mac_Accent.mint` literal may match.

**Anti-pattern guards:** No `circle` checkbox. No animation > 0.2s. Rail is `transform/opacity`-safe
(fixed-width Rectangle, no layout animation). No new file unless Mac target membership confirmed.

---

## Phase 2 — Sidebar, root layout, window chrome, keyboard shortcuts

**Files:** `Mac_ContentView.swift`, `PlannerMacApp.swift`.

**Sidebar (replace the native `List(selection:)` at `Mac_ContentView.swift:45-50`):**
- `NavigationSplitView { sidebar } detail: { ... }` where `sidebar` is a custom
  `VStack(alignment: .leading, spacing: 4)` of nav buttons (NOT a `List`), driven by `Mac_NavState`.
- Each nav button: SF Symbol + `pane.title` in `p.font(.body)`.
  - Inactive: `p.textSecondary`, outline glyph, clear background.
  - Selected: `Mac_Accent.mint` text + glyph, plus a subtle selected fill
    (`Mac_Accent.mint.opacity(0.12)`) and a 2pt mint left accent mark (mirror the iOS row rail).
    Use the `.fill` variant of the SF Symbol when selected (`pane.glyph` outline → add a
    `glyphSelected` returning the `.fill` symbol; e.g. `square.grid.2x2` → `square.grid.2x2.fill`,
    `target` stays, `checklist` → use `checklist.checked`).
  - `.buttonStyle(.plain)`; `.onHover` lift to `p.chromeSurface` (easeInOut 0.12s).
- Sidebar column background = `p.canvasView` (NOT system sidebar material). Apply
  `.scrollContentBackground(.hidden)` if any scroll container is used. No header label, no
  disclosure triangles. Column width: `.navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)`.
- Keep the `Mac_CaptureBar` above the split (existing structure `:38-43`) but replace
  `Divider().opacity(0.4)` with `RowSeparator()` (palette hairline).

**Window chrome (`PlannerMacApp.swift:55-89`):**
- Add `.windowStyle(.hiddenTitleBar)` to the `WindowGroup` to blend the title bar into the canvas.
- Replace `.defaultSize(width: 980, height: 640)` is fine; add a real minimum via the root view:
  set `Mac_ContentView`'s `.frame(minWidth: 900, minHeight: 600)` (current is 720×460 at `:59` —
  raise it).
- Error fallback `:74` uses `Color.black` — switch to `DesignTokens.Surface.canvas` (or
  `ThemePalette.starkDark.sheetBackground`) so even the failure screen is on-brand.

**Keyboard shortcuts (`.commands { }` on the `WindowGroup`):**
- Expose nav state to commands via `.focusedSceneValue(\.macNav, navState)` (define a
  `FocusedValueKey`); commands read it with `@FocusedValue(\.macNav)`.
- `CommandGroup(replacing: .newItem)`: "New Capture" → `⌘N` sets `navState.captureFocusToken = true`.
- A custom `CommandMenu("View")` (or `CommandGroup(after: .toolbar)`): "Overview ⌘1",
  "Tasks ⌘2", "Goals ⌘3" set `navState.selection`.
- `⌘F` focus search: only the Tasks pane has a search field — gate the command on the active pane;
  if no search field, omit rather than fake it (brief says "if search field exists").
- `Escape` to dismiss sheets/popovers: rely on `.keyboardShortcut(.cancelAction)` already on
  every sheet's Cancel button (`Mac_EditTaskSheet:165`, `Mac_AddGoalSheet:101`) — verify each
  sheet has a Cancel with `.cancelAction`; add where missing.

**Docs to copy from:** iOS tab-selection expression in `ContentView.swift` (tab bar), focus-token
pattern `StarkCaptureBar.swift:81`.

**Verification:** Launch app → sidebar shows no blue highlight; selected item is mint with left
mark; title bar is flush with canvas; window won't shrink below 900×600; `⌘1/2/3` switch panes,
`⌘N` focuses capture, `Esc` closes an open sheet. Grep `Mac_ContentView.swift PlannerMacApp.swift`
for `Divider(`, `Color.black`, `.unified(` → zero matches.

**Anti-pattern guards:** No `List(selection:)`. No `.windowToolbarStyle(.unified(showsTitle:))`.
No system blue tint anywhere.

---

## Phase 3 — Capture bar polish (`Mac_CaptureBar.swift`)

**What to implement:**
- Delete the local `let mint = …` (`:20`); use `Mac_Accent.mint` for the `>` glyph and cursor `.tint`.
- `>` glyph: keep `Font.system(size: 14, weight: .bold, design: .monospaced)`, `Mac_Accent.mint`
  (non-negotiable — unchanged).
- Background: `p.rowFill` is fine but switch the corner radius literal `10` → `DesignTokens.Radius.small`.
- Idle border: **none** (or `Color.clear`) per brief; focus border: `Mac_Accent.mint.opacity(0.55)`
  (already there at `:46`) — keep, but replace the idle `Color.white.opacity(0.07)` with `p.hairline`.
- Placeholder: replace plain `TextField("Capture a task…")` with a styled prompt matching
  `StarkCaptureBar.prompt` (`:261`): Space-Mono/monospaced, `.tracking(0.6)` (≈ +0.16em feel),
  `p.textTertiary`. Use the `prompt:` parameter form `TextField("", text:, prompt: Text(...))`.
- **Capture flash:** on successful `commit()`, briefly set a `@State flash = true` that paints the
  border `Mac_Accent.mint` at full, then `withAnimation(.easeInOut(duration: 0.18)) { flash = false }`.
  Border opacity only — no layout, ≤ 0.2s. Then clear text (existing `:97`).
- **⌘N focus:** add `var shouldFocus: Binding<Bool> = .constant(false)` prop and the
  `.onChange(of: shouldFocus.wrappedValue)` reset block copied verbatim from `StarkCaptureBar.swift:81-86`.
  `Mac_ContentView` binds it to `navState.captureFocusToken`.

**Docs to copy from:** `StarkCaptureBar.swift:124-201` (input row, border swap), `:261-266` (prompt).

**Verification:** `>` is mint in all four themes; placeholder is monospaced wide-tracked tertiary;
focus shows mint hairline border; a successful capture flashes mint then clears; `⌘N` from any pane
focuses the bar. Grep `Mac_CaptureBar.swift` for `Color(red`, `Color.white.opacity`, `cornerRadius: 10`
→ zero matches.

**Anti-pattern guards:** Don't remove or soften `>`. Flash is border-opacity only, ≤ 0.2s.

---

## Phase 4 — Task rows in Tasks + Overview panes

**Files:** `Mac_TasksPane.swift`, `Mac_OverviewPane.swift`.

**`Mac_TasksPane` (`:19-90`):**
- Replace the inline `row(_:palette:)` (plain HStack, `circle` checkbox, `Divider().opacity(0.25)`)
  with `Mac_TaskRow` from Phase 1, wiring `onToggleComplete`/`onEdit: { editingTask = task }`/`onDelete`.
- Replace the plain empty-state `Text(...)` (`:24-27`) with `StarkEmptyState("Empty.",
  footnote: "Press ⌘N to capture your first item.")`.
- Stack spacing: `LazyVStack(spacing: 10)`; page padding stays 24 (or `DesignTokens.Spacing.pageHorizontal`).
  Drop the `Divider()` between rows — cards self-separate via their own border + spacing.
- Keep `Mac_EditTaskSheet` wiring (`:40-42`); its token cleanup happens in Phase 6.

**`Mac_OverviewPane` (`:27-73`):**
- Add a display hero above "Due Today": `Text("Overview")` (or today's date) via `p.font(.display)`
  + `.tracking(p.displayTracking)` + `p.textPrimary`, copying `TodayHeader` (`TasksTabView.swift:519`).
- Section header "DUE TODAY": already micro-uppercase (`:31-35`) — switch its color to `p.textTertiary`
  and ensure `.tracking(p.microTracking)`.
- Replace the inline due-today rows (`:43-64`, `circle` checkbox) with `Mac_TaskRow` (Overview wires
  `onEdit` to nil / no-op or opens the same `Mac_EditTaskSheet`; minimally Complete + Delete).
- Replace `Text("No tasks due today.")` with `StarkEmptyState("No tasks due today.")`.

**Docs to copy from:** `TasksViews.swift:19` (row), `TasksTabView.swift:463-555` (hero/section).

**Verification:** Both panes render `Mac_TaskRow` with 2pt type-colored rail, uppercase meta strip,
`square` checkbox, hover lift, right-click menu; Overview shows the display title; empty states use
`StarkEmptyState`. All four themes switch cleanly. Grep both files for `circle`, `Divider(`,
`Color.white.opacity`, `Font.system` → only monospaced-digit/`>` exceptions allowed.

**Anti-pattern guards:** No duplicated row code — both panes consume the single `Mac_TaskRow`.

---

## Phase 5 — Goal rows (`Mac_GoalsPane.swift`)

**What to implement:**
- Rework `card(_:palette:)` (`:78-110`) to match iOS `GoalsViews` progress anatomy:
  - Title `p.font(.headline)` + `.tracking(p.headlineTracking)` + `p.textPrimary`.
  - Progress bar: two `Rectangle()`s in a `GeometryReader` — **track `p.hairline`** (currently
    `p.textTertiary.opacity(0.25)` — change it), **fill `goal.displayTint`**, `.frame(height: 2)`
    (iOS uses 2pt resting). Keep the existing width math `max(0,min(1,goal.progress)) * geo.width`.
  - Meta **below** the bar: `"\(goal.currentText) / \(goal.targetText)"` (+ optional `goal.percentText`)
    in `p.font(.micro)`, `.tracking(p.microTracking)`, `.textCase(.uppercase)`, monospaced digits,
    `p.textTertiary`. (Currently the count uses `p.font(.body)` at `:90` — demote to micro meta.)
  - Card surface: replace `RoundedRectangle(cornerRadius: 12).fill(p.rowFill)` (`:108`) with the
    same card treatment as `Mac_TaskRow` (`p.rowFill` fill + `p.hairline` strokeBorder, radius
    `DesignTokens.Radius.medium`), OR wrap in `ThemedCard(palette: p) { ... }` for full theme parity
    (recommended — gives Liquid Glass its material + specular edge for free).
  - **Hover** lift + **context menu** identical treatment to `Mac_TaskRow` (the menu already exists
    at `:35-50` — keep its `GoalMutator` routing).
- Empty state (`:28-31`) → `StarkEmptyState("No active goals.", footnote: "Add one with +.")`.
- Toolbar `+` (`:60-66`) is a bare system `Image(systemName:"plus")` — leave functional, but it
  inherits system tint; if it shows blue, wrap label to use `p.textPrimary`.

**Docs to copy from:** `GoalsViews.swift:152-165` (progress bar), `:100-120` (meta strip).

**Verification:** Goal cards show title, mint/displayTint progress fill on a hairline track, meta
below in micro uppercase; hover + right-click match task rows; `ThemedCard` makes Liquid Glass
frosted. Grep `Mac_GoalsPane.swift` for `cornerRadius: 12`, `opacity(0.25)` → zero matches.

---

## Phase 6 — Settings + sheet token cleanup

**Files:** `Mac_SettingsView.swift`, `Mac_EditTaskSheet` (in `Mac_TasksPane.swift`), `Mac_AddGoalSheet.swift`.

- **`Mac_EditTaskSheet` (`Mac_TasksPane.swift:98-188`)** and **`Mac_AddGoalSheet.swift`:**
  - Delete local `let mint` (`:109`, `:31`) → `Mac_Accent.mint`.
  - Replace every `Color.white.opacity(0.07)` field border → `p.hairline`; `cornerRadius: 8`
    literal → `DesignTokens.Radius.small`; field fill `p.rowFill` is fine.
  - Field label "TITLE"/"TARGET": already micro — ensure `.tracking(p.microTracking)` +
    `.textCase(.uppercase)` for consistency.
  - Confirm each sheet has a Cancel button with `.keyboardShortcut(.cancelAction)` (present) so
    Escape dismisses (Phase 2 acceptance).
- **`Mac_SettingsView.swift`:** Functional but plain `Form/.grouped`. Minimum: it already drives
  `$theme.selected` correctly (theme switching works). Optional polish within scope: wrap the
  picker area on `.themedCanvas(theme.palette)` so the Settings window reads on-brand, and label
  the theme row with `p.font(.body)`. Do not add settings beyond the theme picker.

**Verification:** Edit-task and add-goal sheets contain zero `Color.white.opacity` / `Color(red` /
`cornerRadius: 8` literals; theme picker still re-morphs the whole app live.

---

## Phase 7 — Verification (final)

1. **Build:** Compile the macOS target (XcodeBuildMCP `build_sim`/`build_run_sim` for the Mac
   scheme, or `xcodebuild` for the `PlannerMac` target). Zero warnings about layout constraints.
2. **Hardcoded-value sweep (must return only sanctioned exceptions):**
   ```
   rg -n 'Color\.white\.opacity|Color\(red:|Color\.black|cornerRadius: (8|10|11|12)|\.unified\(|Divider\(' PlannerMac/
   ```
   Allowed survivors: the **single** `Mac_Accent.mint` literal; monospaced `>`/digit font sizes.
   Everything else must trace to `p.*` / `DesignTokens.*`.
3. **Four-theme pass:** Switch Dark → Light → Calm Earth → Liquid Glass in Settings; confirm every
   pane (sidebar, capture, tasks, overview, goals, sheets) re-morphs with no layout breakage and
   Liquid Glass shows material + specular on cards.
4. **Anatomy checklist:** task rows have 2pt type rail + uppercase meta + `square` checkbox + hover
   lift + context menu; goal rows have hairline-track mint progress + meta below; sidebar selected =
   mint (no blue); capture bar `>` mint + monospaced placeholder + mint focus border + capture flash.
5. **Keyboard:** `⌘N`, `⌘1`, `⌘2`, `⌘3`, `Escape` all work globally.
6. **Title bar** blends into canvas (`.hiddenTitleBar`); window won't collapse below 900×600.

---

## Stop-and-ask triggers (do not proceed silently)
- Any animation > 0.2s or animating layout (frame/bounds/width/height).
- Needing a color not derivable from the palette/tokens **other than** the one sanctioned
  `Mac_Accent.mint` brand literal — if a second such color appears, stop.
- Adding a new `.swift` file when Mac target membership is unconfirmed (pbxproj edit risk).
- Any change to a file outside `PlannerMac/`.

## Files in scope (modify) — all under `PlannerMac/`
`Mac_ContentView.swift`, `Mac_CaptureBar.swift`, `Mac_OverviewPane.swift`,
`Mac_TasksPane.swift` (incl. `Mac_EditTaskSheet`), `Mac_GoalsPane.swift`,
`Mac_SettingsView.swift`, `Mac_AddGoalSheet.swift`, `PlannerMacApp.swift`.
Reference-only (never modify): `DesignTokens.swift`, `ThemePalette.swift`, `StarkCaptureBar.swift`,
`StarkEmptyState.swift`, `TasksViews.swift`, `GoalsViews.swift`, `TasksTabView.swift`.
