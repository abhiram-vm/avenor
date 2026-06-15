# AVENOR — MASTER CONTEXT DOCUMENT
### For new Claude sessions. Read this entirely before doing anything.
*Last updated: June 2026*

---

## WHO YOU'RE WORKING WITH

**Abhiram** — solo indie iOS developer, Frisco Texas. Built and shipped Avenor entirely alone, zero third-party dependencies. Communicates directly, informally, often via voice-to-text. Wants tasks handled one at a time with explicit sign-off before moving forward. Blunt feedback is welcomed and expected. Does not want to be asked clarifying questions unless truly necessary — make a decision and state it. Fast-moving. Design-literate. High standards.

**Working style:**
- One task at a time, explicit sign-off before next
- Direct and informal communication
- Blunt honest feedback over diplomatic hedging
- Zero marketing budget — everything is organic/earned
- ~5 hours/week available for marketing
- Uses Claude Code (Fable model) for all coding work
- Uses claude.ai browser for complex generation and planning
- CLAUDE.md exists in project root for Claude Code context persistence

---

## WHAT AVENOR IS

**Avenor** is a premium, capture-first iOS life organizer. It unifies five mental modes — tasks, notes, goals, habits, and calendar — behind a single natural language input bar. You type like you talk, it routes and organizes automatically.

- **Bundle ID:** `com.avenor.planner` (internal target name: `Planner`)
- **Website:** `avenorus.app`
- **Social handle:** `@avenor_app` (Twitter/X, Instagram, TikTok)
- **Price:** Free (with Pro tier)
- **Platform:** iOS 17+ only
- **Requires:** No account. CloudKit sync. Zero third-party dependencies.

**Design language:** "Sophisticated Stark" — dark-first, minimal, keyboard-forward. Inspired by Linear, Vercel, and Arc Browser.

**Positioning:** "Linear for your life" / "Capture-first iOS planner"

**Tagline:** "one bar. everything organized."

**Primary personas:**
1. Design-Conscious Operators (primary)
2. Recovering Notion Refugees (secondary)
3. Apple Ecosystem Aesthetes (tertiary)

**Competitive foils:** Things 3, Todoist, Notion, Obsidian, Fantastical, Bear, Craft, Sunsama, Akiflow

---

## THE APP — FEATURES BY VERSION

### v1.0 (original launch)
- Five-tab navigation: Overview, Tasks, Notes, Goals, Calendar
- Natural language capture bar with CaptureParser
- Four themes: Stark Dark, Stark Light, Calm Earth, Liquid Glass
- SwiftData persistence, CloudKit sync
- WidgetKit extension (small/medium/large)
- Basic task/note/goal CRUD

### v1.1
- Schema validation improvements
- Beta diagnostics
- Logger hardening

### v1.2
- Interactive widgets
- Live Activity / Dynamic Island countdown
- App Group sharing improvements

### v1.3 (launched WWDC day, June 8 2026 — used WWDC hashtag wave as marketing moment)
- **Smart Rollover Engine** — overdue action debt panel
- **Recurrence-Gated Routine Streaks** with double-log protection
- **"Burn a Task" Streak Restoration**
- **Parent-Child Goal Progress Sync**
- **Kinetic Flame animations**
- **Bento-Box Calendar** with RoundedRectangle cells (not circles)
- **Advanced Recurrence Matrix** with single-letter chips (M T W T F S S)
- **Streamlined Archive Glyphs** (SF Symbols)
- 120Hz frame budget maintained, zero dependencies confirmed

### v1.4 (in planning — prompts ready for Claude Code)
Three features with full implementation prompts written:

**1. Smart Recurrence Templates**
- New `RecurrenceTemplate` enum: everyDay, weekdays, weekends, everyMWF, everyTTh, biweekly, firstOfMonth
- `RecurrenceTemplateSheet.swift` — list of templates with SF Symbol icons
- "Browse →" button above chip matrix in AddGoalSheet + AddRoutineSheet
- Template name persisted alongside RecurrenceRule for display
- Chips animate to selected state with spring on template selection

