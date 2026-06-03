//
//  AvenorWidgetBundle.swift
//  AvenorWidget
//
//  Created by Abhiram Menon on 5/25/26.
//

import WidgetKit
import SwiftUI

// Registered widgets:
//   • AvenorWidget            — the unified date/time + capture glance
//     (small / medium / large), theme-aware layouts.
//   • AvenorTasksWidget       — Phase 6 interactive task & routine widget
//     (small / medium). Requires the App Group capability on BOTH targets.
//   • AvenorWidgetLiveActivity — Phase 6 Dynamic Countdown Live Activity.
//     Requires `NSSupportsLiveActivities = YES` in the main app's Info.plist.
//
// ⚠️ The two Phase 6 entries are INERT until their capabilities are added in
//    Xcode (see the manual setup notes). They compile and register safely
//    without the capabilities — they simply render empty / never fire.
@main
struct AvenorWidgetBundle: WidgetBundle {
    var body: some Widget {
        AvenorWidget()
        AvenorTasksWidget()
        AvenorWidgetLiveActivity()
    }
}
