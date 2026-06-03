import SwiftUI
import WidgetKit

// MARK: - WidgetTokens
//
// Local mirror of the Sophisticated Stark visual atoms needed inside
// widgets. Kept narrowly scoped — only what the two widgets render with.
// If a token here drifts from the main app, sync deliberately; do not
// cross-import `DesignTokens` from the app target.

enum WidgetTokens {
    enum Surface {
        static let canvas       = Color(red: 0.039, green: 0.039, blue: 0.047) // #0A0A0C
        static let cardElevated = Color(red: 0.078, green: 0.078, blue: 0.090) // #141417
    }

    enum Stroke {
        static let hairline  = Color.white.opacity(0.08)
        static let prominent = Color.white.opacity(0.14)
    }

    enum Accent {
        static let primary  = Color.white
        static let todo     = Color(red: 0.62, green: 0.84, blue: 0.71)
        static let reminder = Color(red: 0.86, green: 0.66, blue: 0.42)
        static let idea     = Color(red: 0.74, green: 0.72, blue: 0.84)
    }

    enum Typography {
        static let micro    = Font.system(size: 9,  weight: .semibold)
        static let body     = Font.system(size: 12, weight: .regular)
        static let headline = Font.system(size: 13, weight: .semibold)
        static let title    = Font.system(size: 22, weight: .semibold)
        static let display  = Font.system(size: 28, weight: .bold)
    }

    enum Tracking {
        static let micro: CGFloat = 0.8
        static let display: CGFloat = -0.5
    }

    /// Resolves a task type string to its Stark accent.
    static func accent(forTypeRaw raw: String) -> Color {
        switch raw {
        case "todo":     return Accent.todo
        case "reminder": return Accent.reminder
        case "idea":     return Accent.idea
        default:         return Accent.primary
        }
    }

    static func typeLabel(forTypeRaw raw: String) -> String {
        switch raw {
        case "todo":     return "TODO"
        case "reminder": return "REM"
        case "idea":     return "IDEA"
        default:         return raw.uppercased()
        }
    }
}

// MARK: - Stark widget background container

extension View {
    func starkWidgetContainer() -> some View {
        self
            .containerBackground(for: .widget) {
                WidgetTokens.Surface.canvas
            }
    }
}
