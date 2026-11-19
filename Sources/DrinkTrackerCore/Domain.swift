import Foundation

public enum DrinkCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case drinks, water, rageCage
    public var id: String { rawValue }
    public var title: String {
        switch self { case .drinks: "Drinks"; case .water: "Water"; case .rageCage: "Rage cage" }
    }
    public var emoji: String {
        switch self { case .drinks: "🍺"; case .water: "💧"; case .rageCage: "🥤" }
    }
    public var unit: String {
        switch self { case .drinks: "drink"; case .water: "glass of water"; case .rageCage: "rage cage cup" }
    }
}

public enum TrackingState: String, Codable, Sendable { case active, paused, finalized }
public enum LifecycleKind: String, Codable, Sendable { case started, paused, resumed }
public enum ZoneBasis: String, Codable, Sendable { case current, handoff, fallback }

public struct TrackingWindow: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let label: String
    public let timeZoneID: String
    public let basis: ZoneBasis
    public var key: String { "\(Int64(start.timeIntervalSince1970)):\(Int64(end.timeIntervalSince1970))" }
    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

public struct EventSnapshot: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let kind: LifecycleKind
    public let occurredAt: Date
    public let sequence: Int
    public let timeZoneID: String
    public let utcOffset: Int
}

public struct DaySnapshot: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let window: TrackingWindow
    public let firstStartedAt: Date
    public let drinks: Int
    public let water: Int
    public let rageCage: Int
    public let state: TrackingState
    public let finalizedAt: Date?
    public let activePeriodID: UUID?
    public let revision: Int
    public let endingTimeZoneID: String?
    public let events: [EventSnapshot]

    public subscript(_ category: DrinkCategory) -> Int {
        switch category { case .drinks: drinks; case .water: water; case .rageCage: rageCage }
    }
    public func effectiveState(at now: Date) -> TrackingState { now >= window.end ? .finalized : state }
    public var displayDate: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = window.label.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))!
    }
}

public enum TrackingError: LocalizedError, Sendable {
    case noActiveDay, invalidPeriod, cutoffReached, invalidAdjustment, overlappingWindow, clockMovedBack, overflow
    public var errorDescription: String? {
        switch self {
        case .noActiveDay: "Tracking is paused or no day has been started."
        case .invalidPeriod: "This control belongs to an earlier tracking period. Open the app to refresh it."
        case .cutoffReached: "This tracking day has finished. Its totals are now final."
        case .invalidAdjustment: "Counts can only change by one."
        case .overlappingWindow: "A tracking day already exists for this time window."
        case .clockMovedBack: "The device clock is earlier than the last finalized day. Check Date & Time settings."
        case .overflow: "This count has reached the supported integer limit."
        }
    }
}
