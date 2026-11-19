import ActivityKit
import Foundation

struct TrackingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var drinks: Int
        var water: Int
        var rageCage: Int
        var periodID: UUID
        var revision: Int
        var cutoff: Date
        var active: Bool
        var message: String?
    }
    var dayID: UUID
    var label: String
}
