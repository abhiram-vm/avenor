import SwiftUI
import EventKit

// MARK: - CalendarEventCard
//
// A minimal, high-fidelity row for a read-only system calendar event.
// Deliberately stripped of any interaction affordance — no checkbox, no
// radio, no swipe, no drag. The event is a mirror of the user's calendar;
// the only action is a tap that deep-links into Apple Calendar at the
// event's moment via the `calshow:` scheme.
//
// Visual language follows the daily timeline: a thin left rail colored by
// the source calendar, rounded title, and a muted duration line (or an
// "All Day" pill).

struct CalendarEventCard: View {
    let event: EKEvent
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        let p = theme.palette

        Button(action: openInCalendar) {
            HStack(spacing: 12) {
                // Source-calendar color rail.
                Rectangle()
                    .fill(railColor)
                    .frame(width: 3)
                    .clipShape(Capsule())

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title ?? "Untitled Event")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(p.textPrimary)
                        .lineLimit(1)

                    timeLabel(p)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(p.textTertiary)
            }
            .padding(.vertical, 10)
            .padding(.trailing, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Time presentation

    @ViewBuilder
    private func timeLabel(_ p: ThemePalette) -> some View {
        if event.isAllDay {
            Text("All Day")
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .textCase(.uppercase)
                .foregroundStyle(p.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(p.chromeSurface)
                )
        } else {
            Text(durationText)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(p.textSecondary)
        }
    }

    private var durationText: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return "\(f.string(from: event.startDate)) – \(f.string(from: event.endDate))"
    }

    // MARK: Source-calendar color

    private var railColor: Color {
        if let cg = event.calendar?.cgColor {
            return Color(cgColor: cg)
        }
        return theme.palette.accent
    }

    // MARK: Deep link into Apple Calendar

    private func openInCalendar() {
        AppHaptic.tap()
        // calshow: takes seconds since the reference date (2001-01-01).
        let seconds = Int(event.startDate.timeIntervalSinceReferenceDate)
        guard let url = URL(string: "calshow:\(seconds)") else { return }
        #if os(iOS)
        UIApplication.shared.open(url)
        #endif
    }
}
