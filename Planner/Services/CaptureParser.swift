import Foundation

// MARK: - CaptureParser
//
// Natural-language disambiguator for the Overview Command Center's quick
// capture bar. Routes a single line of free-form text into one of three
// concrete intents (todo / idea / note) and surfaces the structured tokens
// it stripped along the way.
//
// ARCHITECTURE — Component-Accumulating Builder
// ─────────────────────────────────────────────
// Previous versions ran each token extractor independently, with each one
// composing its own `Date` against `now`. That was destructive: matching
// `@5pm` clobbered the year/month/day, so "Gym tomorrow @5pm" silently
// landed on TODAY at 5pm instead of TOMORROW at 5pm.
//
// The new pipeline is a single-pass, additive accumulator:
//
//   1. `TaskDraftBuilder` is seeded with `now`'s y/m/d and a default time
//      of 09:00.
//   2. Each extractor runs in turn against the ORIGINAL string. Date-only
//      extractors mutate `.year/.month/.day`; time-only extractors mutate
//      `.hour/.minute`. Both also record their matched span.
//   3. After all extractors complete, the matched spans are stripped from
//      the title in reverse order and whitespace is collapsed.
//   4. `Calendar.current.date(from: components)` is called exactly once at
//      the end to produce the final `Date`.
//
// This makes the parser non-destructive: any combination of date + time
// tokens composes correctly regardless of order in the input string.
//
// Priority chain (only one intent can win):
//   0. Trailing `!` / `!!` / `!!!` → priority 1/2/3, stripped from text.
//   1. Hashtag present  → `.idea` (hashtag becomes `ideaTag`).
//   2. Date OR time token found → `.todo` (resolved Date attached).
//   3. >3 words & no tokens     → `.note`.
//   4. Else                     → `.todo` with no deadline.
//
// Privacy / runtime contract:
//   • Pure Swift + Foundation; no NLP frameworks, no Regex caching across
//     calls, no string logging, no network round-trips.
//   • Builder is a value type — no reference cycles.
//   • Each `parse` invocation is O(n) over the input.

// MARK: - RecurrenceRule
//
// A behavioral cadence detected in the capture text. Drives the habit
// routing branch and the preview shelf's checkbox→loop icon morph. Pure
// Foundation so both the parser and the persistence layer can share it.

enum RecurrenceRule: Equatable, Hashable {
    /// "every day" / "daily" / "each morning" / "each night".
    case daily
    /// "every monday"… — `weekday` is 1 (Sun)…7 (Sat). `nil` = generic
    /// "weekly" / "every week" with no specific anchor day.
    case weekly(weekday: Int?)
    /// "every weekday" — Monday through Friday.
    case weekdays
    /// "every other week" — `weekday` is 1 (Sun)…7 (Sat). `nil` = generic
    /// bi-weekly cadence with no specific anchor day. Template-only; the
    /// chip matrix can't express it, so it carries its schedule here.
    case biweekly(weekday: Int?)
    /// "1st of each month" — `day` is the day-of-month (1…31). Template-only.
    case monthly(day: Int)
    /// An explicit set of weekdays (1=Sun…7=Sat), e.g. weekends [1, 7] or
    /// Mon/Wed/Fri [2, 4, 6]. Same numbering convention as the chip matrix.
    case customDays([Int])

    /// Human-facing label for chips and row meta strips.
    var label: String {
        switch self {
        case .daily:    return "Every day"
        case .weekdays: return "Weekdays"
        case .weekly(let wd):
            guard let wd, let name = Self.weekdayName(wd) else { return "Weekly" }
            return "Every \(name)"
        case .biweekly(let wd):
            guard let wd, let name = Self.weekdayName(wd) else { return "Every other week" }
            return "Every other \(name)"
        case .monthly(let day):
            return "Monthly on day \(day)"
        case .customDays(let days):
            guard !days.isEmpty else { return "Custom" }
            let names = days.sorted().compactMap { Self.weekdayName($0).map { String($0.prefix(3)) } }
            return names.isEmpty ? "Custom" : names.joined(separator: ", ")
        }
    }

    /// Compact, stable persistence token (stored on `PersistedHabit`).
    var rawToken: String {
        switch self {
        case .daily:    return "daily"
        case .weekdays: return "weekdays"
        case .weekly(let wd): return wd.map { "weekly:\($0)" } ?? "weekly"
        case .biweekly(let wd): return wd.map { "biweekly:\($0)" } ?? "biweekly"
        case .monthly(let day): return "monthly:\(day)"
        case .customDays(let days):
            return "days:" + days.map(String.init).joined(separator: ",")
        }
    }

    init?(rawToken: String) {
        switch rawToken {
        case "daily":    self = .daily
        case "weekdays": self = .weekdays
        case "weekly":   self = .weekly(weekday: nil)
        case "biweekly": self = .biweekly(weekday: nil)
        default:
            if rawToken.hasPrefix("weekly:"),
               let wd = Int(rawToken.dropFirst("weekly:".count)) {
                self = .weekly(weekday: wd)
            } else if rawToken.hasPrefix("biweekly:"),
                      let wd = Int(rawToken.dropFirst("biweekly:".count)) {
                self = .biweekly(weekday: wd)
            } else if rawToken.hasPrefix("monthly:"),
                      let day = Int(rawToken.dropFirst("monthly:".count)) {
                self = .monthly(day: day)
            } else if rawToken.hasPrefix("days:") {
                let days = rawToken.dropFirst("days:".count)
                    .split(separator: ",")
                    .compactMap { Int($0) }
                guard !days.isEmpty else { return nil }
                self = .customDays(days)
            } else {
                return nil
            }
        }
    }

    static func weekdayName(_ wd: Int) -> String? {
        switch wd {
        case 1: return "Sunday";    case 2: return "Monday"
        case 3: return "Tuesday";   case 4: return "Wednesday"
        case 5: return "Thursday";  case 6: return "Friday"
        case 7: return "Saturday";  default: return nil
        }
    }
}

// MARK: - CaptureIntent

enum CaptureIntent: Equatable {
    /// `title` is the deadline-stripped text. `dueDate` is `nil` when no
    /// date or time token was recognized. `priority` is `1`..`3` for
    /// `!!!`/`!!`/`!` respectively (1 = highest), or `nil`.
    case todo(title: String, dueDate: Date?, priority: Int?)

    /// Like `.todo` but the title contains a social/meeting verb ("call",
    /// "lunch", "sync", etc.) paired with an explicit time token. Routed
    /// to the reminder container so Calendar integration can surface it.
    case reminder(title: String, dueDate: Date, priority: Int?)

    /// `title` is the hashtag-stripped text. `tag` is the bare hashtag
    /// word (no `#` prefix), uppercased, max 10 chars. `priority` carries
    /// the same bang-mapping rules as `.todo`.
    case idea(title: String, tag: String, priority: Int?)

    /// First sentence is the title; remaining text is the body. Falls back
    /// to the whole string as title if no period/newline split exists.
    case note(title: String, body: String)

