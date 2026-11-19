import ActivityKit
import DrinkTrackerCore
import Foundation

@MainActor final class LiveActivityManager {
    private(set) var status: String?
    private var pending: (DaySnapshot?, Bool)?
    private var publishing = false
    private var latestRevision: [UUID: Int] = [:]
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func publish(_ day: DaySnapshot?, request: Bool = false) async {
        if let day {
            guard day.revision >= (latestRevision[day.id] ?? 0) else { return }
            latestRevision[day.id] = day.revision
        }
        pending = (day, request || pending?.1 == true)
        if publishing {
            await withCheckedContinuation { waiters.append($0) }
            return
        }
        publishing = true
        while let next = pending {
            pending = nil
            await apply(next.0, request: next.1)
        }
        publishing = false
        let finished = waiters; waiters.removeAll()
        finished.forEach { $0.resume() }
    }
    private func content(_ day: DaySnapshot, message: String? = nil) -> ActivityContent<TrackingActivityAttributes.ContentState> {
        ActivityContent(state: .init(drinks: day.drinks, water: day.water, rageCage: day.rageCage,
            periodID: day.activePeriodID ?? UUID(), revision: day.revision, cutoff: day.window.end,
            active: day.state == .active && day.window.end > Date(), message: message), staleDate: day.window.end)
    }
    private func apply(_ day: DaySnapshot?, request: Bool) async {
        let active = day.flatMap { $0.state == .active && $0.window.end > Date() ? $0 : nil }
        var matched: Activity<TrackingActivityAttributes>?
        for activity in Activity<TrackingActivityAttributes>.activities {
            if let active, activity.attributes.dayID == active.id,
               activity.content.state.periodID == active.activePeriodID,
               activity.activityState == .active || activity.activityState == .stale,
               matched == nil {
                matched = activity
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        guard let active else { status = nil; return }
        if let matched {
            await matched.update(content(active)); status = nil
        } else if request {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                status = "Live Activities are unavailable. Check Settings; tracking still works here."; return
            }
            do {
                _ = try Activity.request(attributes: TrackingActivityAttributes(dayID: active.id, label: active.window.label),
                                         content: content(active), pushType: nil)
                status = nil
            } catch { status = "Couldn’t show the Lock Screen card. \(error.localizedDescription)" }
        } else {
            status = "Your Lock Screen card isn’t active. Tracking still works here."
        }
    }
    func reportFailure(_ error: Error) async {
        for activity in Activity<TrackingActivityAttributes>.activities {
            var state = activity.content.state
            state.message = "Couldn’t save. Open Drink Tracker."
            await activity.update(ActivityContent(state: state, staleDate: state.cutoff))
        }
    }
}