**2. Natural Language Goal Creation**
- Extend CaptureParser with new `.goal(draft: NewGoalDraft)` intent
- Detection: keyword gate + number extraction (mandatory) + unit detection + due date + title construction
- Examples: "read 300 pages by august" → goal; "save $5000 by december" → revenue goal
- `GoalUnitPickerSheet` for disambiguation when unit detection fails
- ACTIVE METRICS count increments + row springs in on success

**3. Goal Milestones**
- New `PersistedMilestone` SwiftData model (parentGoalID loose FK, sortOrder, isCompleted, completedAt)
- Added to modelContainer in PlannerApp.swift
- `MilestoneMutator` enum (add, complete, uncomplete, delete, reorder)
- complete() side effect: increments parentGoal.currentValue (triggers parent-child sync)
- UpdateGoalSheet: new Milestones section with MilestoneRow (32px progress ring, title, target, checkmark)
- GoalRowCell: "2 of 5 milestones complete" below progress bar
- Overview ACTIVE METRICS: "NEXT: [first incomplete milestone]" in meta strip

**Also in v1.4:**
- App Intents / Siri Shortcuts (ALREADY IMPLEMENTED — see below)

---

## APP INTENTS — ALREADY SHIPPED (v1.3/v1.4 boundary)

Five intents implemented in `Planner/Services/AvenorIntents.swift` (368 lines) and `Planner/Services/AvenorShortcuts.swift` (62 lines):

- `AddTaskIntent` — routes through CaptureParser, handles all 4 parse outcomes
- `GetTodaysTasksIntent` — reads App Group widget payload, falls back to store fetch if stale
- `CompleteTaskIntent` — fuzzy match → TaskMutator.complete
- `CheckGoalProgressIntent` — reads active goals, optional name parameter
- `CaptureNoteIntent` — inserts PersistedNote with title + optional body

Modified files: TaskMutator.swift (donation hook), OverviewTabView.swift (donation hook), Info.plist (NSUserActivityTypes), Planner.entitlements (com.apple.developer.siri: true)

---

## ARCHITECTURE — NON-NEGOTIABLE CONSTRAINTS

These are absolute. Never violate them in any Claude Code prompt.

**Technical:**
- Zero third-party dependencies. Ever.
- CloudKit compatibility: NO `@Attribute(.unique)`, NO `@Relationship` macros, all non-optional fields have defaults
- Service layer pattern — views NEVER mutate SwiftData directly. Always use TaskMutator, GoalMutator, etc.
- 120Hz frame budget maintained at all times
- All animation via CSS transform/opacity only (web) or SwiftUI animation (app). Never animate layout properties.
- App Group: `group.com.avenor.planner`

**UI:**
- The `>` terminal prompt in the capture bar is PRESERVED. Never remove it.
- All four themes are kept. Never reduce to fewer.
- Tab bar: Overview, Tasks, Notes, Goals, Calendar (5 tabs, this order)
- No native SwiftUI `List` or `.swipeActions` — use `StarkSwipeRow` and `GoalIncrementSwipeRow`

**Data models:**
- `PersistedTask`, `PersistedNote`, `PersistedGoal`
- parentGoalID is a loose foreign key (UUID?), not a @Relationship
- sortOrder uses negative epoch-millis for newest-first ascending sort

---

## DESIGN SYSTEM

### Colors (exact)
| Token | Value | Use |
|---|---|---|
| Canvas | #000000 / #0A0A0C | Page/app background |
| Card surface | #0E0E11 / #141417 | Elevated cards |
| Accent (mint) | #6EE7A8 | ONLY accent color |
| Text primary | white @ 90-95% | Titles |
| Text secondary | white @ 55% | Body |
| Text tertiary | white @ 30-32% | Meta/labels |
| Hairline border | white @ 6-8% | Card borders |
| Hairline 2 | white @ 16% | Active/focus borders |
| Todo accent | #6EE7A8 mint | Task row rails |
| Idea accent | #A78BFA purple | Idea row rails |
| Note accent | #94A3B8 slate | Note row rails |
| Habit accent | #FBBF24 gold | Habit/priority |

