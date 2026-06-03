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

    /// Human-facing label for chips and row meta strips.
    var label: String {
        switch self {
        case .daily:    return "Every day"
        case .weekdays: return "Weekdays"
        case .weekly(let wd):
            guard let wd, let name = Self.weekdayName(wd) else { return "Weekly" }
            return "Every \(name)"
        }
    }

    /// Compact, stable persistence token (stored on `PersistedHabit`).
    var rawToken: String {
        switch self {
        case .daily:    return "daily"
        case .weekdays: return "weekdays"
        case .weekly(let wd): return wd.map { "weekly:\($0)" } ?? "weekly"
        }
    }

    init?(rawToken: String) {
        switch rawToken {
        case "daily":    self = .daily
        case "weekdays": self = .weekdays
        case "weekly":   self = .weekly(weekday: nil)
        default:
            guard rawToken.hasPrefix("weekly:"),
                  let wd = Int(rawToken.dropFirst("weekly:".count)) else { return nil }
            self = .weekly(weekday: wd)
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
            return .todo(title: title, dueDate: due, priority: pri)
        }

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
            if !digits.isEmpty, let (hour, minute) = parseHourMinute(digits, period: period) {
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

    /// Maps a digit payload (with or without colon) to validated (h, m).
    private static func parseHourMinute(_ digits: String,
                                        period: String?) -> (Int, Int)? {
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
        var wordEnd = cursor
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
            KW(needle: "tomorrow", dayOffset: 1, alsoTime: nil),
            KW(needle: "tonight",  dayOffset: 0, alsoTime: (20, 0)),
            KW(needle: "today",    dayOffset: 0, alsoTime: nil)
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
        let prefixes = ["next ", "this ", "on "]
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
            if usedPrefix == "next" { delta += 7 }

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
            case "day", "days":   component = .day
            case "week", "weeks": component = .weekOfYear
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