    /// A recurring lifestyle routine. `rule` is the detected cadence;
    /// `anchor` carries the optional time-of-day (e.g. "read every day at
    /// 6pm"); `tag` is an optional hashtag; `priority` follows the bang
    /// rules. Routes to the habit container, not the task list.
    case habit(title: String, rule: RecurrenceRule, anchor: Date?, tag: String?, priority: Int?)

    #if os(macOS)
    /// A scheduled calendar event. **macOS-only.** Produced when a clock time
    /// is present with no recurrence, no hashtag, no priority bang, and no
    /// social/meeting verb — those route to habit / idea / todo / reminder
    /// respectively. `startDate` is always resolved (the parser never emits
    /// this without a time); `duration` defaults to one hour. The Mac capture
    /// bar routes this to EventKit.
    ///
    /// Gated behind `#if os(macOS)` so the iOS capture switch
    /// (`OverviewTabView.commitCapture`), which must stay exhaustive and is
    /// off-limits, never sees a new case — iOS routing is byte-identical.
    case calendar(title: String, startDate: Date, duration: TimeInterval)

    /// A measurable goal. **macOS-only.** Produced when the capture text carries
    /// a numeric target ("read 50 pages", "save $5000 by august") with no
    /// recurrence, no hashtag, no priority bang, and no resolvable date/time
    /// (those route to habit / idea / todo / calendar respectively). `unit` is
    /// `nil` when detection is ambiguous — the Mac capture bar then presents
    /// `Mac_GoalUnitPickerSheet` to pick one. `dueDate` is best-effort
    /// ("by august" → last day of August); it is not persisted today because
    /// `PersistedGoal` has no deadline field.
    ///
    /// Gated behind `#if os(macOS)` so the iOS capture switch stays exhaustive
    /// and byte-identical — iOS never sees this case.
    case goal(title: String, targetValue: Double, unit: String?, dueDate: Date?)
    #endif
}

// MARK: - TaskDraftBuilder
//
// Value-type accumulator. Holds the in-flight date components, the matched
// ranges (for stripping), and any out-of-band fields (hashtag, priority).
// Exposed at module scope so `SmartCaptureEngine` can reuse the same
// extraction pass for inline syntax highlighting — guarantees the live
// preview can never disagree with the committed result.

struct TaskDraftBuilder {

    // MARK: Component slots

    /// Mutable date components. Seeded with today @ 09:00 in `init`.
    var components: DateComponents

    // MARK: Match tracking

    /// All ranges that should be stripped from the final title.
    var matchedRanges: [Range<String.Index>] = []

    /// Range of the recognized date token (highlight metadata).
    var dateRange: Range<String.Index>? = nil
    /// Range of the recognized time token (highlight metadata).
    var timeRange: Range<String.Index>? = nil
    /// Range + value of the recognized hashtag (highlight metadata).
    var hashtag: (tag: String, range: Range<String.Index>)? = nil
    /// Range + value of the trailing-bang priority (highlight metadata).
    var priority: (level: Int, range: Range<String.Index>)? = nil
    /// Range + value of a recurrence cadence ("every day", "every monday").
    /// Presence of this routes the capture to a habit, not a task.
    var recurrence: (rule: RecurrenceRule, range: Range<String.Index>)? = nil

    // MARK: Flags

    /// `true` once a date extractor has written to `.year/.month/.day`.
    var hasDate: Bool = false
    /// `true` once a time extractor has written to `.hour/.minute`.
    var hasTime: Bool = false

    // MARK: Init

    init(now: Date, calendar: Calendar = .autoupdatingCurrent) {
        var c = DateComponents()
        let base = calendar.dateComponents([.year, .month, .day], from: now)
        c.year   = base.year
        c.month  = base.month
        c.day    = base.day
        c.hour   = 9
        c.minute = 0
        self.components = c
    }

    // MARK: Additive mutators

    /// Set ONLY the calendar slots. The clock slots are left untouched.
    mutating func setDate(year: Int, month: Int, day: Int,
                          range: Range<String.Index>) {
        components.year  = year
        components.month = month
        components.day   = day
        hasDate          = true
        dateRange        = range
        matchedRanges.append(range)
    }

    /// Set ONLY the clock slots. The calendar slots are left untouched.
    mutating func setTime(hour: Int, minute: Int,
                          range: Range<String.Index>) {
        components.hour   = hour
        components.minute = minute
        hasTime           = true
        timeRange         = range
        matchedRanges.append(range)
    }

    mutating func setHashtag(_ tag: String, range: Range<String.Index>) {
        hashtag = (tag, range)
        matchedRanges.append(range)
    }

    mutating func setPriority(_ level: Int, range: Range<String.Index>) {
        priority = (level, range)
        matchedRanges.append(range)
    }

    mutating func setRecurrence(_ rule: RecurrenceRule, range: Range<String.Index>) {
        recurrence = (rule, range)
        matchedRanges.append(range)
    }

    /// Pin the clock slots from a recurrence default ("each morning" → 09:00)
    /// WITHOUT recording a strip range or a `timeRange`. The cadence phrase
    /// is already being stripped/highlighted as a recurrence token, so we
    /// must not double-count it as a time span.
    mutating func setImplicitTime(hour: Int, minute: Int) {
        components.hour   = hour
        components.minute = minute
        hasTime           = true
    }

    // MARK: Compile

    /// Single resolution call. Returns `nil` when neither a date nor a
    /// time token was ever matched.
    func resolvedDate(calendar: Calendar = .autoupdatingCurrent) -> Date? {
        guard hasDate || hasTime else { return nil }
        return calendar.date(from: components)
    }
}

// MARK: - CaptureParser

enum CaptureParser {

    /// Default span for a `.calendar` event when capture text carries only a
    /// start time (one hour). macOS-only routing reads this; declared
    /// unconditionally so the constant has a single home.
    static let defaultEventDuration: TimeInterval = 3600

    // MARK: Public entry

    /// Single entry point. Returns `nil` for empty / whitespace-only input.
    static func parse(_ raw: String, now: Date = .now) -> CaptureIntent? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Edge case: input is nothing but bangs.
        if trimmed.allSatisfy({ $0 == "!" }) {
            return .todo(title: trimmed, dueDate: nil, priority: nil)
        }

        // Run the shared extraction pass — same builder consumed by
        // SmartCaptureEngine for inline highlighting.
        let builder = build(trimmed, now: now)

        // Strip every matched span from the original string.
        let cleaned = strip(matchedRanges: builder.matchedRanges, from: trimmed)
        let title   = collapseWhitespace(cleaned)
        let pri     = builder.priority?.level

        // Intent decision (priority chain).
        // 1. Recurrence wins outright — a cadence means this is a habit,
        //    carrying any time anchor + hashtag along for the ride.
        if let recurrence = builder.recurrence {
            return .habit(
                title: title,
                rule: recurrence.rule,
                anchor: builder.resolvedDate(),
                tag: builder.hashtag?.tag,
                priority: pri
            )
        }

        // 2. Hashtag wins over date/time → idea.
        if let hashtag = builder.hashtag {
            return .idea(title: title, tag: hashtag.tag, priority: pri)
        }