### Typography
- **Display titles** (Overview, Today, Goals): Geist 800 / Inter ExtraBold, tight letter-spacing -0.02em
- **Meta labels** (DUE TODAY, ACTIVE METRICS): Space Mono, 9-11px, ALL CAPS, letter-spacing +0.1em to +0.2em, white @ 25-28% opacity
- **Body/task titles**: Inter Medium 500, 15-17px, white @ 90%
- **Capture bar placeholder**: Space Mono, very wide tracking +0.16em, white @ 32%

### Four Themes
| Theme | Canvas | Card | Font | Scheme | Distinctive |
|---|---|---|---|---|---|
| Stark Dark | #0A0A0C solid | #101013 flat | Default | Dark | Hairline white borders, monochromatic |
| Stark Light | #F9F9F9 solid | white flat | Default | Light | Deep slate text, black borders |
| Calm Earth | cream #F5F0E8 solid | lighter cream flat | Rounded | Light | Olive accents, 20pt radius, softer |
| Liquid Glass | lavender→teal gradient | ultraThinMaterial | Rounded | Dark | 22pt radius, specular top edge, plusLighter blend |

### Task Row Anatomy (EXACT — important for phone mockup accuracy)
- 2px colored left rail flush to left edge
- Card background: #0E0E11, 1px border white @ 6%, rounded ~11px
- Meta strip above title: "TODO · DUE TODAY AT 3:00 PM" — Space Mono 9px, ALL CAPS, white @ 25%
- Title: Inter 500, 15-17px, white @ 90%
- Left: small square checkbox (unfilled)
- Right: chevron
- No native swipeActions — custom StarkSwipeRow handles swipe gestures

### CaptureParser Rules (web port also uses these)
Priority order:
1. Trailing `!`, `!!`, `!!!` → P3, P2, P1 (whitespace-gated)
2. `#hashtag` → `.idea(title, tag, priority)`
3. Time token (`@5pm`, `today`, `tomorrow`, `tonight`, `in N days`, day-of-week) → `.todo(title, dueDate, priority)`
4. Recurrence (`every night`, `every monday`, `weekdays`, `daily`) → `.habit(title, recurrence)`
5. >3 words, no tokens → `.note(title: firstSentence, body: rest)`
6. Fallback → `.todo(title, dueDate: nil, priority: nil)`

---

## THE WEBSITE — avenorus.app

**Location:** `~/Avenor/.claude/worktrees/avenor-website/website/`
**Branch:** `worktree-avenor-website`
**Tech:** 5 standalone vanilla HTML files. No build step. No npm. No frameworks.

### Pages
- `index.html` — Home / hero with live parser demo
- `features.html` — Interactive feature exhibits + sticky phone mockup
- `themes.html` — Live theme switcher (entire page morphs)
- `download.html` — App Store CTA
- `about.html` — Founder letter + decisions

### What's Built (as of latest session)
- **Live parser playground** — full-screen overlay, real-time token highlighting (mint=time, purple=hashtag, gold=priority), three columns TASKS/IDEAS/NOTES, spring-physics card entries, suggestion chips
- **Toast + Intelligence Cascade** — every capture commit fires iOS-style toast + SVG branch cascade showing "notification queued", "widget refreshed", "CloudKit synced", etc. Branches change based on capture type.
- **Site-wide command bar** (`/` or `⌘K`) — navigates pages, switches themes, files captures. The site literally becomes the product. Fable invented this on its own — it's the standout feature.
- **Sticky phone mockup** on features.html — screen crossfades through app screens as you scroll, scroll-velocity tilt
- **Keyboard shortcuts overlay** (`?`) — all shortcuts documented
- **Magnetic hover** — 120px proximity physics on nav/CTAs
- **Noise grain** — SVG feTurbulence overlay, film-like
- **Custom cursor** — white dot + ring, lerped physics
- **Theme switcher** — themes.html lets user switch and entire page remorphs including phone mockup using exact ThemePalette.swift token values

### Latest Prompt (IN PROGRESS — run in existing session)
A major UI overhaul prompt was written covering:
1. Phone screen accuracy fix (rebuild all 5 screens to match exact app anatomy)
2. Parser simplification (one entry point — the hero bar. Remove "Try the Parser →" button. Command bar stays as power-user easter egg)
3. Full cinematic UI overhaul — enormous typography (96-140px), asymmetric layouts, 200px+ breathing room, film scan line, drifting particles, editorial sections, dramatic scroll reveals

