import ActivityKit
import Foundation

/// Everything the Lock Screen and Dynamic Island need, carried in the activity
/// payload itself so the widget extension does not need shared storage.
struct PassActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var primary: String
        var secondary: String
        var symbolName: String
        var countdownVerb: String?
        var countdownStart: Date?
        var countdownEnd: Date?
    }

    var passID: UUID
    var kindLabel: String
}
