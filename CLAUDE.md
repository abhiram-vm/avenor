# CLAUDE.md — Avenor Project Context

This file is read automatically by Claude Code at the start of every session. It contains the project structure, conventions, constraints, and architectural principles for Avenor. Do not modify this file without explicit project sign-off.

---

## Project Overview

**Avenor** is a premium iOS life organizer (productivity app) shipping on the App Store under bundle ID `com.avenor.planner`. The app unifies tasks, notes, goals, habits, and calendar behind a single natural language input bar and a "Sophisticated Stark" design aesthetic with four distinct themes.

**Current Version:** 1.3  
**Target iOS:** 17.0+  
**Swift Version:** 5.9+  
**Architecture Pattern:** MVVM + Service Layer  
**Data Persistence:** SwiftData (CloudKit-compatible)  
**UI Framework:** SwiftUI  

---

## Tech Stack & Dependencies

- **Persistence:** SwiftData (no custom migration layer; use `@Model` classes)
- **Sync:** CloudKit (configured via SwiftData; no manual CloudKit calls)
- **State Management:** `@Observable` for `ThemeStore` only; all other domain state lives in SwiftData via `@Query`
- **Widgets:** WidgetKit (AvenorWidget target; self-contained, no shared design system imports)
- **Live Activity:** EventCountdownAttributes with Dynamic Island support
- **Notifications:** UNUserNotificationCenter (calendar-based triggers)
- **Haptics:** Custom `AppHaptic` enum gating all haptic feedback through `Preferences.hapticsEnabled`
- **Third-Party Dependencies:** ZERO. No SPM packages, no CocoaPods, no external libraries beyond the standard library.

---

## Architectural Pillars (Do Not Deviate)

### 1. SwiftData Models (Persistence Layer)

All persistent data lives in three core models:

- `PersistedTask` — unified actionable item (todos, reminders, ideas)
- `PersistedNote` — free-form text with markdown support
- `PersistedGoal` — measurable outcome with progress tracking

**Critical Constraints:**
- No `@Attribute(.unique)` — CloudKit forbids it
- All non-optional fields must have init defaults
- No `@Relationship` macros yet (relationships are optional + manual foreign keys via UUID)
- CloudKit compatibility is non-negotiable; test every schema change in iCloud sync scenarios

### 2. Service Layer (Pure Enums/Actors)

All business logic lives in `@MainActor` enums and actor singletons. Views never mutate SwiftData directly.

**Core Services:**
- `TaskMutator` — complete, uncomplete, delete, with side effects (notifications, widget updates, timestamps)
- `GoalMutator` — increment, abandon, with progress sync
- `NotificationManager` — schedule/cancel notifications; idempotent and fail-soft
- `ConflictResolver` — reconcile CloudKit-induced duplicates on launch
- `LifecycleAutomation` — daily maintenance (archive stale reminders, etc.)
- `WidgetSnapshotPublisher` — compute and publish widget payloads to App Group
- `CaptureParser` — parse natural language input into task/note/goal
- `MarkdownRenderer` — render markdown to AttributedString for display

**Rule:** Services are never instantiated; they're called as static/singleton methods.

### 2b. App Intents Layer (Siri / Shortcuts / Spotlight)

Avenor's core actions are exposed to Siri, Spotlight, the Shortcuts app, and the Action Button via the AppIntents framework. Lives in the **main Planner target** (no extension): `Planner/Services/AvenorIntents.swift` + `AvenorShortcuts.swift`.

**Intents:**
- `AddTaskIntent` — routes free text through `CaptureParser.parse(_:)` (so Siri capture and the in-app capture bar can never disagree), inserts the resulting task/idea/note/habit, schedules notifications, refreshes widgets
- `GetTodaysTasksIntent` — reads `widget.todayPayload.v1` from the App Group (no model context needed); falls back to a store fetch only when the snapshot is stale (generated before today)
- `CompleteTaskIntent` — fuzzy match (lowercased `contains`, exact-title match wins ties) against open tasks → `TaskMutator.complete`
- `CheckGoalProgressIntent` — reads active goals; optional goal name parameter, blank = all
- `CaptureNoteIntent` — inserts a `PersistedNote` with title + optional body

**Rules:**
- Every `perform()` is `@MainActor` (the service layer is main-actor isolated)
- `openAppWhenRun = false` everywhere — intents run in the background
- Mutating intents open the shared default SwiftData store via the cached `IntentModelStore.container()` (same schema/configuration as `PlannerApp`)
- Fail-soft: every error path returns an explanatory `IntentDialog`; intents never crash or surface raw errors
- `AvenorShortcuts` (`AppShortcutsProvider`) registers the Siri phrases; every phrase must embed `\(.applicationName)`
- `IntentDonations.donateAddTask()` is fired from `TaskMutator.complete` and `OverviewTabView.commitCapture` so the system learns capture frequency
- Entitlements: `com.apple.developer.siri` in `Planner.entitlements`; intent names listed under `NSUserActivityTypes` in `Planner/Info.plist`

