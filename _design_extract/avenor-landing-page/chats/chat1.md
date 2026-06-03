# Avenor iOS Landing Page

_Started 2026-05-27 20:59 UTC_

---

## User

Create my landing page for Avenor - an iOS App. Refer to ARCHITECTURE.md for Context.

## Assistant

_[tool: read_file]_

_[tool: list_files]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: update_todos]_

I have everything I need. The user's brief is highly detailed and there's an existing marketing kit I can fork. Let me plan: this is a hi-fi landing page (not a wireframe — the brief is too specific for low-fi), so I'll follow the brief's structure precisely while honoring the design system's voice and tokens.

Key adjustments vs. the existing kit:
- Brief calls for **vertical-stacked feature cards with iPhone screenshots inside each** (vs. the kit's 3-column triplet)
- Brief specifies different copy ("Capture-first iOS planner." headline, etc.) — I'll honor the brief literally
- Three different phone mockups (capture parsing, overview tab, theme switcher)

_[tool: copy_files]_

_[tool: write_file]_

Now I'll build the landing page. Single file with embedded styles + a touch of JS for the live capture-parse demo.

_[tool: done]_

_[tool: fork_verifier_agent]_

Built **Landing Page.html** following the brief structure, voiced and styled against the Avenor design system:

- **Sticky nav** — wordmark + white "Get Early Access" button, backdrop blur kicks in on scroll
- **Hero** — centered phone (capture bar parsing `gym tomorrow @7am !!` with date/time/priority tokens highlighted in semantic accent colors), then headline / subhead / email card
- **Social proof strip** — italic Instrument Serif line, hairline-bordered
- **Three feature cards** stacked vertically, each 40px-padded with copy left + a distinct mini iPhone right:
  1. *Capture* → parser demo with examples
  2. *Unify* → Command Center overview (tasks, goals progress, brain dumps)
  3. *Feel* → theme switcher showing all four palettes including the Liquid Glass gradient
- **Email section** + minimal three-column footer

Both email forms are live (validate → confirm state). Hit me with tweaks — variations on the phone framing, alternate hero compositions, or copy iterations.

## User

Verifier agent check completed

## Assistant

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: done]_

_[tool: fork_verifier_agent]_

Fixed the cascading center alignment on the hero phone screen and locked the capture bar to a single line. Waiting on verifier's screenshot to confirm.

## User

Verifier agent check completed

## Assistant

Verifier confirmed the fix. Hero phone screen content is left-aligned and the capture bar stays on one line.

## User

<system-info comment="Only acknowledge these if relevant">
Project title is now "Avenor Landing Page"
Project currently has 3 file(s)
User is viewing file: Landing Page.html
Current date is now May 27, 2026
</system-info>

<pasted_text name="Pasted text (339 lines)">
Build a multi-page marketing website for Avenor, a capture-first iOS planner. The design language is "Sophisticated Stark" — think Linear.app meets Apple product pages. Dark, minimal, confident, no fluff.

Global Design System
Colors:

Canvas: #0A0A0C
Card surface: #101013
Card border: #222225 (1px hairline)
Text primary: #FFFFFF
Text secondary: #AAAAAA
Muted: #666666
Accent rail colors: Todo #4A9EFF, Idea #FFB347, Reminder #FF6B6B, Note #888888

Typography:

Headlines: SF Pro Display, bold, letter-spacing -0.02em
Body: SF Pro Text, regular, letter-spacing 0
Monospace labels: SF Mono, 11px uppercase tracked wide (used for eyebrow labels like CAPTURE · TASKS · GOALS)
No decorative fonts

Components:

Cards: #101013 background, 1px #222225 border, 12px border radius, 40px inner padding
Buttons (primary): white background, black text, 6px radius, 14px bold
Buttons (ghost): transparent, 1px white border, white text
iPhone mockup: flat-on (no perspective tilt), natural black finish, 0 40px 80px rgba(0,0,0,0.6) drop shadow
2pt left accent rail on task rows (matches task type color)
Hairline dividers between sections: 1px #222225

Motion principles:

Fade + translate-up on scroll (elements enter from 20px below, opacity 0 → 1, 400ms ease-out)
No bounce, no spring, no overshoot — everything is controlled and precise
Hover states: opacity 0.7 → 1 transition, 150ms
Interactive demo animations: typewriter effect at 80ms per character

Layout:

Max content width: 1100px, centered
Section padding: 120px top/bottom
Mobile: single column, 24px horizontal padding
Sticky nav: #0A0A0C with 1px #222225 bottom border, 60px height, backdrop blur


Navigation Bar (sticky, all pages)
Left: Avenor wordmark — SF Pro Display, 18px, bold, white
Center: Navigation links — Home · Capture · Features · Themes · About — SF Pro Text, 14px, #AAAAAA, hover → #FFFFFF, active page → #FFFFFF
Right: Get Early Access button — white background, black text, 6px radius, 14px bold

PAGE 1: Home
Section 1 — Hero

