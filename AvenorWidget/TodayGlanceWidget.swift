import SwiftUI
import WidgetKit

// MARK: - TodayGlanceWidget
//
// Small: prominent monospaced count + label.
// Medium: same count plus the top 3 items, each line:
//     TODO · DUE 12:00 PM · #URGENT
//
// All rendering is Stark: flat black, hairlines, monospaced digits, no
// gradients, no SF Symbol decoration past tiny inline glyphs.

struct TodayGlanceWidget: Widget {
    let kind: String = "AvenorTodayGlance"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            TodayGlanceView(entry: entry)
                .starkWidgetContainer()
        }
        .configurationDisplayName("Today")
        .description("A quiet glance at what's due today.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: Timeline provider

struct TodayEntry: TimelineEntry {
    let date: Date
    let payload: TodayWidgetPayload
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, payload: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: .now, payload: WidgetSnapshotIO.readToday()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let payload = WidgetSnapshotIO.readToday()
        let entry = TodayEntry(date: .now, payload: payload)
        // Refresh hourly — the main app also writes snapshots on mutations,
        // and iOS will request a reload via WidgetCenter when that happens.
        let next = Calendar.autoupdatingCurrent.date(byAdding: .hour, value: 1, to: .now) ?? .now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: View

struct TodayGlanceView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        switch family {
        case .systemSmall:  smallLayout
        case .systemMedium: mediumLayout
        default:            smallLayout
        }
    }

    // MARK: Small

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TODAY")
                .font(WidgetTokens.Typography.micro)
                .tracking(WidgetTokens.Tracking.micro)
                .foregroundStyle(.white.opacity(0.50))

            Text("\(entry.payload.totalDueToday)")
                .font(WidgetTokens.Typography.display)
                .tracking(WidgetTokens.Tracking.display)
                .monospacedDigit()
                .foregroundStyle(.white)

            Spacer(minLength: 0)

            Text(entry.payload.totalDueToday == 1 ? "ITEM DUE" : "ITEMS DUE")
                .font(WidgetTokens.Typography.micro)
                .tracking(WidgetTokens.Tracking.micro)
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Medium

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("TODAY")
                    .font(WidgetTokens.Typography.micro)
                    .tracking(WidgetTokens.Tracking.micro)
                    .foregroundStyle(.white.opacity(0.50))

                Spacer()

                Text("\(entry.payload.totalDueToday)")
                    .font(WidgetTokens.Typography.title)
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }

            hairline

            if entry.payload.items.isEmpty {
                Text("NO ACTION ITEMS DUE TODAY.")
                    .font(WidgetTokens.Typography.micro)
                    .tracking(WidgetTokens.Tracking.micro)
                    .foregroundStyle(.white.opacity(0.40))
                    .padding(.top, 6)
                Spacer(minLength: 0)
            } else {
                ForEach(entry.payload.items.prefix(3)) { item in
                    row(item)
                    hairline
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var hairline: some View {
        Rectangle().fill(WidgetTokens.Stroke.hairline).frame(height: 0.5)
    }

    private func row(_ item: TodayWidgetItem) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Rectangle()
                .fill(WidgetTokens.accent(forTypeRaw: item.typeRaw).opacity(0.85))
                .frame(width: 2, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? "Untitled" : item.title)
                    .font(WidgetTokens.Typography.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                metaLine(for: item)
            }

            Spacer(minLength: 0)
        }
    }

    private func metaLine(for item: TodayWidgetItem) -> some View {
        var tokens: [String] = [WidgetTokens.typeLabel(forTypeRaw: item.typeRaw)]
        if let due = item.dueDate { tokens.append("DUE \(Self.timeFormatter.string(from: due).uppercased())") }
        if let tag = item.ideaTag, !tag.isEmpty { tokens.append("#\(tag.uppercased())") }

        return Text(tokens.joined(separator: " · "))
            .font(WidgetTokens.Typography.micro)
            .tracking(WidgetTokens.Tracking.micro)
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.55))
            .lineLimit(1)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f
    }()
}