**Status: This prompt has been written but may not have been run yet. Check the worktree HTML files to see current state before running.**

### Website Design Direction
- NOT: dense, technical, three equal cards, purple gradients, centered hero
- YES: cinematic, editorial, expressive, bold, unexpected layouts, scale contrast
- Typography: enormous headlines (-0.05em tracking, 0.9 line-height), Space Mono for all meta (whisper-level opacity)
- Atmosphere: noise grain 5-6%, film scan line, drifting particles, one cinematic moment per page
- Motion: blur-to-sharp reveals (blur(4px)→0 + translateY 30→0), 60fps always, prefers-reduced-motion respected

---

## MARKETING — COMPLETE STRATEGY

### Positioning
**Primary:** "Capture-First Planner" — most ownable, most defensible long-term
**Secondary:** "Linear for your life" — resonates with design-literate audience
**Avoid:** "Anti-System Planner" — most differentiated but least defensible

### Channels (priority order)
1. **Twitter/X** — primary. Build-in-public, design/productivity audience
2. **TikTok/Reels** — primary. App demos, visual storytelling
3. **Instagram** — secondary. Aesthetic screenshots, theme showcases
4. Threads, Bluesky, Mastodon — explicitly DEPRIORITIZED. Skip.

### Content Pillars
- Build-in-public (decisions, tradeoffs, what shipped)
- Feature deep-dives (show the intelligence, not just the UI)
- Aesthetic/design (theme showcases, motion details)
- User stories (the capture bar solving real problems)
- Anti-patterns (what Avenor deliberately doesn't do)

### Social Copy Style
- Lowercase always
- No exclamation marks in product copy
- No "powerful", "seamless", "supercharge"
- Short sentences. Real thoughts. Founder voice.

### Launch Channels (pending)
- ProductHunt submission
- Hacker News (Show HN)
- Relevant subreddits (r/productivity, r/ios, r/indiedev)
- Layers.is, Mobbin, Dribbble
- Apple Featuring submissions
- Indie newsletter outreach

### WWDC Launch Posts (shipped June 8 2026)
X post sent:
```
shipped avenor 1.3 on WWDC day.
smart rollover, habit streaks that actually work. bento calendar. goal sync.
everything you need in one place.
avenorus.app
#WWDC26 #iOS #productivity
```

### App Store Optimization
- Review prompts tied to user WIN moments (streak milestones, goal completion), NOT session counts
- Content strategy grounded in aesthetic identity, not generic productivity content

### Video/Ad Assets
- Full Meshy AI prompt written for 30-second vertical ad (9:16, 6 scenes, exact color specs, animation curves, component anatomy)
- Condensed 800-char Meshy prompt also available

### In-App Viral Loop (planned)
- "Share my widget" export feature — screenshot of personalized widget with Avenor branding
- Future: year-in-review card feature

---

## TOOLS & WORKFLOW

| Tool | Purpose |
|---|---|
| Claude Code (Fable model) | All feature implementation, website coding, animation work |
| claude.ai browser | Planning, prompts, marketing strategy, this document |
| CLAUDE.md | Persists architecture context across Claude Code sessions |
| Buffer | Social media scheduling |
| Typefully | Twitter/X thread drafting |
| Xcode | iOS development |
| SwiftUI + SwiftData + iOS 17+ | App tech stack |
| WidgetKit + CloudKit | Widget + sync |
| SF Symbols | All icons |

### Claude Code Session Tips
- Always start with a fresh read of CLAUDE.md and ARCHITECTURE.md
- Give Fable creative freedom on visual decisions — don't over-specify
- For animation: give direction and references, not pixel specs
- For UI: "surprise me" unlocks better output than exact specs
- Skills can be added to `~/.claude/CLAUDE.md` for global rules across all sessions
- Skills can also be placed in `.claude/skills/` and referenced from CLAUDE.md

### Pro Plan Usage
- ~$20/month Claude Pro
- 2-3 sessions/day hitting the 5-hour limit
- API would cost ~$234/month — not worth it for current usage
- VS Code Claude integration uses Haiku 4.5 only — use browser for complex generation

---

## PENDING ACTION ITEMS (as of June 2026)

### App (v1.4)
- [ ] Run Smart Recurrence Templates prompt in Claude Code
- [ ] Run Natural Language Goal Creation prompt in Claude Code
- [ ] Run Goal Milestones prompt in Claude Code
- [ ] Run UI refinement prompt (7 design changes from audit)
- [ ] Fix widget tasks not showing (WidgetSnapshotPublisher → App Group write issue — suspected)
- [ ] Fix widget CFBundleVersion 3-vs-2 mismatch (minor)
- [ ] Test App Intents: "Hey Siri, add Avenor task" + Shortcuts app + Spotlight

### Website
- [ ] Run the major UI overhaul prompt (cinematic redesign + phone screen fix + parser simplification)
- [ ] Update App Store badge link (TODO comment in download.html — needs real listing URL)
- [ ] Deploy website to avenorus.app when ready

### Marketing
- [ ] ProductHunt submission
- [ ] Hacker News Show HN post
- [ ] Relevant subreddits
- [ ] Layers.is, Mobbin, Dribbble submissions
- [ ] Apple Featuring submission
- [ ] Indie newsletter outreach
- [ ] Record cinematic showcase animation as MP4 (screen record HTML + add music from Artlist.io or Epidemic Sound, "minimal ambient" 70-90 BPM, Nils Frahm/Bonobo/Tycho energy)

---

## KEY DECISIONS & PRINCIPLES (on the record)

- **Capture-first** is the most ownable angle. Defend it.
- **Zero dependencies** is a technical and marketing differentiator — mention it.
- **The `>` prompt** in the capture bar stays. It's iconic.
- **All four themes** stay. They're a differentiator, not dilution.
- **No native SwiftUI List** — StarkSwipeRow is the custom gesture primitive.
- **CloudKit-safe modeling** means loose foreign keys (UUID?) not @Relationship.
- **CLAUDE.md** is the established pattern for codebase context persistence.
- **Animation prompts** should give Claude Code creative freedom, not pixel specs.
- **Social:** Twitter/X + TikTok primary. Threads/Bluesky/Mastodon skipped.
- **Website command bar** (`/`) is the "one major thing" — the site becomes the product.
- **Parser entry points simplified** — one way in (hero bar). Command bar is power-user easter egg.

---

## FILES & LOCATIONS

```
~/Avenor/
├── Planner.xcodeproj
├── CLAUDE.md                          ← Claude Code context (always read first)
├── ARCHITECTURE.md                    ← Full architectural source of truth
├── Planner/
│   ├── Models/
│   │   ├── PersistentModels.swift     ← PersistedTask, PersistedNote, PersistedGoal
│   │   └── Models.swift               ← Enums, drafts, theme tokens
│   ├── Services/
│   │   ├── CaptureParser.swift        ← Natural language routing
│   │   ├── TaskMutator.swift          ← Task mutations + side effects
│   │   ├── GoalMutator.swift          ← Goal mutations
│   │   ├── NotificationManager.swift  ← UNCalendarNotificationTrigger
│   │   ├── WidgetSnapshotPublisher.swift
│   │   ├── AvenorIntents.swift        ← App Intents (5 intents)
│   │   └── AvenorShortcuts.swift      ← Siri Shortcuts
│   ├── ViewModels/
│   │   └── LocalStore.swift           ← ThemeStore (@Observable), Preferences
│   ├── Pages/                         ← Tab views
│   ├── DesignSystem/
│   │   ├── DesignTokens.swift         ← Physical token layer
│   │   └── ThemePalette.swift         ← Semantic token layer (make(for:))
│   └── PlannerApp.swift               ← App entry, lifecycle hooks
├── AvenorWidget/                      ← WidgetKit extension (self-contained)
└── .claude/
    └── worktrees/
        └── avenor-website/
            └── website/               ← 5-page HTML site
                ├── index.html
                ├── features.html
                ├── themes.html
                ├── download.html
                └── about.html
```

---

*This document is the single source of truth for Avenor context. If something conflicts with ARCHITECTURE.md, trust ARCHITECTURE.md for technical details. If something conflicts with CLAUDE.md, trust CLAUDE.md for coding conventions.*