Full viewport height, content vertically and horizontally centered
Eyebrow: COMING TO THE APP STORE — SF Mono, 11px, #666666, tracked wide, uppercase
Headline: Capture everything. — SF Pro Display, 72px, bold, white, letter-spacing -0.03em
Subheadline: The iOS planner Things 3 should've become. — SF Pro Text, 22px, #AAAAAA
CTA row: Email input + Notify me button side by side inside a dark card (#101013, 1px #222225 border, 8px radius). Input placeholder: your@email.com. Button: white bg, black text.
Below CTA: No spam. One email when we launch. — 12px, #666666
Background detail: extremely subtle radial gradient centered behind headline — rgba(255,255,255,0.02) — barely visible, just adds depth

Section 2 — Live Capture Demo (THE MAIN HERO FEATURE)

Eyebrow: THE CAPTURE BAR
Headline: Type how you think. — 48px bold white
Subheadline: Avenor reads your intent. No tapping through menus. — 18px #AAAAAA
The interactive demo component (full-width dark card, 12px radius, 60px padding):

Render a working capture bar UI that matches the app exactly:

Left: > monospace prompt in #AAAAAA
Right: blinking cursor
Font: SF Mono, 16px, white
Placeholder: CAPTURE INTENT… in #444444 uppercase


Below the bar: a parsed result card (hidden until input is detected)

Shows the parsed task with: 2pt accent rail, task type badge, title, due date chip


Three pre-built demo buttons below the bar (ghost pill buttons, #222225 border):

gym tomorrow @7am !!
#UI new onboarding flow
finish pitch deck in 3 days


Behavior: when user clicks a demo button OR types their own text:

Text types itself into the bar character by character (80ms per char, typewriter effect)
A 600ms pause after the last character
The parsed result card slides up from below (translate-Y 20px → 0, opacity 0 → 1, 300ms ease-out)
The card shows the parsed output with labels:

gym tomorrow @7am !! → Type: REMINDER (red rail) · Due: Tomorrow, 7:00 AM · Priority: P2 · Title: Gym
#UI new onboarding flow → Type: IDEA (orange rail) · Tag: #UI · Title: New onboarding flow
finish pitch deck in 3 days → Type: TODO (blue rail) · Due: In 3 days, 9:00 AM · Title: Finish pitch deck


Each label animates in separately, staggered 80ms apart (type → due → priority → title)


Below the parsed card: annotation labels with small arrows pointing to each part of the result:

Arrow pointing to rail → Task type detected automatically
Arrow pointing to due date → Natural language date parsed
Arrow pointing to priority → !! = Priority 2


Below the demo card: three columns explaining the three parse paths:

Column 1: #hashtag icon · IDEA CAPTURE · Add a # and Avenor files it as an idea with a tag
Column 2: clock icon · TIME PARSING · @5pm, tomorrow, in 3 days — all understood
Column 3: !! icon · PRIORITY FLAGGING · !, !!, !!! map to P3, P2, P1





Section 3 — Unification Claim

Eyebrow: ONE APP
Headline: Stop juggling five apps. — 48px bold white
Subheadline: Tasks, notes, goals, and calendar. All behind one bar. — 18px #AAAAAA
Five app icons dissolving into one Avenor icon — animated on scroll entry
Four feature cards in a 2×2 grid (each dark card, 12px radius, 40px padding):

Card 1: TASKS eyebrow · Capture, prioritize, complete. headline · iPhone screenshot of Tasks tab
Card 2: NOTES eyebrow · Brain dumps that stay organized. headline · iPhone screenshot of Notes tab
Card 3: GOALS eyebrow · Set targets. Track progress. headline · iPhone screenshot of Goals tab
Card 4: CALENDAR eyebrow · See your week. Not your overwhelm. headline · iPhone screenshot of Calendar tab



Section 4 — Theme Teaser

Eyebrow: FOUR THEMES
Headline: One feeling, four faces. — 48px bold white
Four iPhone mockups side by side, each showing the same view in a different theme:

Stark Dark · Stark Light · Calm Earth · Liquid Glass


Each mockup has a label below: theme name in 12px SF Mono uppercase #AAAAAA
On hover over each mockup: scale 1.02, shadow intensifies — 200ms ease
CTA below: Explore themes → ghost button

Section 5 — Email Capture

Centered, clean
Headline: Be first to know when we launch. — 32px bold white
Email card (same as hero)
No spam. Just a single launch email. — 12px #666666

Footer

1px #222225 top border
Left: © 2026 Avenor
Center: @avenor_app Twitter · Instagram
Right: avenor.app
All 12px #666666


PAGE 2: Capture
This page is dedicated entirely to explaining the capture bar and parsing engine. It's a technical love letter to the feature.
Section 1 — Hero

Headline: The capture bar. — 64px bold white
Subheadline: The front door of Avenor. One line. Every intention. — 20px #AAAAAA
Full-width render of the capture bar at large scale (as if zoomed in from the app)
> prompt on the left, CAPTURE INTENT… placeholder, blinking cursor

Section 2 — How It Works (step-by-step scroll)
Three cards in a vertical stack, each entering on scroll:
Card 1 — You type naturally

Left: large SF Mono input showing gym tomorrow @7am !! with cursor
Right: annotation labels:

gym → highlighted blue → The task title
tomorrow → highlighted green → Day keyword → resolves to next calendar day at 9AM
@7am → highlighted green → Explicit time override → 7:00 AM
!! → highlighted orange → Double bang → Priority 2



Card 2 — Avenor parses intent

Animated flowchart (simple, linear, no bubbles — just lines and labels):

Input text → Does it have #? → Yes → IDEA + tag / No → Does it have @time or day keyword? → Yes → TODO or REMINDER + dueDate / No → Long text (>3 words)? → Yes → NOTE / No → TODO (no date)


Style: lines in #222225, labels in #AAAAAA SF Mono 12px, decision nodes as small white squares

Card 3 — Result appears instantly

The parsed task row exactly as it would appear in the app:

2pt red accent rail (reminder type)
REMINDER · DUE TOMORROW 7:00 AM · P2 — SF Mono 11px #AAAAAA
Gym — SF Pro Text 16px white
Checkbox glyph on right



Section 3 — Parse Reference Table
Full-width dark card. A clean table showing all supported parse patterns:
Input patternWhat Avenor createsExample#tag titleIdea with tag#design new icon set@5pm titleTodo due today at 5pmcall mom @5pmtomorrow titleTodo due tomorrow 9amdentist tomorrowtonight titleTodo due tonight 8pmreview PR tonightin N days titleTodo due in N daystaxes in 4 daysnext monday titleTodo due next Mondaymeeting prep next mondaytitle !!!Priority 1 (highest)ship hotfix !!!title !!Priority 2reply to investor !!title !Priority 3water plants !Long sentenceNoteHad a great call with the team today about Q3
Table style: #101013 background, #222225 row borders, SF Mono 12px for patterns, SF Pro Text 14px for descriptions
Section 4 — Try It Yourself

Same interactive demo component as Home page Section 2
Add a free-text input mode so users can type their own string and see it parsed live
Below: This is exactly how the app works. No magic. Just intent. — 14px #666666 centered


PAGE 3: Features
Layout: alternating left-right feature blocks
Each block: full-width section, 120px padding. iPhone mockup on one side, text on the other. They alternate left/right.
Feature 1 — Tasks (mockup right)

Eyebrow: TASKS
Headline: Your to-do list, without the ceremony.
Body: Swipe to complete. Swipe to delete. Filter by type. Link tasks to goals. No folders, no projects, no setup.
iPhone mockup: Tasks tab, dark theme, showing a SwipeRow in mid-swipe

Feature 2 — Notes (mockup left)

Eyebrow: NOTES
Headline: Brain dumps that stay put.
Body: Markdown rendered on the fly. Write in raw syntax, read in clean prose. Tap to edit, tap again to read.
iPhone mockup: Notes tab showing a rendered markdown note

Feature 3 — Goals (mockup right)

Eyebrow: GOALS
Headline: Measure what matters.
Body: Set a target. Pick a unit. Swipe to increment. Watch the progress bar move. Link tasks to goals so everything connects.
iPhone mockup: Goals tab showing a goal row with a progress rail at 60%

Feature 4 — Calendar (mockup left)

Eyebrow: CALENDAR
Headline: See your week without the dread.
Body: A month grid with colored dots for each task type. Tap a day, see your tasks. No subscriptions, no sync headaches.
iPhone mockup: Calendar tab showing month grid with colored dots

Feature 5 — Widgets (mockup right)

Eyebrow: WIDGETS
Headline: Your day on your lock screen.
Body: Small, medium, and large widgets. Updates every 15 minutes. Tap to open the capture bar directly from your home screen.
iPhone mockup: home screen showing large Avenor widget


PAGE 4: Themes
Section 1 — Hero

Headline: Four themes. One feeling. — 64px bold white
Subheadline: Switch anytime. The whole app responds instantly. — 20px #AAAAAA

Section 2 — Theme Showcase (one section per theme)
Theme 1 — Stark Dark

Full-width dark card
Left: large iPhone mockup in Stark Dark
Right: theme details

Name: STARK DARK — SF Mono 11px #AAAAAA
Description: The default. Near-black canvas, hairline white borders, monochromatic accent. Designed to disappear and let your content lead.
Color swatches: three circles — #0A0A0C, #101013, #FFFFFF



Theme 2 — Stark Light

Same layout, flipped
Light version — #F9F9F9 canvas, white cards, deep slate text
Description: Same restraint, inverted. For those who work in daylight.

Theme 3 — Calm Earth

Same layout
Cream canvas, olive accents, rounded font
Description: Softer. Warmer. Rounded corners, olive tones, and a font that breathes. For when the day calls for something quieter.

Theme 4 — Liquid Glass

Same layout — make this one feel premium
Lavender-to-teal gradient canvas, ultra-thin material cards, specular top-edge highlight
Description: The showpiece. Frosted glass cards over a gradient canvas. A specular edge that catches light. This one's for the lock screen.
Add a subtle animated shimmer on the card border (the specular gradient stroke animating left to right slowly, looping)

Section 3 — Theme Switcher Demo

Single iPhone mockup, centered
Four theme pill buttons below it: Dark · Light · Calm Earth · Liquid Glass
Clicking a pill switches the mockup's theme with a 300ms crossfade
The canvas background of the section itself also shifts subtly to match the active theme


PAGE 5: About
Section 1 — The Origin

Headline: Built by one person. For one person at a time.
Body (3 short paragraphs, 16px #AAAAAA, max-width 640px, centered):

Para 1: Avenor started as frustration. Five apps open. None of them talking to each other. A task in Reminders, a note in Bear, a goal in Notion nobody opened, a calendar in Fantastical that didn't know about any of it.
Para 2: The capture bar came first. One line of text that could become anything — a task, a note, an idea, a reminder — depending on how you typed it. That felt right. The rest of the app grew around that bar.
Para 3: Avenor is a solo project. No team, no investors, no roadmap driven by enterprise feature requests. Just one app, built carefully, for people who care about how their tools feel.



Section 2 — The Principles
Three dark cards in a row:

Card 1: CAPTURE FIRST · The bar is the app. Everything else is a consequence of what you've already typed.
Card 2: NO SETUP TAX · You don't need a system. You need a place to type. Avenor handles the rest.
Card 3: TASTE AS FUNCTION · How an app feels affects how often you open it. Design isn't decoration here — it's the product.

Section 3 — Contact / Press

Press inquiries, feedback, or just want to say something?
Email link: hello@avenor.app — white, underline on hover
Social links: Twitter @avenor_app · Instagram @avenor_app


Animation Summary (implement across all pages)

Scroll entry: every section fades in + translates up 20px → 0 on entering viewport. Stagger child elements 80ms apart.
Capture bar typewriter: 80ms per character, blinking cursor, 600ms pause before parse result appears
Parse result reveal: translate-Y 20px → 0, opacity 0 → 1, 300ms ease-out. Child labels stagger 80ms.
Theme switcher crossfade: 300ms opacity crossfade between mockup states
Specular shimmer (Liquid Glass card border): gradient animates left → right on a 3s loop, subtle
Feature block entrance: mockup slides in from the side (60px), text from opposite side, 400ms ease-out
Hover on cards: scale 1.01, shadow deepens, 200ms ease
Button hover: opacity 0.8, 150ms
No bounce. No spring. Everything is deliberate.
</pasted_text>

<!-- The user explicitly selected the following skills for this project, as attachments to their message. These are not optional context — they define how you work. Use them. -->
<attached-skill name="Avenor Design System (design system)">
[Design System] This project uses the **Avenor Design System** design system. This is a binding choice for visual style — every visual must follow it. Don't invent colors, type, spacing, or components not grounded here.

Scope: the design system is a visual style reference only. Its guide may describe example products, brands, or people that are unrelated to the user and unrelated to the subject of this conversation. Never treat anything in the design system as a fact about the user, their work, or the topic they asked about.

    Explore it to find what you need:
    - Always copy out the fonts and colors you need
    - For prototypes and designs, always copy out any relevant components
    - If the design system contains existing mocks of products, and you were asked to design or prototype something similar, copy and fork those mocks to start your design. This helps you make high-quality designs.

    Explore it quickly to find relevant UI kits (e.g. mocks of existing products you can copy and fork)

Full system at `/projects/c1a36601-f108-47e2-983d-b4f9f7054cb7/`. Its guide is reproduced below so you don't need to fetch it:

<design-system-guide>
# Avenor Design System

**Avenor** is a capture-first iOS planner that unifies tasks, notes, goals,
and calendar behind one aesthetic vocabulary called **"Sophisticated Stark"**
— editorial, near-black, hairline-bordered, monochromatic. A single-user app
shipping at launch with four themes (Stark Dark, Stark Light, Calm Earth,
Liquid Glass) and a companion marketing site at **avenor.app**.

This folder is the canonical design system for both surfaces (the iOS app
and the marketing site). Both share one token vocabulary so the marketing
hero and the actual app feel like the same product.

---

## Sources used to build this system

- **`DesignSystem/DesignTokens.swift`** — local mounted folder; the iOS
  app's namespaced token enum (Spacing, Radius, Stroke, Accent, Surface,
  Typography, Tracking, Motion, Background). Source of truth for raw values.
- **`DesignSystem/ThemePalette.swift`** — local mounted folder; the
  semantic token layer that maps each of the four themes to a `ThemePalette`
  struct. Source of truth for theme-aware semantic tokens.
- **`uploads/Avenor_Logo.png`** — provided logo (dark glyph on white,
  for use on light backgrounds).
- **`uploads/Avenor_Logo_Dark.png`** — provided logo (white glyph on dark,
  for the production Stark Dark aesthetic).
- Inline brief from the project owner specifying voice rules ("No marketing
  fluff. No emoji. No exclamation points except inside the app demo itself.
  Every word earns its place. Sentences are short and declarative.")
  and landing-page section list (sticky nav, hero with iPhone mockup +
  capture bar demo, three feature blocks CAPTURE / UNIFY / FEEL, email
  capture, minimal footer).

Reference brands explicitly named in the brief: **Linear**, **Vercel**,
**Arc Browser**, **Things 3**. These set the standard for restraint,
density, and how monochrome surfaces can carry an entire product story.

---

## CONTENT FUNDAMENTALS

Avenor's voice is **stark, declarative, and short**. Copy is treated like
an editorial typeface: the less it tries to do, the more it carries.

### Tone

- **No marketing fluff.** "The best planner you'll ever use" → never.
  "Capture. Then keep going." → yes.
- **No emoji.** Not in app strings, not in marketing, not in social.
- **No exclamation points** anywhere except inside the app demo itself
  (where users naturally type them into their own captures).
- **Short, declarative sentences.** Subject. Verb. End. Run-ons and
  conditional clauses are a smell.
- **Every word earns its place.** If a sentence still reads with a word
  removed, remove the word.

### Casing

- **Section labels and micro labels:** `UPPERCASE`, tracked +0.073em.
  Example: `CAPTURE`, `TODAY`, `INBOX`.
- **Section heads and headlines:** Sentence case, no terminal period.
  Example: `Capture before it slips`, not `Capture Before It Slips.`
- **Buttons:** Sentence case, single verb when possible. `Get early access`,
  not `Get Early Access` or `GET EARLY ACCESS`.
- **Display headlines (marketing hero):** Sentence case, tight tracking
  (`-0.02em`), often two short lines stacked rather than one long line.

### Pronouns

- **Address the reader as "you"**, sparingly. Most copy doesn't need a
  pronoun at all.
- **Avoid "we"** in product copy — the system speaks, not the company.
- The brand voice **never refers to itself by name** in body copy except
  where unavoidable. The product is the noun in the sentence, not the
  subject of it.

### Vibe

Imagine the print edition of a quiet design quarterly. The opposite of
SaaS-confetti. The reader is intelligent, busy, and tired of being sold to.

### Concrete examples

| ✗ Don't                                       | ✓ Do                          |
|-----------------------------------------------|-------------------------------|
| The ultimate productivity companion!          | A planner, finished.          |
| 🚀 Capture your ideas instantly!              | Capture before it slips.      |
| We help you stay organized 🎯                 | One inbox. Four lenses.       |
| Click here to learn more →                    | Get early access              |
| Streamline your workflow with AI-powered…     | No AI. No bloat. No syncing.  |
| Welcome back! Let's tackle your day 💪        | Today.                        |

### Section copy in practice (from the landing page)

- **Hero headline:** *Capture. Then keep going.*
- **Hero sub:** *A planner that unifies tasks, notes, goals, and calendar.
  Built for one person.*
- **Feature labels:** `CAPTURE` · `UNIFY` · `FEEL`
- **Email field placeholder:** *you@domain.com*
- **Email submit:** *Request access*
- **Footer rule:** *© Avenor. Made for one.*

---

## VISUAL FOUNDATIONS

### The single rule

**Separation comes from precise tonal steps and hairline borders, never
from translucency or shadow.** This is the load-bearing principle of the
Stark Dark aesthetic. Internalize it and most other rules follow.

### Color

- **Canvas is pitch-black**, not pure black: `#0A0A0C`. The 0.039 lift
  in each channel reads as "considered" rather than "default terminal."
- **Cards are darker than nothing**, paradoxically — the card fill
  `#101013` reads as a *darker* region than the surrounding canvas because
  it's bordered by a hairline white at 6% opacity. This inversion is what
  gives Linear-style products their weight.
- **Three surface tiers:** canvas (`#0A0A0C`) → card (`#101013`) → card
  elevated (`#141417`). That's it. Don't invent a fourth.
- **Text is white but rarely full white.** Body copy is `rgba(255,255,255,
  0.92)`. Secondary is `0.55`. Tertiary is `0.32`. The pure `#FFFFFF` is
  reserved for the display headline and the accent role.
- **Semantic accents are desaturated and clinical** — clinical mint
  `#9ED6B5` for todos, clay amber `#DBA86B` for reminders, pale slate-lilac
  `#BCB7D6` for ideas, cold slate blue `#8FADD1` for notes. They identify
  task type. They never decorate.

### Type

- **SF Pro Display for headlines, SF Pro Text for body.** On the web,
  Apple's system stack is loaded first; **Inter** is the metrically
  compatible fallback for non-Apple platforms.
- **Tight tracking on display copy** (`-0.02em` at 32px and above).
  Open tracking on micro labels (`+0.073em` at 11px, uppercased).
- **Editorial scale, not a SaaS scale:** Display 32 / Title 22 / Headline 16
  / Body 15 / Caption 13 / Micro 11. Six steps. Don't add a seventh.
- **Bold weights are reserved.** Body is regular (400). Headlines and
  micro labels are semibold (600). Only the display headline goes bold (700).

### Spacing

A coarse, opinionated grid:
- **18px card inset** (the inside of every card).
- **14px card content gap.**
- **16px stack** between sibling cards.
- **28px stack-large** between sections inside a long page.
- **20px page horizontal** outer gutter.
- The 4-pt baseline grid is implicit but rarely needs to be invoked
  literally — pick from the scale above.

### Backgrounds

- **No imagery.** No textures. No grain.
- **No gradients** anywhere except the Liquid Glass theme (which is a
  single lavender→teal diagonal: `#9480DC → #738CCC → #4D94BD`,
  `135deg`).
- **No repeating patterns.** The canvas is a single flat color.
- **Full-bleed black** is the default page background. Sections are
  separated by spacing, not by color shifts.

### Borders, strokes, hairlines

- **Hairlines do the work that backgrounds usually do.** A 1px white
  stroke at 6% opacity (`rgba(255,255,255,0.06)`) separates every card,
  row, field, and chip from its surroundings.
- **Three stroke weights of opacity**: hairline 6% (default), prominent
  10% (selected / focus rings), interactive 16% (hover and active).
- **No double borders.** A card inside a card uses elevated fill, not a
  second hairline.

### Shadows

- **Drop shadows are subtle and used only under iPhone mockups.**
  Marketing hero: `0 32px 80px -16px rgba(0,0,0,0.65),
  0 12px 32px -8px rgba(0,0,0,0.45)`. Two layers, both warm-black, both
  offset downward. Nothing else in the system has a shadow.
- **No inner glows.** No neumorphism. No "frosted" treatments outside
  Liquid Glass.

### Corner radii

- **Capsule (`999px`)** — chips, badges, the email submit button.
- **8px** — small controls (single-line inputs, segmented controls).
- **12px** — medium (rows nested inside cards).
- **16px** — card (the primary surface).
- **24px** — sheet (only the iOS sheet/modal — does not appear on web).
- The Calm Earth theme nudges card radius up to 20px; Liquid Glass to 22px.
  Stark Dark and Light stay at 16.

### Cards

- Fill: `#101013` (card) or `#141417` (card-elevated for nested rows).
- Border: 1px `rgba(255,255,255,0.06)`.
- Radius: 16px.
- Inset padding: 18px.
- **No shadow** unless it contains an iPhone mockup.
- **No rounded-corner-with-colored-left-border accents.** Ever.

### Layout

- **Marketing site is a single column of stacked sections**, max-width
  capped at ~1100–1200px, gutter 20px (mobile) / 40px (desktop).
- **Sticky nav** at the top, hairline-bottomed, transparent canvas
  underneath until you scroll, then a subtle backdrop blur kicks in.
- **Section rhythm** is hero → feature triplet (CAPTURE / UNIFY / FEEL)
  → theme showcase → email capture → footer. Sections don't compete
  with each other for visual weight.

### Animation & easing

- **Two springs**, lifted from the iOS app:
  - **Snappy** — `220ms cubic-bezier(0.32, 0.72, 0.32, 1)` — chips,
    toggles, taps. The default for any state change a user triggers.
  - **Smooth** — `340ms cubic-bezier(0.32, 0.72, 0.32, 1)` — row
    expansions, sheet transitions, theme switches.
- **Fades over slides.** No bounce. No overshoot.
- **No parallax.** No scroll-jacking.
- **Hover states:** opacity step from default to `0.85`, or border
  opacity step from hairline (6%) to interactive (16%). Never a color
  shift.
- **Press states:** brief scale to `0.97`, snappy spring back.
  No color flash.

### Transparency & blur

- **Used sparingly.** Only the sticky nav (after scroll) and the Liquid
  Glass theme use backdrop blur. Body copy is always on a fully opaque
  surface.

### Imagery (when it appears)

- iPhone mockups are rendered against the black canvas with a single
  warm-black drop shadow. The phone bezel is matte black; the screen
  inside renders an actual Stark Dark app view, not a flat screenshot.
- No stock photography. No lifestyle imagery. No team photos.
- If a photographic image must appear (a future case study), it should
  be cool-tinted, slightly desaturated, fine grain optional.

---

## ICONOGRAPHY

Avenor uses **Apple's SF Symbols** inside the iOS app — confirmed by the
`glyph` field on every `ThemePalette` (`"moon.fill"`, `"sun.max.fill"`,
`"leaf.fill"`, `"sparkles"`) which references SF Symbols names. SF Symbols
is not available on the web as a license-clean font, so the marketing
site substitutes **Lucide** (matching stroke-weight, similar geometric
construction) loaded from CDN.

### Rules

- **Stroke icons only** in marketing. 1.5px stroke weight. Rounded caps
  and joins. 24×24 frame. Sized inline with the type they sit next to.
- **No filled-circle "badge" icons.** No two-tone icons. No skeuomorphic
  ones.
- **No emoji.** This is non-negotiable.
- **No unicode characters used as icons** (e.g. arrows, checkmarks, stars).
  Use the Lucide equivalent.
- **One color at a time.** Icons inherit `currentColor`. They never carry
  a fill that disagrees with surrounding text.
- **Icons are functional, not decorative.** If an icon doesn't add
  recognition or meaning, remove it. Most headlines don't need one.

### Web (CDN)

```html
<script src="https://unpkg.com/lucide@latest"></script>
<i data-lucide="inbox"></i>
<script>lucide.createIcons();</script>
```

### iOS

Use `Image(systemName: "moon.fill")` etc. SF Symbols only. No PNG icons
in the app.

### Substitution flag

⚠️ **SF Symbols → Lucide on the web is a substitution.** When you ship a
production landing page, audit each icon you've used and pick the
closest-matching Lucide glyph. Document the mapping in a comment so
future engineers know the intent. If the user produces an SVG export of
their SF Symbols selection, prefer those.

### Logos

Two logo files are checked in:

- `assets/Avenor_Logo.png` — the dark glyph on transparent/white. Use on
  Stark Light, Calm Earth.
- `assets/Avenor_Logo_Dark.png` — the white glyph on dark. Use on
  Stark Dark and Liquid Glass.

The logo is a **3D-rendered infinity ribbon** (a Möbius strip read as
an infinity loop). It carries the brand's "one continuous capture loop"
metaphor. It should never be rotated, recolored, or skewed. Always sized
between 28–48px on the nav, larger only in display contexts (favicon
splash, app icon, hero accent).

---

## Index — files in this folder

### Root
- `README.md` — this file. Brand context, voice, foundations, iconography.
- `colors_and_type.css` — all CSS variables and base typography classes.
  Import this once at the top of any HTML surface you build.
- `SKILL.md` — Agent Skills manifest so this folder can be loaded as a
  reusable skill by Claude Code or another agent.

### `assets/`
- `Avenor_Logo.png` — dark glyph (for light surfaces).
- `Avenor_Logo_Dark.png` — white glyph (for dark surfaces — default).

### `fonts/`
- Empty. SF Pro is loaded via Apple system stack; Inter via Google Fonts
  CDN. Self-host either by dropping `.woff2` files here and uncommenting
  the `@font-face` blocks at the top of `colors_and_type.css`.

### `preview/`
- Small HTML cards (~700×N each) that populate the Design System tab.
  One concept per card. See the tab itself for the full grid.

### `ui_kits/`
- `avenor-ios/` — iOS app UI kit. The four-tab planner, in
  Stark Dark. Includes Today, Inbox, Capture sheet, Settings.
- `avenor-marketing/` — the landing page wireframe at avenor.app.
  Sticky nav, hero with capture-bar demo, CAPTURE / UNIFY / FEEL,
  email capture, footer.

### `DesignSystem/` *(mounted, read-only)*
- `DesignTokens.swift`
- `ThemePalette.swift`

---

## Caveats

- **SF Pro is loaded via the Apple system stack with Inter as a web
  fallback.** If you want pixel-identical type on every platform, ship
  a licensed SF Pro web kit or replace the fallback with a different
  metrically-similar typeface.
- **SF Symbols → Lucide is a substitution.** Audit per surface before
  shipping.
- **The four themes are scaffolded as CSS data-attribute variants in
  `colors_and_type.css`** but the marketing site and the iOS UI kit
  preview render in Stark Dark only. Building out Light / Calm Earth /
  Liquid Glass variants of the UI kits is a follow-on.

</design-system-guide>

CSS tokens: the guide may describe tokens in prose, but the exact `--*` names are defined in the design system's stylesheet(s) (`/projects/c1a36601-f108-47e2-983d-b4f9f7054cb7/colors_and_type.css`, `/projects/c1a36601-f108-47e2-983d-b4f9f7054cb7/preview/_card.css`, `/projects/c1a36601-f108-47e2-983d-b4f9f7054cb7/ui_kits/avenor-marketing/landing.css`). The 63 custom properties it defines are:

--accent-idea, --accent-note, --accent-primary, --accent-reminder, --accent-success, --accent-todo, --accent-warning, --ease-out, --fg-muted, --fg-primary, --fg-primary-soft, --fg-quaternary, --fg-secondary, --fg-tertiary, --font-display, --font-mono, --font-text, --fs-body, --fs-caption, --fs-display, --fs-headline, --fs-micro, --fs-title, --fw-bold, --fw-regular, --fw-semibold, --lh-body, --lh-caption, --lh-display, --lh-headline, --lh-micro, --lh-title, --motion-smooth, --motion-snappy, --radius-card, --radius-chip, --radius-md, --radius-sheet, --radius-sm, --shadow-card-lift, --shadow-mockup, --space-card-gap, --space-card-inset, --space-hairline, --space-page-bottom, --space-page-h, --space-page-top, --space-stack, --space-stack-lg, --stroke-hairline, --stroke-hairline-hex, --stroke-interactive, --stroke-prominent, --stroke-prominent-hex, --surface-canvas, --surface-card, --surface-card-elevated, --surface-field, --tr-body, --tr-display, --tr-headline, --tr-micro, --tr-title

Only use `var(--*)` names from that list. Never guess a token name — an unresolved `var()` silently falls back to the browser default.

For assets and UI kits beyond the guide: `read_file("/projects/c1a36601-f108-47e2-983d-b4f9f7054cb7/<path>")` and `copy_files` to bring them into the current project.
</attached-skill>

## User

Refer to the Screenshots of how the app actually looks.

## Assistant

_[tool: snip]_

_[tool: update_todos]_

_[tool: list_files]_

_[tool: read_file]_

_[tool: write_file]_

I have what I need. Let me build this site efficiently — shared CSS/JS, then 5 pages. The phone mockups will faithfully recreate the actual app screens from the screenshots.

**File 1/3 — site.css** (tokens, nav, sections, forms, footer):

_[tool: write_file]_

**File 2/3 — phones.css** (iPhone mockup + real-app screens + 4 themes):

_[tool: write_file]_

**File 3/3 — site.js** (nav scroll, reveal, capture demo, theme switcher):

_[tool: write_file]_

I need to make iPhone screens reusable across 5 pages without copying 100+ lines of markup each time. Let me add a phones.js that hydrates placeholder divs:

_[tool: write_file]_

_[tool: show_html]_

Now build **Page 1: index.html** (Home):

_[tool: write_file]_

Continuing — I'll build all 5 pages then verify at the end.

**Page 2: capture.html** (technical love letter to the parsing engine):**Page 3: features.html** (alternating left-right blocks):

_[tool: write_file]_

**Page 4: themes.html** (4 themes + interactive switcher):

_[tool: write_file]_

**Page 5: about.html**:

_[tool: write_file]_

All 5 pages built. Let me verify the home page loads cleanly and visually inspect:

_[tool: done]_

_[tool: fork_verifier_agent]_

Built a 5-page **Avenor marketing site** — Sophisticated Stark throughout, with iPhone mockups that faithfully recreate the actual app screens from your simulator shots.

**Pages**
- `index.html` — Home: hero, live capture demo (typewriter + parse), 2×2 unification grid, 4-theme teaser, email capture
- `capture.html` — Capture: oversized bar, 3 scroll-stacked explainer cards (typing → flowchart → result), full parse-reference table, free-text "try it" demo
- `features.html` — Tasks · Notes · Goals · Calendar · Widgets in alternating split layouts
- `themes.html` — 4 theme showcase rows + Liquid Glass shimmer + interactive switcher (live theme swap with section bg shift)
- `about.html` — Origin prose, three principles, contact

**Shared infrastructure**
- `assets/site.css` — tokens, nav, sections, forms, footer, scroll-reveal
- `assets/phones.css` — iPhone bezel + status bar + tab bar + all 5 real app screens + 4 theme variants (Stark Light, Calm Earth, Liquid Glass with frosted glass + specular shimmer)
- `assets/phones.js` — hydrates `<div data-phone="..." data-theme="..." data-size="...">` placeholders so screens stay reusable across pages
- `assets/site.js` — nav scroll, IntersectionObserver reveal, typewriter+parse demo, free-form parser, theme switcher

Old `Landing Page.html` is preserved as v1. Waiting on the verifier's cross-page sweep — let me know what to refine.

## User

Verifier agent check completed

## Assistant

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: run_script]_

Fixing the broken `[hidden]` → display:none transition. Simplest fix: stop using `hidden` entirely — the card's default `opacity:0` already makes it invisible.

_[tool: str_replace_edit]_

_[tool: done]_

Rewriting the About prose in a personal voice, no em-dashes:Updated the About prose:
- Opens with your name and that you're a high school student
- First-person voice throughout
- Em-dashes removed; replaced with full stops where the rhythm calls for it
- Same Avenor voice (short, declarative, no fluff)

## User

Apply a direct edit. In about.html: change the text from "Your day on your lock screen." to "Your day on your homee screen.".
<mentioned-element>
dom:      body[screen="03 Features"] › main › section › div.wrap › div.split.reveal › div.copy › h2[2/3]
text:     "Your day on your lock screen."
children: text
selector: section:nth-child(6) .copy >:is(h1,h2,h3,h4,h5,h6)
id:       cc-2
</mentioned-element>

## Assistant

_[tool: str_replace_edit]_

Already corrected to "Your day on your home screen." in features.html in the previous edit.

## User

Add tweakable controls to about.html: --- **Title** Edit and clarify the prompt about the Capture intent bar  **Role & stance** You are a professional text editor. Preserve the original meaning and intent, fix grammar and flow, and produce a natural-sounding version without altering what the author meant.  **Task** Edit the provided draft to be clear, concise, and grammatically correct while preserving the intended message.  **Context** The input text describes an issue with the first "Capture intent bar" and asks to insert some placeholder text to test scrolling and typing functionality, noting that typing is not currently possible and needs fixing.  **Inputs available** - IN the first "Capture intent bar, write somewher ein small dull text to scroll down to ttest it out, becuase rn it look slike you're supposed to be able to type and you cant, fix that  **Output requirements** Provide a cleaned, natural-sounding version that preserves the original meaning and intent. Do not add new information.  **Constraints / Do-nots** - Preserve meaning and intent - Preserve proper nouns (e.g., "Capture intent bar") - Remove disfluencies and typos - Do not add new facts or inferences - Do not output the original text unchanged  **Examples / References** N/A  **Execution checklist** - [ ] Correct grammar and spelling - [ ] Remove disfluencies - [ ] Preserve author intent - [ ] Ensure the sentence reads naturally  **Conflict resolution** N/A

## User

So Claude, here, it looks like you're supposed to be able to type and it doesn't work, right? Write just mention somewhere in small, dull font to: try out this feature below or something along those lines.

## Assistant

_[tool: str_replace_edit]_

_[tool: done]_

Adding a small dull hint that the hero bar is decorative and to scroll to the live one:Added "Display only. Try the live bar below ↓" in small mono uppercase under the hero bar. It's a link to the working demo in Section 4 — hover bumps it from muted to subtle.

## User

I have a question, now how do i make this an actual website?

## Assistant

The site is already a fully working static website — no build step needed. To put it on the internet, you have three good options, in order of "how fast can it be live":

**1. Drag-and-drop to Netlify (literally 30 seconds, free)**
- Go to [app.netlify.com/drop](https://app.netlify.com/drop)
- Drag the project folder onto the page
- You get a live URL like `avenor-xyz.netlify.app` instantly
- Hook up a custom domain (avenor.app) in the dashboard later

**2. Vercel (also free, slightly more polished)**
- `npm i -g vercel` then `vercel` in the project folder, or
- Push to GitHub → import on [vercel.com](https://vercel.com) → autodeploys on every commit

**3. Cloudflare Pages or GitHub Pages**
- Free, fast, similar workflow. Cloudflare Pages is the most generous on bandwidth.

**For the avenor.app domain**
You buy it at Namecheap / Cloudflare / Porkbun (~$10–15/yr for `.app`), then in your host's dashboard you set a custom domain and follow their two DNS records. Live in ~10 minutes.

**Things to check before launching**
- The email form currently just shows a "You're on the list" confirmation in JS — it doesn't go anywhere. Hook it up to a real service (Buttondown, ConvertKit, Tally, or a Netlify form) when you're ready.
- The page paths use relative URLs already, so it works without any rewrites.

Want me to **package the project as a downloadable .zip** so you can drag it into Netlify right now? Or set up the email form to actually capture submissions to a service?

## User

I want to add the email form to actually use submissions.

## Assistant

_[tool: str_replace_edit]_

_[tool: run_script]_

I'll wire it up with **Formspree** — easiest host-agnostic option (works on any platform, free tier covers 50 submissions/month, no backend needed).

Updating the JS to actually POST submissions, and tagging the forms with an endpoint attribute you'll swap in:Done. Here's what to do to make it live:

## 3-step setup with Formspree

**1. Create the form**
- Go to [formspree.io](https://formspree.io) and sign up (free tier = 50 submissions/month)
- Click "+ New Form", name it "Avenor early access", save
- Copy the endpoint URL (it looks like `https://formspree.io/f/xnnabcde`)

**2. Paste it into the site**
- In `index.html`, find both `data-endpoint="https://formspree.io/f/YOUR_FORM_ID"` occurrences (one in the hero, one in the access section)
- Replace `YOUR_FORM_ID` with your form's ID — both forms can use the same endpoint

**3. Deploy + test**
- Upload to Netlify/Vercel/Cloudflare Pages as discussed
- Submit your own email to verify
- New submissions show up in your Formspree dashboard and email you a notification

## What happens behind the scenes

- The form POSTs JSON `{ email, source, referrer }` to your endpoint
- On success → "You're on the list" + thanks note (existing UX preserved)
- On network error → button re-enables, note turns reminder-red with "Couldn't send. Try again in a moment."
- If you leave the placeholder in place, it falls back to optimistic UI — so local previews still feel snappy

## Alternatives if you'd rather not use Formspree

- **Netlify Forms** — if you host on Netlify, add `netlify name="early-access"` to the `<form>` tag and remove `data-endpoint`. Submissions go straight to your Netlify dashboard. 100 free submissions/month.
- **Web3Forms** — same flow as Formspree, 250 free/month, just swap the endpoint URL
- **Buttondown / ConvertKit** — if you want a real newsletter pipeline from day one. They both expose form endpoints.

Let me know your host pick and I'll wire it specifically for that path if you want.

## User

I have created a Formspree form with the endpoint:
https://formspree.io/f/mojbypae

## Assistant

_[tool: run_script]_

_[tool: done]_

Live. Both forms on `index.html` (hero + access section) now POST to `https://formspree.io/f/mojbypae`.

**Verify when you deploy:**
1. Submit your own email in the hero form
2. Check Formspree dashboard — you should see it with `email`, `source: /index.html`, and `referrer` fields
3. Formspree will ask you to confirm via email once on the first submission (anti-spam), then it's silent afterward

**Heads up on first submission:** Formspree sends you a "confirm your email" link the very first time someone submits — this is them verifying you own the endpoint, not a real user-facing step. After you click it once, all future submissions flow straight to your dashboard + notification emails.

## User

okay now setting it up as an actual website. i dont like netlify, all the domains i can buy there r bad. Suggest other ones. I'm thinking cloudflare, but idk whats the best one, thats free to host, but u need to still pay for the doman.

## Assistant

You're on the right track with Cloudflare. Here's the honest landscape:

## Hosting (free)

| Host | Why pick it | Why skip |
|---|---|---|
| **Cloudflare Pages** ⭐ | Best CDN on the planet, generous free tier (500 builds/month, unlimited bandwidth), seamless if you use Cloudflare Registrar too | Slightly nerdier dashboard than Vercel |
| **Vercel** | Beautiful dashboard, fastest deploys, "git push to deploy" feels great | Bandwidth cap (100GB/month free) is enough for now but it scales pricey if you blow up |
| **GitHub Pages** | Dead simple if your code is already on GitHub | No build pipeline, no analytics, no edge functions if you ever want them |
| **Surge.sh** | One-liner CLI deploy — fastest path to a live URL | No git integration, basic |

For Avenor, **Cloudflare Pages is the best free pick**. Static site + global CDN + you can layer Cloudflare Analytics on top for free. Drag-and-drop or `git push` workflow.

## Domain registrars

You're right that registrars vary wildly. For `.app` specifically (which is what the brief calls for):

| Registrar | `.app` price | Notes |
|---|---|---|
| **Cloudflare Registrar** ⭐ | **~$10.44/yr** | At-cost pricing, no upsell, no fake "first year discount" trick. Renewals stay the same price forever |
| **Porkbun** | ~$11.98/yr | Clean UI, free WHOIS privacy, fair renewal pricing |
| **Namecheap** | ~$15.98/yr | Often discounted year 1, renewals jump |
| GoDaddy | ~$20+/yr | Avoid — known for upsells and renewal hikes |

## The clean stack I'd pick

1. **Buy `avenor.app` at Cloudflare Registrar** (~$10/yr forever, no markup)
2. **Host on Cloudflare Pages** (free, same dashboard)
3. Domain auto-connects in one click since it's already on Cloudflare's nameservers

Total cost: ~$10/year. No backend, no surprises.

## Deploy steps (Cloudflare Pages, no git required)

1. Sign up at [dash.cloudflare.com](https://dash.cloudflare.com)
2. Pages → "Create a project" → "Upload assets"
3. Drag your project folder onto the page
4. Live in ~60 seconds at `avenor-xyz.pages.dev`
5. Buy `avenor.app` in the Registrar tab → click "Custom Domain" in Pages → "Add" → pick avenor.app
6. Done — auto SSL, CDN, the whole thing

Want me to **package the project as a zip** for the drag-and-drop upload?

## User

Apply comment

## Assistant

_[tool: str_replace_edit]_

## User

Apply a direct edit. In index.html: change the text from "hello@avenor.app" to "avenorapp@gmail.com\n".
<mentioned-element>
dom:      body[screen="05 About"] › main › section › div.wrap.reveal › a[3/4]
text:     "hello@avenor.app"
children: text
selector: .wrap >a
id:       cc-2
</mentioned-element>

## Assistant

