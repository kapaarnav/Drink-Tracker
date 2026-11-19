import ActivityKit
import SwiftUI
import WidgetKit
import DrinkTrackerCore

@main struct DrinkTrackerWidgets: WidgetBundle {
    var body: some Widget { DrinkTrackerActivity() }
}

struct DrinkTrackerActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrackingActivityAttributes.self) { context in
            ActivityRows(context: context)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .activityBackgroundTint(Color(.secondarySystemBackground))
                .activitySystemActionForegroundColor(.primary)
                .widgetURL(URL(string: "drinktracker://tracking"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) { ActivityRows(context: context) }
            } compactLeading: {
                Image(systemName: "chart.bar.xaxis")
            } compactTrailing: {
                Text("🍺\(context.state.drinks) 💧\(context.state.water) 🥤\(context.state.rageCage)")
                    .font(.caption2).monospacedDigit()
                    .accessibilityLabel("\(context.state.drinks) drinks, \(context.state.water) water glasses, \(context.state.rageCage) rage cage cups")
            } minimal: {
                Image(systemName: "chart.bar.xaxis")
            }
            .widgetURL(URL(string: "drinktracker://tracking"))
        }
    }
}

private struct ActivityRows: View {
    let context: ActivityViewContext<TrackingActivityAttributes>
    private var enabled: Bool { context.state.active && !context.isStale && context.state.cutoff > Date() }
    var body: some View {
        VStack(spacing: 0) {
            ForEach(DrinkCategory.allCases) { category in
                HStack(spacing: 8) {
                    Text(category.emoji).font(.body).accessibilityHidden(true)
                    TallyView(count: count(category), height: 16)
                    Text(count(category).formatted()).font(.body.bold()).monospacedDigit()
                        .minimumScaleFactor(0.6).lineLimit(1)
                        .accessibilityLabel("\(category.title), \(count(category))")
                    button(category, delta: -1)
                    button(category, delta: 1)
                }.frame(minHeight: 44)
            }
            if let message = context.state.message {
                Text(message).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            } else if !enabled {
                Text("Tracking ended · open app").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private func count(_ category: DrinkCategory) -> Int {
        switch category { case .drinks: context.state.drinks; case .water: context.state.water; case .rageCage: context.state.rageCage }
    }
    private func button(_ category: DrinkCategory, delta: Int) -> some View {
        Button(intent: AdjustCountIntent(day: context.attributes.dayID, period: context.state.periodID,
                                       category: category.rawValue, delta: delta)) {
            Image(systemName: delta == 1 ? "plus" : "minus").font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || (delta == -1 && count(category) == 0))
        .accessibilityLabel("\(delta == 1 ? "Add" : "Remove") \(category.unit)")
    }
}
