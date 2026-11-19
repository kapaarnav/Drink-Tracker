import AppIntents
import Foundation

struct AdjustCountIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Adjust tracking count"
    static let description = IntentDescription("Adjust an already active tracking day.")
    static let openAppWhenRun: Bool = false
    static let isDiscoverable: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @Parameter(title: "Day") var day: String
    @Parameter(title: "Active period") var period: String
    @Parameter(title: "Category") var category: String
    @Parameter(title: "Adjustment") var delta: Int

    init() {}
    init(day: UUID, period: UUID, category: String, delta: Int) {
        self.day = day.uuidString; self.period = period.uuidString
        self.category = category; self.delta = delta
    }
    func perform() async throws -> some IntentResult {
        #if DRINK_TRACKER_APP
        await AppServices.shared.handleIntent(day: day, period: period, category: category, delta: delta)
        #endif
        return .result()
    }
}
