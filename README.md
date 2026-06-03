# Avenor — Premium iOS Life Organizer

A beautifully crafted iOS app for unified task, note, goal, and calendar management. Built with SwiftUI and SwiftData on a "Sophisticated Stark" design system emphasizing deep blacks, hairline borders, and hand-built interactions.

**Status:** Live on App Store. Currently in Phase 6 (interactive widgets + live activities).

## Features

- **Tasks** — Unified todo/reminder/idea capture with custom swipe actions and deadline tracking
- **Notes** — Free-form markdown notes with word count and edit-date tracking
- **Goals** — Measurable outcomes with progress bars and one-tap logging
- **Calendar** — Month grid with task indicators and daily task list view
- **Interactive Widgets** — Today widget (task count) + Goal Progress widget via App Group snapshots
- **Live Activities** — Lock screen + Dynamic Island countdown for high-priority timed events
- **Local Notifications** — UNCalendarNotificationTrigger reminders for due dates
- **Custom Interactions** — Hand-built `StarkSwipeRow` with axis-lock, rubber-banding, and haptic feedback
- **Dark Mode Only** — Monochromatic aesthetic with crisp white accents and task-type colors

## Tech Stack

- **Language:** Swift 5.9+
- **UI Framework:** SwiftUI (iOS 17+)
- **Persistence:** SwiftData (CloudKit-compatible schema)
- **State Management:** `@Observable` (ThemeStore) + `@Query` (live data)
- **Widgets:** WidgetKit extension (small/medium families) + ActivityKit (Dynamic Island)
- **IPC:** App Group (`group.com.avenor.planner`) for widget snapshots & pending actions
- **Notifications:** UserNotifications + UNCalendarNotificationTrigger
- **Design System:** Custom tokens (Stark palette), no third-party UI frameworks

## Project Structure

```
Avenor/
├── Planner/                          # Main app target
│   ├── Models/                       # SwiftData models (PersistedTask, PersistedNote, PersistedGoal)
│   ├── Views/                        # UI components (TaskRow, NoteRow, GoalRow, StarkSwipeRow, etc.)
│   ├── Pages/                        # Tab view screens (TasksTabView, NotesTabView, GoalsTabView, etc.)
│   ├── Services/                     # Business logic (TaskMutator, WidgetSnapshotPublisher, NotificationManager, etc.)
│   ├── DesignSystem/                 # Design tokens (colors, typography, spacing)
│   ├── Utilities/                    # Helpers (MarkdownRenderer, TaskCalendarService, etc.)
│   └── PlannerApp.swift              # Root app + lifecycle hooks
│
├── AvenorWidget/                     # Widget extension target
│   ├── Views/                        # Widget UI (AvenorTasksWidget, AvenorWidgetLiveActivity)
│   ├── AppIntent.swift               # Interactive widget intents (CompleteTaskIntent, ToggleHabitIntent)
│   └── AvenorWidgetBundle.swift      # Widget bundle registration
│
├── ARCHITECTURE.md                   # Detailed architectural guide
└── README.md                         # This file
```

## Requirements

- Xcode 15.3+
- Swift 5.9+
- iOS 17+
- Deployment target: iOS 17.0

## Setup & Build

### 1. Clone the repo
```bash
git clone git@github.com:abhiram-vm/avenor.git
cd avenor
```

### 2. Open in Xcode
```bash
open Planner.xcodeproj
```

### 3. Select the Planner target
- Scheme: **Planner**
- Device: iPhone 15+ or simulator
- Build settings are pre-configured; no manual setup needed

### 4. Build & Run
```
Cmd+R  (or Product → Run)
```

## Manual Xcode Setup (First Time)

The widget extension and live activities require manual capability setup in Xcode:

1. **App Group Capability**
   - Select both `Planner` and `AvenorWidget` targets
   - Capabilities → App Group
   - Container ID: `group.com.avenor.planner`

2. **Live Activities Support**
   - Select `Planner` target
   - Info.plist → Add `NSSupportsLiveActivities` (Boolean) = `YES`

3. **Widget Target Membership**
   - Select `Planner/Shared/WidgetSharedModels.swift`
   - File Inspector → Target Membership → check both `Planner` and `AvenorWidget`

See the [Architecture Guide](ARCHITECTURE.md) for detailed technical design.

## Architecture Highlights

### Data Layer
- **SwiftData models** for tasks, notes, goals with CloudKit-safe schema (no unique constraints)
- **`@Observable` ThemeStore** for theme persistence to App Group
- **Service layer** (pure enums/actors) for mutations, notifications, widget publishing

### UI Layer
- **Custom swipe interactions** (`StarkSwipeRow`, `GoalIncrementSwipeRow`) with haptic feedback
- **"Sophisticated Stark" design** — deep blacks (#0A0A0C), hairline borders, white accents
- **Responsive layouts** using `ScrollView + LazyVStack` (no native List)

### Integration
- **App Group IPC** for widget theme + snapshots
- **Pending-action queue** — widget taps journal to App Group, app applies on foreground
- **Live Activities** — lock-screen countdowns for high-priority timed events within 15 min

## Available Services

### Core Mutators
- `TaskMutator.complete(task, in: context)`
- `TaskMutator.delete(task, in: context)`
- `GoalMutator.increment(goal, by:, in: context)`

### Lifecycle
- `ConflictResolver.reconcile(in:)` — dedup CloudKit duplicates
- `LifecycleAutomation.runDailyMaintenance(in:)` — archive stale reminders
- `NotificationManager.schedule(for: task)` — calendar notifications

### Widget Integration
- `WidgetSnapshotPublisher.publishTasks(_:)` — reload Tasks widget
- `WidgetSnapshotPublisher.publishRoutine(_:)` — reload Routine widget
- `WidgetActionApplier.drainAndApply(in:)` — apply pending widget taps

### Parsing & Rendering
- `CaptureParser.parse(_:)` — NL task capture (e.g., "Call John tmr 2pm" → PersistedTask)
- `MarkdownRenderer.render(_:)` — AttributedString from markdown

## Design System

**Colors:**
- Canvas: `#0A0A0C`
- Card: `#101013`
- Accent: White (primary) + task-type colors (mint, clay, lilac, slate)

**Typography:**
- Display: 32pt bold, -0.6 tracking
- Title: 22pt, -0.3 tracking
- Body: 15pt, +3 line-spacing
- Micro: 11pt uppercase, +0.8 tracking

See `Planner/DesignSystem/DesignTokens.swift` for the complete token set.

## Haptics

All haptics are gated by `Preferences.hapticsEnabled` (opt-out, defaults true):
- `AppHaptic.tap()` — light impact (buttons, toggles)
- `AppHaptic.success()` — notification success (task completion, goal logging)
- `AppHaptic.rigid()` — heavy impact (destructive delete)

## Logging

All logging uses `Logger(subsystem: "com.remyavipindas.avenor", category:...)` for production safety. No `print()` statements.

## License

Private. All rights reserved.

---

For detailed architectural docs, see [ARCHITECTURE.md](ARCHITECTURE.md).