### 3. State Management

- **Theme State:** `@Observable` singleton `ThemeStore` (global env injection)
- **Domain State:** All live in SwiftData; read via `@Query`; never hold mutable copies in @State
- **Transient State:** Only UI-transient state (sheet presentation, scroll offset, etc.) lives in @State

**Rule:** If it needs to persist, it must be a SwiftData model or written to the App Group.

### 4. App Group Sharing

**Suite ID:** `group.com.avenor.planner`

All IPC between main app and WidgetKit/Live Activity extensions happens via App Group UserDefaults or JSON-encoded Codable payloads:

- `theme.selected.v2` — active `AppThemeCase` raw value (syncs instantly)
- `widget.todayPayload.v1` — serialized `TodayWidgetPayload` (snapshot)
- `widget.goalsPayload.v1` — serialized `GoalsWidgetPayload` (snapshot)
- `widget.pendingActions.v1` — queue of `WidgetPendingAction` (for interactive widgets)

**Rule:** All App Group keys are versioned (`.v1`, `.v2`) for schema evolution without breaking.

---

## Coding Conventions

### SwiftUI Views

- **No Native List or NavigationStack:** Use `ScrollView + LazyVStack + StarkSwipeRow` throughout
- **Custom Gestures Only:** Hand-built `StarkSwipeRow` and `GoalIncrementSwipeRow` replace all `.swipeActions`
- **themedCanvas Modifier:** Every tab wraps its entire content in `.themedCanvas(palette: p)` to apply the active theme's background
- **ThemedCard Component:** All floating surfaces (sheets, cards) use `ThemedCard(palette: p) { content }` to apply semantic borders, backgrounds, and material styling
- **Never use native HStack/VStack for list rows:** Use custom row components with explicit frame constraints

### Animation & Motion

- **120Hz Frame Budget:** All motion must maintain 60fps minimum; use `transform` and `opacity` only, never animate layout properties (frame, bounds)
- **Spring Easing:** Use `cubic-bezier(0.34, 1.56, 0.64, 1)` for spring feel (not `.spring()`)
- **Smooth Drift:** Use `cubic-bezier(0.45, 0, 0.55, 1)` for subtle continuous motion
- **No Bouncy Defaults:** Animations default to easeInOut unless explicitly spring or linear
- **Haptics Gated:** Every haptic feedback fires through `AppHaptic.tap()` / `.success()` / `.rigid()`; never call `UIImpactFeedbackGenerator` directly

### Naming & Terminology

- **Tabs:** Overview (formerly "Command"), Tasks, Notes, Goals, Calendar
- **Content Types:** `.todo`, `.idea`, `.reminder` (TaskType enum); `.active`, `.abandoned` (GoalStatus enum)
- **Section Labels:** "Due Today", "Active Metrics", "Recent Brain Dumps", "This Week" (title case, not uppercase)
- **Empty State Copy:** Friendly, actionable, no clever metaphors ("No tasks due today." not "INBOX HOLDS THE LINE.")

### Type Chips (New Pattern)

All task/goal/note rows display a type chip in the meta strip:
- Format: colored dot (6px) + label in Space Mono 8px uppercase
- Colors: mint for TODO, purple for IDEA, amber for REMINDER, slate for NOTE
- Position: first element in the meta strip before dot separators

---

## Design System (Non-Negotiable)

### Colors (Exact Hex Values)

- **Canvas:** `#0A0A0C` (dark theme)
- **Canvas Light:** `#F9F9F9` (light theme)
- **Card Surface:** `#0E0E11` (dark), `#FFFFFF` (light)
- **Accent Mint:** `#6EE7A8` (all themes)
- **Text Primary:** `rgba(255,255,255,0.92)` (dark), `rgba(0,0,0,0.92)` (light)
- **Text Meta:** `rgba(255,255,255,0.25)` (dark), `rgba(0,0,0,0.35)` (light)
- **Borders:** `rgba(255,255,255,0.07)` (dark), `rgba(0,0,0,0.1)` (light)

### Typography

- **Display/Title:** Inter 800, letter-spacing -0.02em
- **Headline:** Inter 600–700, letter-spacing -0.01em
- **Body:** Inter 400–500, letter-spacing 0
- **Meta/Mono:** Space Mono 700, letter-spacing 0.12em (section labels, meta strips, capture bar)
- **Micro:** Space Mono 400, letter-spacing 0.08em (tags, badges, timestamps)

### Components

- **StarkSwipeRow:** Axis-locked swipe gesture with 110pt threshold and haptic feedback on commit; hand-built, no native swipeActions
- **StarkCaptureBar:** Terminal-style input (`>` prompt + monospace field); natural language parser upstream
- **ThemedCard:** Resolves background/border/radius based on active `ThemePalette`; handles material vs. flat surfaces
- **MarkdownRenderer:** Renders task/note body markdown to AttributedString; bullet preprocessing

---

## Lifecycle Hooks (Critical)

### PlannerApp.swift