        if let due = builder.resolvedDate() {
            #if os(macOS)
            // macOS capture-bar event routing (inserted after habit + idea,
            // before the reminder/todo fallthrough). Recurrence and hashtag
            // already returned above, so they're excluded here by construction.
            //
            //  • A clock time with no priority bang and no meeting verb books a
            //    calendar event ("standup tomorrow 10am" → .calendar).
            //  • A priority bang flags a task, overriding event/reminder routing
            //    ("meeting at 5pm !!!" → .todo).
            //
            // iOS excludes this whole block, so its routing is unchanged: a
            // bare date still → .todo, a timed meeting verb still → .reminder.
            if builder.hasTime, pri == nil, !containsMeetingVerb(title) {
                return .calendar(title: title, startDate: due, duration: defaultEventDuration)
            }
            if pri != nil {
                return .todo(title: title, dueDate: due, priority: pri)
            }
            #endif
            // If an explicit time was parsed and the title contains a social/
            // meeting verb, route to .reminder so Calendar integration picks it up.
            if builder.hasTime && containsMeetingVerb(title) {
                return .reminder(title: title, dueDate: due, priority: pri)
            }
            return .todo(title: title, dueDate: due, priority: pri)
        }

        #if os(macOS)
        // macOS-only goal routing. Inserted after recurrence + hashtag (both
        // already returned above) and after the date/time block (so a timed
        // capture books a calendar event, never a goal). A numeric target with
        // no priority bang and no resolvable date → a measurable goal
        // ("read 50 pages", "save $5000 by august"). iOS excludes this whole
        // block, so its routing stays byte-identical.
        if pri == nil, let goal = detectGoal(from: title, now: now) {
            return goal
        }
        #endif

        // No tokens, no priority — long-form text routes to note.
        if pri == nil, wordCount(of: title) > 3 {
            return .note(
                title: noteTitle(from: title),
                body:  noteBody(from: title)
            )
        }

