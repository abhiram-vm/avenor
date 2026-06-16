import Foundation

// MARK: - MentionResolver
//
// Resolves `@Mention` tokens in note bodies against live task / goal titles.
// Built once per editor render from the current `@Query` results and handed to
// `MarkdownParser`, which asks `isResolved(_:)` to decide a mention's color
// (mint = matched, gold = unmatched).
//
// Matching is intentionally forgiving (the brief: "ignore case, allow one
// character difference"): a mention matches a title when, case-insensitively,
// it equals the title, is a prefix of the first title word, or is within a
// Levenshtein distance of 1. Goals win ties only if no task matched — tasks
// are checked first since they're the more frequent reference.
//
// Zero dependencies: the fuzzy check is a hand-rolled bounded edit-distance.

struct MentionResolver {

    /// What an `@Mention` points at, once resolved.
    enum Target {
        case task(PersistedTask)
        case goal(PersistedGoal)
    }

    private let tasks: [PersistedTask]
    private let goals: [PersistedGoal]

    init(tasks: [PersistedTask], goals: [PersistedGoal]) {
        self.tasks = tasks
        self.goals = goals
    }

    /// `true` when the mention name maps to a task or goal.
    func isResolved(_ name: String) -> Bool {
        resolve(name) != nil
    }

    /// Resolve a mention name to its target, or `nil` if unmatched.
    /// Tasks are searched before goals.
    func resolve(_ name: String) -> Target? {
        let needle = name.lowercased()
        guard !needle.isEmpty else { return nil }

        if let task = tasks.first(where: { Self.fuzzyMatch(needle, title: $0.title) }) {
            return .task(task)
        }
        if let goal = goals.first(where: { Self.fuzzyMatch(needle, title: $0.title) }) {
            return .goal(goal)
        }
        return nil
    }

    // MARK: Matching

    /// Case-insensitive forgiving match between a mention `needle` (already
    /// lowercased) and a candidate `title`.
    static func fuzzyMatch(_ needle: String, title: String) -> Bool {
        let hay = title.lowercased()
        guard !hay.isEmpty else { return false }

        // Exact, or mention is a prefix of the title's first word (handles a
        // single-word @mention pointing at a multi-word title).
        if hay == needle { return true }
        let firstWord = hay.split(separator: " ").first.map(String.init) ?? hay
        if firstWord == needle { return true }
        if firstWord.hasPrefix(needle) && needle.count >= 3 { return true }

        // Otherwise allow one typo against the first word.
        return boundedEditDistance(needle, firstWord, max: 1) <= 1
    }

    /// Levenshtein distance, early-exiting once it provably exceeds `max`.
    /// `max` is tiny (1) here, so this stays cheap even on long strings.
    static func boundedEditDistance(_ a: String, _ b: String, max: Int) -> Int {
        let a = Array(a), b = Array(b)
        if abs(a.count - b.count) > max { return max + 1 }
        if a.isEmpty { return b.count <= max ? b.count : max + 1 }
        var prev = Array(0...b.count)
        var curr = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            curr[0] = i
            var rowBest = curr[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = Swift.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
                rowBest = Swift.min(rowBest, curr[j])
            }
            if rowBest > max { return max + 1 }
            swap(&prev, &curr)
        }
        return prev[b.count]
    }
}