On app launch and every `.active` scene phase:
1. `ConflictResolver.reconcile(in: modelContext)` — dedup CloudKit-induced duplicates
2. `LifecycleAutomation.runDailyMaintenance(in: modelContext)` — sweep stale reminders to archive
3. `NotificationManager.requestAuthorization()` — one-shot (idempotent)
4. `WidgetSnapshotPublisher.publishToday(…)` — refresh widget payload

**Rule:** These must run serially, in order, before any view renders.

---

## Testing & Validation

### Before Committing

- [ ] Run on iOS 17, 18 (simulator)
- [ ] Test all four themes (Stark Dark, Light, Calm Earth, Liquid Glass)
- [ ] Verify CloudKit sync doesn't create duplicate UUIDs
- [ ] Check 120Hz frame budget via Core Animation tool in Instruments
- [ ] Test widget refresh (WidgetCenter.shared.reloadAllTimelines)
- [ ] Verify notifications fire at correct times (use Simulator notifications settings)
- [ ] Check App Group payload encoding/decoding (test Live Activity + widgets)

### Instrumentation

- **Xcode Instruments:** Core Animation, System Trace (check for dropped frames)
- **Console:** Filter by bundle ID `com.avenor.planner`; watch for CloudKit sync errors
- **Network Link Conditioner:** Test CloudKit behavior on slow/offline networks

---

## Absolute Prohibitions

**Never:**
- Import third-party dependencies without explicit approval
- Mutate SwiftData directly from a view (always use service layer)
- Use native `.swipeActions` — use `StarkSwipeRow` instead
- Animate layout properties (frame, bounds, width, height) — use transform only
- Create circular dependencies between services
- Store sensitive data (API keys, auth tokens) in UserDefaults unencrypted
- Call `UIImpactFeedbackGenerator` directly — use `AppHaptic` enum
- Use `@Relationship` macros (stick to optional + manual foreign keys)
- Modify AppDelegate or SceneDelegate unless coordinating app-level lifecycle
- Add `@Attribute(.unique)` to any SwiftData model

---

## File Structure
Avenor/
├── Planner/
│   ├── PlannerApp.swift                   (lifecycle, app entry)
│   ├── Models/
│   │   ├── PersistentModels.swift         (@Model classes: Task, Note, Goal, Habit)
│   │   └── Models.swift                   (enums: TaskType, GoalStatus, AppThemeCase, etc.)
│   ├── Services/
│   │   ├── TaskMutator.swift
│   │   ├── GoalMutator.swift
│   │   ├── NotificationManager.swift
│   │   ├── ConflictResolver.swift
│   │   ├── LifecycleAutomation.swift
│   │   ├── WidgetSnapshotPublisher.swift
│   │   ├── CaptureParser.swift
│   │   ├── MarkdownRenderer.swift
│   │   ├── AvenorIntents.swift             (AppIntents: Siri/Shortcuts/Spotlight)
│   │   ├── AvenorShortcuts.swift           (AppShortcutsProvider phrases)
│   │   └── ... (other services)
│   ├── Views/
│   │   ├── ContentView.swift               (TabView root)
│   │   ├── Tabs/
│   │   │   ├── OverviewTabView.swift
│   │   │   ├── TasksTabView.swift
│   │   │   ├── NotesTabView.swift
│   │   │   ├── GoalsTabView.swift
│   │   │   └── CalendarTabView.swift
│   │   ├── Components/
│   │   │   ├── StarkSwipeRow.swift
│   │   │   ├── GoalIncrementSwipeRow.swift
│   │   │   ├── ThemedCard.swift
│   │   │   ├── StarkCaptureBar.swift
│   │   │   └── ... (shared components)
│   │   └── Sheets/
│   │       ├── SettingsView.swift
│   │       └── ... (modal sheets)
│   ├── DesignSystem/
│   │   ├── DesignTokens.swift              (literal color/spacing/radius values)
│   │   ├── ThemePalette.swift              (semantic tokens; factory for active theme)
│   │   └── LocalStore.swift                (ThemeStore @Observable singleton)
│   └── Utilities/
│       └── ... (helpers, extensions)
├── AvenorWidget/                          (WidgetKit target)
│   ├── AvenorWidgetBundle.swift
│   ├── AvenorWidget.swift
│   ├── WidgetViews.swift
│   ├── WidgetSharedModels.swift            (App Group Codable types)
│   └── ... (widget-specific files)
└── ... (other targets)
---

## How to Use This File

1. **Before Starting Work:** Read this file top-to-bottom
2. **During Coding:** Reference specific sections (e.g., "Coding Conventions", "Absolute Prohibitions")
3. **For New Features:** Check "Architectural Pillars" to ensure your work fits the pattern
4. **For Debugging:** "Lifecycle Hooks" and "Testing & Validation" will clarify expected behavior

---

## Last Updated

**Date:** June 8, 2026  
**Version:** 1.4 (Latest) 
**Author:** Abhiram (solo indie dev)

If this file is outdated notify me immediately.