        return .todo(title: title, dueDate: nil, priority: pri)
    }

    // MARK: Shared extraction pass
    //
    // Walks the input once and populates a `TaskDraftBuilder` with every
    // recognized token. Exposed `internal` so `SmartCaptureEngine` can
    // reuse the exact same matcher for inline syntax highlighting.
    //
    // Order matters only because each individual extractor uses
    // first-match semantics: e.g., `tomorrow` wins over `today` if both
    // are typed. Cross-channel matches (date + time + hashtag + priority)
    // are independent and accumulate freely.

    static func build(_ text: String, now: Date = .now) -> TaskDraftBuilder {
        var builder = TaskDraftBuilder(now: now)

        // Trailing bangs — recorded first so the priority extractor sees
        // a clean tail. The strip happens later via `matchedRanges`.
        applyTrailingPriority(text, builder: &builder)

        // Hashtag — independent channel.
        applyHashtag(text, builder: &builder)

        // Time channel. `@HH[:MM][am|pm]` and `@HMM[am|pm]` forms. Runs
        // BEFORE recurrence so an explicit `@6pm` wins over the implicit
        // morning/evening default that "each morning" would otherwise set.
        applyAtTimeToken(text, builder: &builder, now: now)
        // "at <time>" word form — equivalent trigger to @time.
        applyAtWordTimeToken(text, builder: &builder, now: now)

        #if os(macOS)
        // Bare time token ("10am", "2pm", "3:30pm", "17:00"). macOS-only: it
        // exists to feed the Mac `.calendar` route — the iOS parser never had
        // bare-time detection and its routing must stay byte-identical, so this
        // is gated. Runs only when no explicit `@time` / "at time" already
        // locked the clock, and reuses the shared `parseHourMinute` validator
        // (no duplicated time logic).
        if !builder.hasTime {
            applyBareTimeToken(text, builder: &builder, now: now)
        }
        #endif

        // Recurrence channel. Detected cadence ("every day", "every monday")
        // routes the whole capture to a habit. Runs BEFORE the one-off date
        // extractors and suppresses them — a habit's schedule IS its cadence,
        // so we must not also bind a single calendar date (and "every monday"
        // must not be misread as the next-occurrence "monday").
        applyRecurrence(text, builder: &builder)

        // One-off date channel — skipped entirely when a cadence is present.
        // Each helper is a no-op if a date is already locked in (first wins).
        if builder.recurrence == nil {
            let calendar = Calendar.autoupdatingCurrent
            applyKeywordDateToken(text, builder: &builder, calendar: calendar, now: now)
            if builder.dateRange == nil {
                applyDayOfWeekToken(text, builder: &builder, calendar: calendar, now: now)
            }
            if builder.dateRange == nil {
                applyRelativeShorthand(text, builder: &builder, calendar: calendar, now: now)
            }
            if builder.dateRange == nil {
                applyRelativeTimeOffset(text, builder: &builder, now: now)
            }
            if builder.dateRange == nil {
                applyThisContextualTime(text, builder: &builder, calendar: calendar, now: now)
            }
            if builder.dateRange == nil {
                applyOrdinalDate(text, builder: &builder, calendar: calendar, now: now)
            }
        }

        return builder
    }

    // MARK: - Recurrence channel
    //
    // Whole-word phrase matching for behavioral cadence. Ordered longest /
    // most-specific first so "every weekday" beats "every", and the
    // morning/evening variants (which also pin a default time) are checked
    // before the bare "every day". The matched span is recorded for
    // stripping so the stored title stays clean ("Read 20 pages every day"
    // → "Read 20 pages").

    private static func applyRecurrence(_ text: String,
                                        builder: inout TaskDraftBuilder) {
        struct Pattern {
            let needles: [String]
            let rule: RecurrenceRule
            /// Implicit time-of-day, applied only when no `@time` was set.
            let implicitTime: (hour: Int, minute: Int)?
        }

        // Per-weekday "every <day>" / "each <day>".
        var patterns: [Pattern] = []
        let weekdays: [(String, Int)] = [
            ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4),
            ("thursday", 5), ("friday", 6), ("saturday", 7)
        ]
        patterns.append(Pattern(needles: ["every weekday", "each weekday", "weekdays"],
                                rule: .weekdays, implicitTime: nil))
        for (name, wd) in weekdays {
            patterns.append(Pattern(needles: ["every \(name)", "each \(name)"],
                                    rule: .weekly(weekday: wd), implicitTime: nil))
        }
        patterns.append(contentsOf: [
            Pattern(needles: ["every morning", "each morning"],
                    rule: .daily, implicitTime: (9, 0)),
            Pattern(needles: ["every evening", "each evening", "every night", "each night"],
                    rule: .daily, implicitTime: (20, 0)),
            Pattern(needles: ["every week", "each week", "weekly"],
                    rule: .weekly(weekday: nil), implicitTime: nil),
            Pattern(needles: ["every day", "each day", "everyday", "daily"],
                    rule: .daily, implicitTime: nil)
        ])

        let lower = text.lowercased()
        for pattern in patterns {
            for needle in pattern.needles {
                guard let lowerRange = wholeWordRange(of: needle, in: lower) else { continue }
                let origRange = mapRange(lowerRange, fromLower: lower, original: text)
                builder.setRecurrence(pattern.rule, range: origRange)
                if let time = pattern.implicitTime, !builder.hasTime {
                    builder.setImplicitTime(hour: time.hour, minute: time.minute)
                }
                return
            }
        }
    }

    // MARK: Strip

    /// Removes every matched range from `text`. Ranges are sorted in
    /// descending order so indices remain valid as we splice out spans.
    private static func strip(matchedRanges ranges: [Range<String.Index>],
                              from text: String) -> String {
        guard !ranges.isEmpty else { return text }
        let sorted = ranges.sorted { $0.lowerBound > $1.lowerBound }
        var result = text
        for range in sorted {
            // Defensive bounds check — if any extractor produced a stale
            // range we silently skip rather than crash. (Should never
            // happen since extractors operate on the same input.)
            guard range.lowerBound >= result.startIndex,
                  range.upperBound <= result.endIndex else { continue }
            result.removeSubrange(range)
        }
        return result
    }

    // MARK: - Priority extractor (trailing bangs)
    //
    // `!!!`/`!!`/`!` at the end of the input (after optional whitespace),
    // preceded by whitespace or string-start. `wow!` inside a sentence is
    // NOT a match because the whitespace gate fails.

    private static func applyTrailingPriority(_ text: String,
                                              builder: inout TaskDraftBuilder) {
        var end = text.endIndex
        while end > text.startIndex {
            let prev = text.index(before: end)
            guard text[prev].isWhitespace else { break }
            end = prev
        }
        guard end > text.startIndex,
              text[text.index(before: end)] == "!" else { return }

        var bangStart = end
        while bangStart > text.startIndex {
            let prev = text.index(before: bangStart)
            guard text[prev] == "!" else { break }
            bangStart = prev
        }
        let count = text.distance(from: bangStart, to: end)
        guard count > 0 else { return }

        if bangStart > text.startIndex {
            let prev = text.index(before: bangStart)
            guard text[prev].isWhitespace else { return }
        }

        let level = max(1, min(3, 4 - count))     // !!! → 1, !! → 2, ! → 3
        let range = bangStart..<text.endIndex     // also gobbles trailing space
        builder.setPriority(level, range: range)
    }

    // MARK: - Hashtag extractor

    private static func applyHashtag(_ text: String,
                                     builder: inout TaskDraftBuilder) {
        guard let hashIdx = text.firstIndex(of: "#") else { return }
        let after = text.index(after: hashIdx)
        guard after < text.endIndex else { return }

        var endIdx = after
        while endIdx < text.endIndex {
            let c = text[endIdx]
            guard c.isLetter || c.isNumber else { break }
            endIdx = text.index(after: endIdx)
        }
        guard endIdx > after else { return }

        let tagWord  = String(text[after..<endIdx])
        let cappedTag = String(tagWord.prefix(10)).uppercased()
        builder.setHashtag(cappedTag, range: hashIdx..<endIdx)
    }

    // MARK: - Time channel: @-time tokens
    //
    // Supports four shapes:
    //   • `@5pm`     → 17:00
    //   • `@5:30pm`  → 17:30
    //   • `@17:00`   → 17:00
    //   • `@630am`   → 06:30  (compact H+MM or HH+MM, no colon)
    //
    // We deliberately do NOT touch year/month/day here — that's the
    // whole point of the new builder pipeline.

    private static func applyAtTimeToken(_ text: String,
                                         builder: inout TaskDraftBuilder,
                                         now: Date) {
        // EDGE CASE (multiple conflicting tokens, e.g. "@5pm @6pm"):
        // We scan EVERY `@` occurrence. The LAST syntactically valid token
        // wins the clock value (most-recent user intent), and ALL of them
        // are recorded for stripping so no literal `@…` clutter survives in
        // the title. The first match's range stays in `matchedRanges`; only
        // `timeRange` (used for highlighting) tracks the winner.
        let currentHour = Calendar.current.component(.hour, from: now)
        var searchStart = text.startIndex

        while let atIdx = text[searchStart...].firstIndex(of: "@") {
            var cursor = text.index(after: atIdx)

            // Collect digits and at most one colon.
            var digits = ""
            var sawColon = false
            while cursor < text.endIndex {
                let c = text[cursor]
                if c.isNumber {
                    digits.append(c)
                    cursor = text.index(after: cursor)
                } else if c == ":" && !sawColon {
                    digits.append(c)
                    sawColon = true
                    cursor = text.index(after: cursor)
                } else {
                    break
                }
            }

            // Optional am/pm suffix.
            var period: String? = nil
            if cursor < text.endIndex {
                let tail = text[cursor...].prefix(2).lowercased()
                if tail == "am" || tail == "pm" {
                    period = String(tail)
                    cursor = text.index(cursor, offsetBy: 2)
                }
            }

            // A valid token overwrites the clock slots (last-wins) and is
            // recorded for stripping. Invalid `@…` runs are skipped — they
            // stay in the title, which is the safe, non-destructive default.
            let inferHour = period == nil ? currentHour : -1
            if !digits.isEmpty, let (hour, minute) = parseHourMinute(digits, period: period,
                                                                      currentHour: inferHour) {
                // Gobble a connector word ("at"/"by") before the `@` so
                // "Run tomorrow at @5pm" cleans up to "Run".
                let leadingRange = gobbleConnectorBefore(atIdx, in: text)
                builder.setTime(hour: hour, minute: minute,
                                range: (leadingRange ?? atIdx)..<cursor)
            }

            // Advance past this `@` regardless of validity. `cursor` is
            // always > `atIdx` (it starts one past `@`), so this strictly
            // progresses and cannot loop forever.
            guard cursor < text.endIndex else { break }
            searchStart = cursor
        }
    }

    #if os(macOS)
    // MARK: - Time channel: bare time token (macOS-only)
    //
    // Detects a free-standing time with no `@` or "at" trigger:
    //   • meridiem form  — "10am", "2pm", "3:30pm", "9 am"
    //   • 24-hour colon  — "17:00", "9:30"
    //
    // Requires a meridiem OR a colon so bare integers ("20 pages", "section 5",
    // "in 2 days") never misfire as times. Validation goes through the shared
    // `parseHourMinute`. The matched span is recorded for stripping so the
    // event title stays clean ("Team standup tomorrow 10am" → "Team standup").
    private static func applyBareTimeToken(_ text: String,
                                           builder: inout TaskDraftBuilder,
                                           now: Date) {
        let currentHour = Calendar.current.component(.hour, from: now)
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        struct Hit { let range: NSRange; let digits: String; let period: String? }
        var hit: Hit?

        // Meridiem form: H[:MM] am|pm  (optional single space before am/pm).
        if let rx = try? NSRegularExpression(
            pattern: #"(?<![0-9A-Za-z])(\d{1,2})(?::(\d{2}))? ?(am|pm)(?![A-Za-z])"#,
            options: .caseInsensitive),
           let m = rx.firstMatch(in: text, range: full) {
            let hourStr = ns.substring(with: m.range(at: 1))
            let minRange = m.range(at: 2)
            let digits = minRange.location == NSNotFound
                ? hourStr
                : "\(hourStr):\(ns.substring(with: minRange))"
            hit = Hit(range: m.range, digits: digits,
                      period: ns.substring(with: m.range(at: 3)).lowercased())
        }

        // 24-hour colon form: HH:MM  (only if no meridiem hit landed earlier).
        if hit == nil,
           let rx = try? NSRegularExpression(
            pattern: #"(?<![0-9A-Za-z:])(\d{1,2}):(\d{2})(?![0-9A-Za-z])"#),
           let m = rx.firstMatch(in: text, range: full) {
            let digits = "\(ns.substring(with: m.range(at: 1))):\(ns.substring(with: m.range(at: 2)))"
            hit = Hit(range: m.range, digits: digits, period: nil)
        }

        guard let hit,
              let r = Range(hit.range, in: text),
              let (hour, minute) = parseHourMinute(hit.digits, period: hit.period,
                                                   currentHour: hit.period == nil ? currentHour : -1)
        else { return }

        builder.setTime(hour: hour, minute: minute, range: r)
    }
    #endif

    /// Maps a digit payload (with or without colon) to validated (h, m).
    private static func parseHourMinute(_ digits: String,
                                        period: String?,
                                        currentHour: Int = -1) -> (Int, Int)? {
        var hour: Int
        var minute: Int

        if digits.contains(":") {
            // Colon form: H:MM or HH:MM
            let parts = digits.split(separator: ":").map(String.init)
            guard let h = Int(parts.first ?? "") else { return nil }
            hour   = h
            minute = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        } else {
            // Compact form: 1–2 digits = hour only, 3 = H+MM, 4 = HH+MM.
            switch digits.count {
            case 1, 2:
                guard let h = Int(digits) else { return nil }
                hour = h; minute = 0
            case 3:
                guard let h = Int(String(digits.prefix(1))),
                      let m = Int(String(digits.suffix(2))) else { return nil }
                hour = h; minute = m
            case 4:
                guard let h = Int(String(digits.prefix(2))),
                      let m = Int(String(digits.suffix(2))) else { return nil }
                hour = h; minute = m
            default:
                return nil
            }
        }

        if let period {
            if period == "pm" && hour < 12 { hour += 12 }
            if period == "am" && hour == 12 { hour  = 0  }
        } else if currentHour >= 0 && hour >= 1 && hour <= 12 {
            // Smart AM/PM inference for bare numbers (no am/pm suffix).
            // 1–6 always PM (nobody books "3am" by default); 7–11 PM only
            // when it's already afternoon; 12 stays at noon.
            if hour <= 6 {
                hour += 12
            } else if hour <= 11 {
                if currentHour >= 12 { hour += 12 }
            }
            // hour == 12 → noon, no adjustment needed
        }
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return (hour, minute)
    }

    /// If the word immediately preceding `idx` is a connector like "at"
    /// or "by", returns a range that includes it (and its leading space)
    /// so the title-strip pass removes it cleanly.
    private static func gobbleConnectorBefore(_ idx: String.Index,
                                              in text: String) -> String.Index? {
        // Walk back across one whitespace run.
        var cursor = idx
        while cursor > text.startIndex {
            let prev = text.index(before: cursor)
            if text[prev].isWhitespace { cursor = prev } else { break }
        }
        // Now read the previous word.
        let wordEnd = cursor
        var wordStart = wordEnd
        while wordStart > text.startIndex {
            let prev = text.index(before: wordStart)
            if text[prev].isLetter { wordStart = prev } else { break }
        }
        let word = text[wordStart..<wordEnd].lowercased()
        guard word == "at" || word == "by" else { return nil }
        // Confirm a clean left boundary (start-of-string or whitespace).
        if wordStart > text.startIndex {
            let prev = text.index(before: wordStart)
            guard text[prev].isWhitespace else { return nil }
        }
        return wordStart
    }

    // MARK: - Date channel: keyword extractor
    //
    // `today` / `tomorrow` / `tonight`.
    // NOTE: `tonight` is special — it sets BOTH the date (today) and the
    // time (20:00). The other two only set the date.

    private static func applyKeywordDateToken(_ text: String,
                                              builder: inout TaskDraftBuilder,
                                              calendar: Calendar,
                                              now: Date) {
        struct KW { let needle: String; let dayOffset: Int; let alsoTime: (Int, Int)? }
        let keywords: [KW] = [
            // Tomorrow and aliases
            KW(needle: "tomorrow", dayOffset: 1, alsoTime: nil),
            KW(needle: "tmrw",     dayOffset: 1, alsoTime: nil),
            KW(needle: "tmr",      dayOffset: 1, alsoTime: nil),
            KW(needle: "tom",      dayOffset: 1, alsoTime: nil),
            KW(needle: "tomoro",   dayOffset: 1, alsoTime: nil),
            // Tonight and aliases
            KW(needle: "tonight",  dayOffset: 0, alsoTime: (20, 0)),
            KW(needle: "tonite",   dayOffset: 0, alsoTime: (20, 0)),
            KW(needle: "2nite",    dayOffset: 0, alsoTime: (20, 0)),
            KW(needle: "tn",       dayOffset: 0, alsoTime: (20, 0)),
            // Today and aliases
            KW(needle: "today",    dayOffset: 0, alsoTime: nil),
            KW(needle: "tdy",      dayOffset: 0, alsoTime: nil),
            KW(needle: "td",       dayOffset: 0, alsoTime: nil),
            KW(needle: "2day",     dayOffset: 0, alsoTime: nil),
        ]
        let lower = text.lowercased()

        for kw in keywords {
            guard let lowerRange = wholeWordRange(of: kw.needle, in: lower) else { continue }

            guard let base = calendar.date(byAdding: .day, value: kw.dayOffset, to: now) else { continue }
            let ymd = calendar.dateComponents([.year, .month, .day], from: base)
            guard let y = ymd.year, let m = ymd.month, let d = ymd.day else { continue }

            let origRange = mapRange(lowerRange, fromLower: lower, original: text)
            builder.setDate(year: y, month: m, day: d, range: origRange)

            // `tonight` additionally pins the clock — but only if no `@`
            // token already locked the time in.
            if let (h, min) = kw.alsoTime, !builder.hasTime {
                builder.setTime(hour: h, minute: min, range: origRange)
            }
            return
        }
    }

    // MARK: - Date channel: day-of-week
    //
    // `[on|this|next] monday`..`sunday`. Resolves to the next future
    // occurrence at the existing time (defaults to 09:00 if no time
    // token has been seen yet).

    private static func applyDayOfWeekToken(_ text: String,
                                            builder: inout TaskDraftBuilder,
                                            calendar: Calendar,
                                            now: Date) {
        let days: [(String, Int)] = [
            ("sunday", 1), ("monday", 2), ("tuesday", 3),
            ("wednesday", 4), ("thursday", 5), ("friday", 6), ("saturday", 7)
        ]
        let prefixes = ["next ", "nxt ", "this ", "on ", "by "]
        let lower = text.lowercased()

        for (name, weekday) in days {
            var lowerRange: Range<String.Index>? = nil
            var usedPrefix: String? = nil

            for pref in prefixes {
                if let r = wholeWordRange(of: pref + name, in: lower) {
                    lowerRange = r
                    usedPrefix = pref.trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            if lowerRange == nil { lowerRange = wholeWordRange(of: name, in: lower) }
            guard let lr = lowerRange else { continue }

            let todayWeekday = calendar.component(.weekday, from: now)
            var delta = weekday - todayWeekday
            if delta <= 0 { delta += 7 }
            if usedPrefix == "next" || usedPrefix == "nxt" { delta += 7 }

            guard let base = calendar.date(byAdding: .day, value: delta, to: now) else { continue }
            let ymd = calendar.dateComponents([.year, .month, .day], from: base)
            guard let y = ymd.year, let m = ymd.month, let d = ymd.day else { continue }

            let origRange = mapRange(lr, fromLower: lower, original: text)
            builder.setDate(year: y, month: m, day: d, range: origRange)
            return
        }
    }

    // MARK: - Date channel: relative shorthand
    //
    // `in N day(s)` / `in N week(s)`. Month/year deliberately omitted —
    // variable-length months open too many edge cases for a quick-capture
    // path. Users wanting a specific date open the new-item sheet.

    private static func applyRelativeShorthand(_ text: String,
                                               builder: inout TaskDraftBuilder,
                                               calendar: Calendar,
                                               now: Date) {
        let lower = text.lowercased()
        let chars = Array(lower)

        var i = 0
        while i < chars.count {
            guard chars[i] == "i", i + 1 < chars.count, chars[i + 1] == "n" else {
                i += 1; continue
            }
            // Left whole-word boundary.
            if i > 0, chars[i - 1].isLetter { i += 1; continue }
            // Right boundary: must be whitespace.
            let afterIn = i + 2
            guard afterIn < chars.count, chars[afterIn].isWhitespace else { i += 1; continue }

            var cursor = afterIn
            while cursor < chars.count, chars[cursor].isWhitespace { cursor += 1 }

            // Digits.
            let numStart = cursor
            while cursor < chars.count, chars[cursor].isNumber { cursor += 1 }
            guard cursor > numStart,
                  let n = Int(String(chars[numStart..<cursor])), n > 0 else { i += 1; continue }

            // Whitespace before unit.
            while cursor < chars.count, chars[cursor].isWhitespace { cursor += 1 }

            // Unit word.
            let unitStart = cursor
            while cursor < chars.count, chars[cursor].isLetter { cursor += 1 }
            let unit = String(chars[unitStart..<cursor])
            let component: Calendar.Component?
            switch unit {
            case "day", "days":                 component = .day
            case "week", "weeks", "wk", "wks": component = .weekOfYear
            default:               component = nil
            }
            guard let comp = component else { i += 1; continue }

            let endOK = cursor == chars.count || !chars[cursor].isLetter
            guard endOK else { i += 1; continue }

            guard let base = calendar.date(byAdding: comp, value: n, to: now) else { i += 1; continue }
            let ymd = calendar.dateComponents([.year, .month, .day], from: base)
            guard let y = ymd.year, let m = ymd.month, let d = ymd.day else { i += 1; continue }

            // Map char-index range back to String.Index.
            let startOrig = text.index(text.startIndex, offsetBy: i)
            let endOrig   = text.index(text.startIndex, offsetBy: cursor)
            builder.setDate(year: y, month: m, day: d, range: startOrig..<endOrig)
            return
        }
    }

    // MARK: - Time channel: "at <time>" word trigger (Change 2 + 3)

    /// Parses "at 9", "at 9pm", "at 9:30am", "at 17:00" as a time trigger,
    /// whole-word matched on "at" so "chat" / "that" / "flat" are ignored.
    private static func applyAtWordTimeToken(_ text: String,
                                             builder: inout TaskDraftBuilder,
                                             now: Date) {
        let lower = text.lowercased()
        let currentHour = Calendar.current.component(.hour, from: now)
        var searchIdx = lower.startIndex

        while searchIdx < lower.endIndex {
            guard let atRange = lower.range(of: "at", range: searchIdx..<lower.endIndex) else { break }

            // Whole-word check: no letter before "at"
            let beforeOK = atRange.lowerBound == lower.startIndex
                || !lower[lower.index(before: atRange.lowerBound)].isLetter
            // Must be followed by whitespace (not end-of-string alone)
            let afterChar: Character? = atRange.upperBound < lower.endIndex
                ? lower[atRange.upperBound] : nil
            let afterOK = afterChar?.isWhitespace == true

            guard beforeOK && afterOK else { searchIdx = atRange.upperBound; continue }

            // Skip whitespace
            var cursor = atRange.upperBound
            while cursor < lower.endIndex, lower[cursor].isWhitespace {
                cursor = lower.index(after: cursor)
            }

            // Collect digits + optional colon
            var digits = ""
            var sawColon = false
            while cursor < lower.endIndex {
                let c = lower[cursor]
                if c.isNumber {
                    digits.append(c)
                    cursor = lower.index(after: cursor)
                } else if c == ":" && !sawColon && !digits.isEmpty {
                    digits.append(c)
                    sawColon = true
                    cursor = lower.index(after: cursor)
                } else {
                    break
                }
            }

            guard !digits.isEmpty else { searchIdx = atRange.upperBound; continue }

            // Optional am/pm
            var period: String? = nil
            if cursor < lower.endIndex {
                let tail = String(lower[cursor...].prefix(2))
                if tail == "am" || tail == "pm" {
                    period = tail
                    cursor = lower.index(cursor, offsetBy: 2)
                }
            }

            // No letter should immediately follow (guards against e.g. "at 9pm sharp" is fine,
            // but "at 9foo" is not a valid time)
            if cursor < lower.endIndex, lower[cursor].isLetter {
                searchIdx = atRange.upperBound; continue
            }

            let inferHour = period == nil ? currentHour : -1
            if let (hour, minute) = parseHourMinute(digits, period: period, currentHour: inferHour) {
                // Strip "at <time>" — from start of "at" through end of time token
                let origStart = mapRange(atRange, fromLower: lower, original: text).lowerBound
                let distEnd   = lower.distance(from: lower.startIndex, to: cursor)
                let origEnd   = text.index(text.startIndex, offsetBy: distEnd)
                builder.setTime(hour: hour, minute: minute, range: origStart..<origEnd)
            }

            guard cursor < lower.endIndex else { break }
            searchIdx = cursor
        }
    }

    // MARK: - Date+time channel: relative time offsets (Change 4)

    /// Handles "in an hour", "in a few hours", "in N hours", "in N mins", etc.
    /// Resolves to `now + offset` and sets both date and time on the builder.
    private static func applyRelativeTimeOffset(_ text: String,
                                                builder: inout TaskDraftBuilder,
                                                now: Date) {
        let lower = text.lowercased()
        let chars  = Array(lower)
        var i      = 0

        while i < chars.count {
            // Whole-word "in" check
            guard chars[i] == "i",
                  i + 1 < chars.count, chars[i + 1] == "n" else { i += 1; continue }
            if i > 0, chars[i - 1].isLetter { i += 1; continue }
            let afterIn = i + 2
            guard afterIn < chars.count, chars[afterIn].isWhitespace else { i += 1; continue }

            var cursor = afterIn
            while cursor < chars.count, chars[cursor].isWhitespace { cursor += 1 }

            var offsetSeconds: Int? = nil
            var endCursor = cursor

            // "an hour"
            let slice7 = chars.count - cursor >= 7 ? String(chars[cursor..<cursor + 7]) : ""
            if slice7 == "an hour" {
                let boundary = cursor + 7 >= chars.count || !chars[cursor + 7].isLetter
                if boundary { offsetSeconds = 3_600; endCursor = cursor + 7 }
            }

            // "a few hours"
            if offsetSeconds == nil {
                let slice11 = chars.count - cursor >= 11 ? String(chars[cursor..<cursor + 11]) : ""
                if slice11 == "a few hours" {
                    let boundary = cursor + 11 >= chars.count || !chars[cursor + 11].isLetter
                    if boundary { offsetSeconds = 3 * 3_600; endCursor = cursor + 11 }
                }
            }

            // "N <unit>"
            if offsetSeconds == nil {
                endCursor = cursor
                let numStart = endCursor
                while endCursor < chars.count, chars[endCursor].isNumber { endCursor += 1 }
                guard endCursor > numStart, let n = Int(String(chars[numStart..<endCursor])), n > 0 else {
                    i += 1; continue
                }
                while endCursor < chars.count, chars[endCursor].isWhitespace { endCursor += 1 }
                let unitStart = endCursor
                while endCursor < chars.count, chars[endCursor].isLetter { endCursor += 1 }
                guard endCursor > unitStart else { i += 1; continue }
                let unit = String(chars[unitStart..<endCursor])
                guard endCursor >= chars.count || !chars[endCursor].isLetter else { i += 1; continue }

                switch unit {
                case "hour", "hours":                    offsetSeconds = n * 3_600
                case "min", "mins", "minute", "minutes": offsetSeconds = n * 60
                default: i += 1; continue
                }
            }

            guard let secs = offsetSeconds else { i += 1; continue }

            let target = now.addingTimeInterval(TimeInterval(secs))
            let cal    = Calendar.current
            let comps  = cal.dateComponents([.year, .month, .day, .hour, .minute], from: target)
            guard let y = comps.year, let m = comps.month, let d = comps.day,
                  let h = comps.hour, let min = comps.minute else { i += 1; continue }

            let startOrig = text.index(text.startIndex, offsetBy: i)
            let endOrig   = text.index(text.startIndex, offsetBy: endCursor)
            builder.setDate(year: y, month: m, day: d, range: startOrig..<endOrig)
            if !builder.hasTime {
                builder.setTime(hour: h, minute: min, range: startOrig..<endOrig)
            }
            return
        }
    }

    // MARK: - Date+time channel: "this morning/afternoon/evening/weekend" (Change 5)

    private static func applyThisContextualTime(_ text: String,
                                                builder: inout TaskDraftBuilder,
                                                calendar: Calendar,
                                                now: Date) {
        struct Ctx {
            let needle: String
            let hour: Int
            let minute: Int
            let isSaturday: Bool
        }
        let currentHour = calendar.component(.hour, from: now)
        let lower = text.lowercased()

        let contexts: [Ctx] = [
            Ctx(needle: "this morning",   hour: 9,  minute: 0, isSaturday: false),
            Ctx(needle: "this afternoon", hour: 14, minute: 0, isSaturday: false),
            Ctx(needle: "this evening",   hour: 18, minute: 0, isSaturday: false),
            Ctx(needle: "this weekend",   hour: 10, minute: 0, isSaturday: true),
        ]

        for ctx in contexts {
            guard let lowerRange = wholeWordRange(of: ctx.needle, in: lower) else { continue }

            var targetDate: Date
            if ctx.isSaturday {
                let todayWeekday = calendar.component(.weekday, from: now)
                var delta = 7 - todayWeekday  // days until Saturday (weekday 7)
                if delta < 0 { delta += 7 }
                targetDate = calendar.date(byAdding: .day, value: delta, to: now) ?? now
            } else {
                // If the target hour is already past, push to tomorrow
                if currentHour >= ctx.hour {
                    targetDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now
                } else {
                    targetDate = now
                }
            }

            let ymd = calendar.dateComponents([.year, .month, .day], from: targetDate)
            guard let y = ymd.year, let m = ymd.month, let d = ymd.day else { continue }

            let origRange = mapRange(lowerRange, fromLower: lower, original: text)
            builder.setDate(year: y, month: m, day: d, range: origRange)
            if !builder.hasTime {
                builder.setTime(hour: ctx.hour, minute: ctx.minute, range: origRange)
            }
            return
        }
    }

    // MARK: - Date channel: ordinal date expressions (Change 6)

    /// Handles "on the 20th", "on the 1st", "on the 3rd", etc.
    /// Resolves to the Nth of this month at 9am; bumps to next month if past.
    private static func applyOrdinalDate(_ text: String,
                                         builder: inout TaskDraftBuilder,
                                         calendar: Calendar,
                                         now: Date) {
        let lower = text.lowercased()
        guard let regex = try? NSRegularExpression(
            pattern: #"\bon the (\d{1,2})(st|nd|rd|th)\b"#,
            options: .caseInsensitive) else { return }

        let nsLower = lower as NSString
        guard let match = regex.firstMatch(in: lower, range: NSRange(location: 0, length: nsLower.length)),
              let numNSRange = Range(match.range(at: 1), in: lower),
              let day = Int(lower[numNSRange]),
              (1...31).contains(day),
              let fullMatchRange = Range(match.range, in: lower) else { return }

        var comps      = calendar.dateComponents([.year, .month], from: now)
        comps.day      = day
        comps.hour     = 9
        comps.minute   = 0

        var targetDate = calendar.date(from: comps)
        if let t = targetDate, t <= now {
            comps.month  = (comps.month ?? 1) + 1
            targetDate   = calendar.date(from: comps)
        }
        guard let resolved = targetDate else { return }

        let ymd = calendar.dateComponents([.year, .month, .day], from: resolved)
        guard let y = ymd.year, let m = ymd.month, let d = ymd.day else { return }

        let origRange = mapRange(fullMatchRange, fromLower: lower, original: text)
        builder.setDate(year: y, month: m, day: d, range: origRange)
        if !builder.hasTime {
            builder.setTime(hour: 9, minute: 0, range: origRange)
        }
    }

    // MARK: - Intent classifier helpers (Change 7)

    /// Returns `true` when `title` contains a social/meeting verb or phrase
    /// that suggests the capture is a scheduled social event rather than a plain task.
    private static func containsMeetingVerb(_ title: String) -> Bool {
        let lower = title.lowercased()
        // Multi-word phrases first (whole-word matched via wholeWordRange)
        let phrases = ["catch up", "chat with", "talk to", "check in"]
        for phrase in phrases {
            if wholeWordRange(of: phrase, in: lower) != nil { return true }
        }
        // Single-word verbs
        let verbs = ["meet", "meeting", "call", "sync", "lunch", "dinner",
                     "coffee", "catchup", "checkin", "zoom", "interview"]
        for verb in verbs {
            if wholeWordRange(of: verb, in: lower) != nil { return true }
        }
        return false
    }

    #if os(macOS)
    // MARK: - Goal detection (macOS-only)
    //
    // Recognizes a measurable goal from capture text carrying a numeric target.
    // Called from `parse` only after recurrence, hashtag, and the date/time
    // block have each had their chance, so a goal never shadows a habit, idea,
    // calendar event, or dated task. Returns `nil` when there's no number,
    // leaving the capture to fall through to note / todo.
    //
    // Rules (all required):
    //   • A number is present (integer/decimal, optional `$` prefix, optional
    //     `k` thousands suffix). Mandatory — no number, no goal.
    //   • Unit is detected from a small keyword table; `nil` when none matches
    //     (the Mac capture handler then prompts for one).
    //   • Optional "by <month>" books a soft due date (last day of the month).
    //
    // The numeric token, unit word, and due-date phrase are stripped to leave a
    // clean title ("read 50 pages" → "read").
    private static func detectGoal(from text: String, now: Date) -> CaptureIntent? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        // Numeric target: optional `$`, digits with optional decimal, optional `k`.
        guard let numRx = try? NSRegularExpression(
            pattern: #"(?<![\w.])(\$)?(\d+(?:\.\d+)?)(k)?(?![\w.])"#,
            options: .caseInsensitive),
            let numMatch = numRx.firstMatch(in: text, range: full),
            let valueRange = Range(numMatch.range(at: 2), in: text),
            var value = Double(text[valueRange])
        else { return nil }

        let hasDollar = numMatch.range(at: 1).location != NSNotFound
        let hasK = numMatch.range(at: 3).location != NSNotFound
        if hasK { value *= 1000 }

        // Spans to strip from the title (number always; unit + due optional).
        var stripRanges: [Range<String.Index>] = []
        if let r = Range(numMatch.range, in: text) { stripRanges.append(r) }

        // Unit detection (first match wins; ordered per spec).
        let lower = text.lowercased()
        var unit: String? = nil
        let unitTable: [(needles: [String], unit: String)] = [
            (["pages", "pg", "p"], "pages"),
            (["words", "word"], "words"),
            (["dollars", "usd"], "dollars"),
            (["miles", "mi"], "miles"),
            (["km"], "km"),
            (["hours", "hrs", "hr"], "hours"),
            (["reps", "rep", "times"], "reps"),
        ]
        outer: for entry in unitTable {
            for needle in entry.needles {
                if let r = wholeWordRange(of: needle, in: lower) {
                    unit = entry.unit
                    stripRanges.append(mapRange(r, fromLower: lower, original: text))
                    break outer
                }
            }
        }
        // Currency / thousands fallbacks when no explicit unit word matched.
        if unit == nil, hasDollar { unit = "dollars" }
        if unit == nil, hasK { unit = "words" }

        // Optional "by <month>" → last day of that month.
        var dueDate: Date? = nil
        if let monthRx = try? NSRegularExpression(
            pattern: #"\bby\s+(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\b"#,
            options: .caseInsensitive),
            let m = monthRx.firstMatch(in: text, range: full),
            let monthRange = Range(m.range(at: 1), in: text),
            let endOfMonth = lastDayOfMonth(String(text[monthRange]), now: now) {
            dueDate = endOfMonth
            if let r = Range(m.range, in: text) { stripRanges.append(r) }
        }

        // Build the clean title by stripping the matched spans.
        let title = collapseWhitespace(strip(matchedRanges: stripRanges, from: text))
        return .goal(title: title, targetValue: value, unit: unit, dueDate: dueDate)
    }

    /// Last moment of the named month, this year (or next year if the month has
    /// already fully passed). Powers "by august"-style soft goal deadlines.
    private static func lastDayOfMonth(_ name: String, now: Date) -> Date? {
        let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                      "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]
        guard let month = months[String(name.lowercased().prefix(3))] else { return nil }
        let cal = Calendar.autoupdatingCurrent
        var comps = cal.dateComponents([.year], from: now)
        comps.month = month
        comps.day = 1
        guard var first = cal.date(from: comps) else { return nil }
        // If that month already ended this year, roll to next year.
        if let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: first), end < now {
            comps.year = (comps.year ?? 0) + 1
            guard let bumped = cal.date(from: comps) else { return nil }
            first = bumped
        }
        guard let range = cal.range(of: .day, in: .month, for: first) else { return nil }
        var lastComps = cal.dateComponents([.year, .month], from: first)
        lastComps.day = range.count
        lastComps.hour = 23
        lastComps.minute = 59
        return cal.date(from: lastComps)
    }
    #endif

    // MARK: - Range helpers

    /// Whole-word range lookup on a lowercased string. Returns `nil` if
    /// the needle isn't found, or if either edge is adjacent to a letter
    /// (so `tomorrow` doesn't match inside `tomorrowland`).
    private static func wholeWordRange(of needle: String,
                                       in lower: String) -> Range<String.Index>? {
        guard let range = lower.range(of: needle) else { return nil }
        let beforeOK = range.lowerBound == lower.startIndex
            || !lower[lower.index(before: range.lowerBound)].isLetter
        let afterOK = range.upperBound == lower.endIndex
            || !lower[range.upperBound].isLetter
        return (beforeOK && afterOK) ? range : nil
    }

    /// Translates a lowercased-derived range back to its original-case
    /// counterpart. Lowercasing a string never changes the count for
    /// ASCII input, but we still walk by distance to remain Unicode-safe.
    private static func mapRange(_ range: Range<String.Index>,
                                 fromLower lower: String,
                                 original: String) -> Range<String.Index> {
        let s = lower.distance(from: lower.startIndex, to: range.lowerBound)
        let e = lower.distance(from: lower.startIndex, to: range.upperBound)
        let lowerOrig = original.index(original.startIndex, offsetBy: s)
        let upperOrig = original.index(original.startIndex, offsetBy: e)
        return lowerOrig..<upperOrig
    }

    // MARK: - Note splitting / whitespace

    private static func wordCount(of s: String) -> Int {
        s.split { $0.isWhitespace || $0.isNewline }.count
    }

    private static func noteTitle(from text: String) -> String {
        let terminators: Set<Character> = [".", "!", "?", "\n"]
        if let idx = text.firstIndex(where: { terminators.contains($0) }) {
            let title = text[..<idx].trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? text : title
        }
        return text
    }

    private static func noteBody(from text: String) -> String {
        let terminators: Set<Character> = [".", "!", "?", "\n"]
        guard let idx = text.firstIndex(where: { terminators.contains($0) }) else { return "" }
        let after = text.index(after: idx)
        guard after < text.endIndex else { return "" }
        return String(text[after...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func collapseWhitespace(_ s: String) -> String {
        let collapsed = s.split { $0.isWhitespace || $0.isNewline }
            .joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
