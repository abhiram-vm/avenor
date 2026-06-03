//
//  AvenorWidgetLiveActivity.swift
//  AvenorWidget
//
//  Dynamic Countdown Live Activity (Phase 6). Renders a high-priority timed
//  event on the Lock Screen + Dynamic Island, counting down to its start.
//  Driven by `EventCountdownAttributes` (shared with the main app, which
//  starts/updates/ends the activity via `EventLiveActivityManager`).
//
//  The countdown uses SwiftUI's native `Text(timerInterval:)` so it ticks
//  every second on-screen with ZERO process wakeups — the system renders
//  the tick, the activity never re-publishes per second.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct AvenorWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EventCountdownAttributes.self) { context in
            // MARK: Lock Screen / banner
            LockScreenCountdownView(context: context)
                .activitySystemActionForegroundColor(palette(for: context).textPrimary)

        } dynamicIsland: { context in
            let p = palette(for: context)
            let accent = Color.fromWidgetHex(context.attributes.accentHex)

            return DynamicIsland {
                // Expanded — full-width: clean title (left), live countdown (right).
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.title)
                            .font(.system(size: 16, weight: .semibold, design: p.fontDesign))
                            .foregroundStyle(p.textPrimary)
                            .lineLimit(1)
                        Text("UPCOMING EVENT")
                            .font(.system(size: 10, weight: .semibold, design: p.fontDesign))
                            .tracking(p.microTracking)
                            .foregroundStyle(p.textSecondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdownText(to: context.state.eventStart, font: .system(size: 22, weight: .bold, design: p.fontDesign))
                        .foregroundStyle(accent)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } compactLeading: {
                Image(systemName: "circle.dashed")
                    .foregroundStyle(accent)
            } compactTrailing: {
                countdownText(to: context.state.eventStart, font: .system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(p.textPrimary)
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "circle.dashed")
                    .foregroundStyle(accent)
            }
            .keylineTint(accent)
        }
    }

    /// Resolves the widget palette from the attributes' theme token, falling
    /// back to Stark Dark when the raw value is unknown.
    private func palette(for context: ActivityViewContext<EventCountdownAttributes>) -> WidgetPalette {
        let id = WidgetThemeID(rawValue: context.attributes.themeRaw) ?? .dark
        return .make(for: id)
    }

    /// Native ticking countdown, clamped so an already-started event renders
    /// "0:00" rather than crashing on an inverted range.
    private func countdownText(to start: Date, font: Font) -> some View {
        let safeEnd = max(start, Date.now)
        return Text(timerInterval: Date.now...safeEnd, countsDown: true)
            .font(font)
            .monospacedDigit()
    }
}

// MARK: - Lock Screen card
//
// Mimics the `.liquidGlass` style: a soft mesh-tinted gradient behind an
// ultra-thin material card with a specular top edge. Left column = title +
// uppercase tracked metadata; right column = live ticking countdown.

private struct LockScreenCountdownView: View {
    let context: ActivityViewContext<EventCountdownAttributes>

    var body: some View {
        let id = WidgetThemeID(rawValue: context.attributes.themeRaw) ?? .liquidGlass
        let p = WidgetPalette.make(for: id)
        let accent = Color.fromWidgetHex(context.attributes.accentHex)
        let safeEnd = max(context.state.eventStart, Date.now)

        HStack(alignment: .center, spacing: 14) {
            // Left: title + metadata
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.title)
                    .font(.system(size: 19, weight: .semibold, design: p.fontDesign))
                    .tracking(p.headlineTracking)
                    .foregroundStyle(p.textPrimary)
                    .lineLimit(1)
                Text("UPCOMING EVENT")
                    .font(.system(size: 11, weight: .semibold, design: p.fontDesign))
                    .tracking(p.microTracking)
                    .foregroundStyle(p.textSecondary)
            }

            Spacer(minLength: 8)

            // Right: live ticking countdown
            VStack(alignment: .trailing, spacing: 2) {
                Text("STARTS IN")
                    .font(.system(size: 9, weight: .semibold, design: p.fontDesign))
                    .tracking(p.microTracking)
                    .foregroundStyle(p.textTertiary)
                Text(timerInterval: Date.now...safeEnd, countsDown: true)
                    .font(.system(size: 26, weight: .bold, design: p.fontDesign))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .frame(minWidth: 78, alignment: .trailing)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(lockScreenBackground(palette: p))
    }

    @ViewBuilder
    private func lockScreenBackground(palette p: WidgetPalette) -> some View {
        ZStack {
            // Static mesh-spectrum snapshot behind the material.
            if case let .gradient(stops, start, end) = p.canvas {
                LinearGradient(stops: stops, startPoint: start, endPoint: end)
            } else if case let .solid(color) = p.canvas {
                color
            }
            Rectangle().fill(.ultraThinMaterial)
        }
        .overlay(alignment: .top) {
            // Specular top edge — the Liquid Glass signature highlight.
            LinearGradient(colors: [.white.opacity(0.45), .clear],
                           startPoint: .top, endPoint: .center)
                .frame(height: 2)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Previews

extension EventCountdownAttributes {
    fileprivate static var preview: EventCountdownAttributes {
        EventCountdownAttributes(title: "Presentation", themeRaw: "liquidGlass", accentHex: "#FFFFFFFF")
    }
}

extension EventCountdownAttributes.ContentState {
    fileprivate static var soon: EventCountdownAttributes.ContentState {
        .init(eventStart: Date.now.addingTimeInterval(15 * 60))
    }
}

#Preview("Lock Screen", as: .content, using: EventCountdownAttributes.preview) {
    AvenorWidgetLiveActivity()
} contentStates: {
    EventCountdownAttributes.ContentState.soon
}
