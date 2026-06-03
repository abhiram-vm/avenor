//
//  AvenorWidget.swift
//  AvenorWidget
//
//  Unified, theme-aware widget family. One `Widget` declaration powers all
//  three system sizes — the layout switches on `widgetFamily` inside the
//  entry view. Theme is sourced from the shared App Group every time iOS
//  asks for a timeline, so the palette flips the moment the user picks a
//  new theme in the main app (which calls `WidgetCenter.reloadAllTimelines`).
//
//  Capture Intent deep link: tapping the "Capture Intent" affordance opens
//  `avenor://capture` — the main app's Tasks tab listens for this scheme
//  and focuses the StarkCaptureBar.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline provider
//
// Static configuration — there's nothing the user needs to configure.
// Entries are spaced 15 minutes apart over the next 4 hours; the time
// display itself uses `Text(_:style: .time)` which auto-ticks between
// reloads, so the cadence here is just a fallback to keep the date
// rolling over at midnight and the upcoming-task list reasonably fresh.

struct AvenorEntry: TimelineEntry {
    let date: Date
    let today: TodayWidgetPayload
    let palette: WidgetPalette
}

struct AvenorProvider: TimelineProvider {

    func placeholder(in context: Context) -> AvenorEntry {
        AvenorEntry(
            date: .now,
            today: .placeholder,
            palette: .starkDark
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (AvenorEntry) -> Void) {
        completion(makeEntry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AvenorEntry>) -> Void) {
        let now = Date.now
        let cal = Calendar.autoupdatingCurrent
        var entries: [AvenorEntry] = []
        for step in 0..<16 {
            let date = cal.date(byAdding: .minute, value: step * 15, to: now) ?? now
            entries.append(makeEntry(at: date))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func makeEntry(at date: Date) -> AvenorEntry {
        AvenorEntry(
            date: date,
            today: WidgetSnapshotIO.readToday(),
            palette: .current()
        )
    }
}

// MARK: - Widget declaration

struct AvenorWidget: Widget {
    let kind: String = "AvenorWidget"

    var body: some WidgetConfiguration {
        // CRITICAL: `.containerBackground(for: .widget) { ... }` must be the
        // ONLY modifier on the view returned from the configuration's content
        // closure. WidgetKit walks the returned view looking for a
        // containerBackground; any modifier chained between the root view
        // and `.containerBackground` (`.environment`, `.foregroundStyle`,
        // `.tint`, etc.) can cause iOS to strip the background and fall back
        // to the system widget default — which is `.fill.tertiary` (white in
        // light mode). All color-scheme / foreground / tint overrides have
        // been moved INSIDE `AvenorEntryView` so the configuration closure
        // stays minimal.
        //
        // `.contentMarginsDisabled()` removes the default 16pt content
        // margin iOS reserves around widget content; without it the system
        // background bleeds through the edges (a common cause of
        // "white-edged" widgets even when containerBackground is correct).
        // The app's deployment target is already iOS 17+, so no availability
        // guard is needed — returning from divergent `if #available`
        // branches breaks the `some WidgetConfiguration` opaque return type.
        return StaticConfiguration(kind: kind, provider: AvenorProvider()) { entry in
            AvenorEntryView(entry: entry)
                // `.containerBackground` is the ONLY modifier chained on
                // the entry view at the configuration level. Any modifier
                // between the root view and this modifier (`.environment`,
                // `.foregroundStyle`, `.tint`) causes iOS to strip the
                // background and fall back to the system white card.
                // Palette + color-scheme propagation happens INSIDE
                // `AvenorEntryView.body` instead.
                .containerBackground(for: .widget) {
                    WidgetCanvasView(palette: entry.palette)
                }
        }
        .configurationDisplayName("Avenor")
        .description("Time, date, and a one-tap capture into Avenor.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Entry view
//
// All palette propagation (color scheme, default foreground, tint) lives
// here, INSIDE the view tree that `.containerBackground` paints behind —
// never chained between the root view and the configuration's
// `.containerBackground` modifier.

struct AvenorEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AvenorEntry

    var body: some View {
        let p = entry.palette
        layout
            .foregroundColor(p.textPrimary)
            .tint(p.accent)
            // Palette-driven color scheme — Stark Dark / Liquid Glass
            // resolve to `.dark`, Stark Light / Calm Earth to `.light`.
            // Driving from the palette keeps the system chrome (e.g.
            // tinted accent rendering) in sync with the chosen theme.
            .environment(\.colorScheme, p.colorScheme)
    }

    @ViewBuilder
    private var layout: some View {
        switch family {
        case .systemSmall:  SmallView(entry: entry)
        case .systemMedium: MediumView(entry: entry)
        case .systemLarge:  LargeView(entry: entry)
        default:            SmallView(entry: entry)
        }
    }
}

// MARK: - Small (Time & Date Focus)

private struct SmallView: View {
    let entry: AvenorEntry

    var body: some View {
        let p = entry.palette
        WidgetThemedCard(palette: p) {
            VStack(alignment: .leading, spacing: 0) {
                // BOLD MINIMALIST TIME — uses display font scaled up to
                // dominate the small canvas. Monospaced digits keep the
                // colon position from jitter-ticking each minute.
                Text(entry.date, style: .time)
                    .font(.system(size: 42, weight: .bold, design: p.fontDesign))
                    .tracking(p.displayTracking)
                    .monospacedDigit()
                    .foregroundStyle(p.textPrimary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .widgetAccentable()

                Spacer(minLength: 0)

                // Compact date strip — weekday + date on one tight stack.
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.date, format: .dateTime.weekday(.wide))
                        .font(p.font(.headline))
                        .tracking(p.headlineTracking)
                        .foregroundStyle(p.textSecondary)
                        .lineLimit(1)

                    Text(entry.date, format: .dateTime.month(.abbreviated).day().year())
                        .font(p.font(.caption))
                        .monospacedDigit()
                        .foregroundStyle(p.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
        }
    }
}

// MARK: - Medium (Date & Action Focus)

private struct MediumView: View {
    let entry: AvenorEntry

    var body: some View {
        let p = entry.palette
        WidgetThemedCard(palette: p) {
            VStack(alignment: .leading, spacing: 0) {
                // Top row: weekday + date on left, time on right —
                // baseline-aligned so the type sits flush.
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.date, format: .dateTime.weekday(.wide))
                            .font(p.font(.headline))
                            .tracking(p.headlineTracking)
                            .textCase(.uppercase)
                            .foregroundStyle(p.textSecondary)
                        Text(entry.date, format: .dateTime.month(.wide).day())
                            .font(p.font(.title))
                            .tracking(p.headlineTracking)
                            .foregroundStyle(p.textPrimary)
                    }
                    Spacer(minLength: 0)
                    Text(entry.date, style: .time)
                        .font(p.font(.title))
                        .tracking(p.displayTracking)
                        .monospacedDigit()
                        .foregroundStyle(p.textPrimary)
                        .widgetAccentable()
                }

                Spacer(minLength: 0)

                CaptureIntentLink(palette: p)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
    }
}

// MARK: - Large (Dashboard)

private struct LargeView: View {
    let entry: AvenorEntry

    var body: some View {
        let p = entry.palette
        WidgetThemedCard(palette: p) {
            VStack(alignment: .leading, spacing: 16) {
                headerRow(palette: p, date: entry.date)

                CaptureIntentLink(palette: p)

                // Palette-driven hairline — Divider().overlay doesn't
                // reliably tint, so we draw a 0.5pt rect ourselves.
                Rectangle()
                    .fill(p.hairline)
                    .frame(height: 0.5)

                upcomingHeader(palette: p, count: entry.today.totalDueToday)

                upcomingList(palette: p, items: entry.today.items)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
        }
    }

    @ViewBuilder
    private func headerRow(palette p: WidgetPalette, date: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(date, format: .dateTime.weekday(.wide))
                    .font(p.font(.headline))
                    .tracking(p.headlineTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(p.textSecondary)
                Text(date, format: .dateTime.month(.wide).day())
                    .font(p.font(.title))
                    .tracking(p.headlineTracking)
                    .foregroundStyle(p.textPrimary)
            }
            Spacer(minLength: 0)
            Text(date, style: .time)
                .font(p.font(.title))
                .tracking(p.displayTracking)
                .foregroundStyle(p.textPrimary)
                .monospacedDigit()
                .widgetAccentable()
        }
    }

    @ViewBuilder
    private func upcomingHeader(palette p: WidgetPalette, count: Int) -> some View {
        HStack(spacing: 6) {
            Text("UPCOMING")
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .foregroundStyle(p.textSecondary)
            Text("·")
                .font(p.font(.micro))
                .foregroundStyle(p.textTertiary)
            Text("\(count) DUE TODAY")
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .monospacedDigit()
                .foregroundStyle(p.textTertiary)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func upcomingList(palette p: WidgetPalette, items: [TodayWidgetItem]) -> some View {
        if items.isEmpty {
            Text("Nothing scheduled.")
                .font(p.font(.body))
                .foregroundStyle(p.textTertiary)
                .padding(.top, 2)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.prefix(4).enumerated()), id: \.element.id) { index, item in
                    UpcomingRow(palette: p, item: item)
                    if index < min(items.count, 4) - 1 {
                        Rectangle()
                            .fill(p.hairline)
                            .frame(height: 0.5)
                    }
                }
            }
        }
    }
}

// MARK: - Building blocks

/// Capture-bar look-alike: tappable terminal-style row that deep-links the
/// user straight into the app's StarkCaptureBar via `avenor://capture`.
/// Alignment mirrors the in-app StarkCaptureBar — caret glyph + body
/// label + invisible trailing slot for visual balance.
private struct CaptureIntentLink: View {
    let palette: WidgetPalette

    var body: some View {
        let p = palette
        Link(destination: URL(string: "avenor://capture")!) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(">")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(p.textPrimary.opacity(0.55))
                Text("Capture intent")
                    .font(p.font(.body))
                    .foregroundStyle(p.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(p.chromeSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(p.hairline, lineWidth: 0.5)
            )
        }
        .widgetAccentable()
    }
}

private struct UpcomingRow: View {
    let palette: WidgetPalette
    let item: TodayWidgetItem

    var body: some View {
        let p = palette
        HStack(alignment: .center, spacing: 10) {
            // 2pt accent rail — matches the in-app row anatomy exactly.
            // Color is type-aware so the row visually reads as a task /
            // reminder / idea at a glance.
            Rectangle()
                .fill(railColor(for: item.typeRaw, palette: p))
                .frame(width: 2)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(p.font(.body))
                    .foregroundStyle(p.textPrimary)
                    .lineLimit(1)
                metaLine
            }
            Spacer(minLength: 6)
            if let due = item.dueDate {
                Text(due, style: .time)
                    .font(p.font(.caption))
                    .monospacedDigit()
                    .foregroundStyle(p.textSecondary)
            }
        }
        .frame(minHeight: 28)
    }

    /// Mirrors the in-app `TaskType` accent map (clinical mint / clay /
    /// pale-lilac). Hex literals avoid a cross-target import of
    /// `DesignTokens.Accent`.
    private func railColor(for typeRaw: String, palette p: WidgetPalette) -> Color {
        switch typeRaw {
        case "todo":     return Color(red: 0.55, green: 0.85, blue: 0.78) // mint
        case "reminder": return Color(red: 0.92, green: 0.74, blue: 0.52) // clay amber
        case "idea":     return Color(red: 0.78, green: 0.76, blue: 0.92) // pale slate-lilac
        default:         return p.accent.opacity(0.55)
        }
    }

    private var metaLine: some View {
        let p = palette
        return HStack(spacing: 0) {
            Text(item.typeRaw.uppercased())
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .foregroundStyle(p.textTertiary)
            if let tag = item.ideaTag, !tag.isEmpty {
                Text("  ·  #\(tag.uppercased())")
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .foregroundStyle(p.textTertiary)
            }
        }
        .lineLimit(1)
    }
}

// MARK: - Previews

#Preview("Small — Dark", as: .systemSmall) {
    AvenorWidget()
} timeline: {
    AvenorEntry(date: .now, today: .placeholder, palette: .starkDark)
}

#Preview("Medium — Light", as: .systemMedium) {
    AvenorWidget()
} timeline: {
    AvenorEntry(date: .now, today: .placeholder, palette: .starkLight)
}

#Preview("Large — Liquid Glass", as: .systemLarge) {
    AvenorWidget()
} timeline: {
    AvenorEntry(date: .now, today: .placeholder, palette: .liquidGlass)
}

#Preview("Large — Calm Earth", as: .systemLarge) {
    AvenorWidget()
} timeline: {
    AvenorEntry(date: .now, today: .placeholder, palette: .calmEarth)
}
