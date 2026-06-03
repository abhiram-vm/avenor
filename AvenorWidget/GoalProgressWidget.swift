import SwiftUI
import WidgetKit

// MARK: - GoalProgressWidget
//
// Small widget surfacing one goal's progress as a flat custom-drawn line.
// No system ProgressView, no green/red. The goal's tint paints the filled
// portion; the unfilled portion is a hairline-bordered void.
//
// Format (small):
//     READ 20 BOOKS
//     7 / 20 BOOKS
//     ───────────────  (Stark progress bar)
//
// First goal in the published list wins. (A future ConfigurationIntent
// could let users pick which goal — wired into AppIntent.)

struct GoalProgressWidget: Widget {
    let kind: String = "AvenorGoalProgress"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GoalProvider()) { entry in
            GoalProgressView(entry: entry)
                .starkWidgetContainer()
        }
        .configurationDisplayName("Goal Progress")
        .description("Track a single goal at a glance.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: Provider

struct GoalEntry: TimelineEntry {
    let date: Date
    let goal: GoalWidgetItem?
}

struct GoalProvider: TimelineProvider {
    func placeholder(in context: Context) -> GoalEntry {
        GoalEntry(date: .now, goal: GoalsWidgetPayload.placeholder.goals.first)
    }

    func getSnapshot(in context: Context, completion: @escaping (GoalEntry) -> Void) {
        completion(GoalEntry(date: .now, goal: WidgetSnapshotIO.readGoals().goals.first))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GoalEntry>) -> Void) {
        let goal = WidgetSnapshotIO.readGoals().goals.first
        let entry = GoalEntry(date: .now, goal: goal)
        let next = Calendar.autoupdatingCurrent.date(byAdding: .hour, value: 2, to: .now) ?? .now.addingTimeInterval(7200)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: View

struct GoalProgressView: View {
    let entry: GoalEntry

    var body: some View {
        if let g = entry.goal {
            populated(g)
        } else {
            emptyState
        }
    }

    private func populated(_ g: GoalWidgetItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GOAL")
                .font(WidgetTokens.Typography.micro)
                .tracking(WidgetTokens.Tracking.micro)
                .foregroundStyle(.white.opacity(0.50))

            Text(g.title)
                .font(WidgetTokens.Typography.headline)
                .foregroundStyle(.white)
                .lineLimit(2)

            Spacer(minLength: 0)

            // Numeric progress line — monospaced.
            HStack(spacing: 6) {
                Text(g.currentValueText)
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("/")
                    .foregroundStyle(.white.opacity(0.35))
                Text(g.targetValueText)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
            }
            .font(WidgetTokens.Typography.body)

            // Percent and bar.
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(g.progress * 100))%")
                    .font(WidgetTokens.Typography.micro)
                    .tracking(WidgetTokens.Tracking.micro)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
            }
            .padding(.top, 2)

            StarkProgressBar(progress: g.progress, tint: Color.fromWidgetHex(g.tintHex))
                .frame(height: 4)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GOAL")
                .font(WidgetTokens.Typography.micro)
                .tracking(WidgetTokens.Tracking.micro)
                .foregroundStyle(.white.opacity(0.50))
            Text("No goal set.")
                .font(WidgetTokens.Typography.headline)
                .foregroundStyle(.white.opacity(0.72))
            Spacer(minLength: 0)
            Text("OPEN AVENOR TO ADD ONE.")
                .font(WidgetTokens.Typography.micro)
                .tracking(WidgetTokens.Tracking.micro)
                .foregroundStyle(.white.opacity(0.32))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - StarkProgressBar
//
// Flat custom line. No animation, no gradient. The filled portion paints
// the goal tint at full opacity; the unfilled portion is a hairline-
// bordered void over the widget canvas.

struct StarkProgressBar: View {
    let progress: Double      // clamped 0...1
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let clamped = max(0, min(1, progress))
            ZStack(alignment: .leading) {
                Capsule()
                    .strokeBorder(WidgetTokens.Stroke.prominent, lineWidth: 0.5)
                Capsule()
                    .fill(tint.opacity(0.95))
                    .frame(width: max(2, geo.size.width * clamped))
            }
        }
    }
}
