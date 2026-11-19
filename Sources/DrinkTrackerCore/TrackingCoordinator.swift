import Foundation
import SwiftData

@ModelActor public actor TrackingCoordinator {
    private func records() throws -> [TrackingDay] {
        modelContext.autosaveEnabled = false
        return try modelContext.fetch(FetchDescriptor<TrackingDay>(sortBy: [SortDescriptor(\.windowStartsAt, order: .reverse)]))
    }
    private func commit() throws {
        do { try modelContext.save() } catch { modelContext.rollback(); throw error }
    }
    private func snapshot(_ day: TrackingDay) -> DaySnapshot {
        DaySnapshot(id: day.id,
            window: TrackingWindow(start: day.windowStartsAt, end: day.windowEndsAt, label: day.labelDate,
                                   timeZoneID: day.windowTimeZoneID, basis: ZoneBasis(rawValue: day.zoneBasis) ?? .fallback),
            firstStartedAt: day.firstStartedAt, drinks: day.drinksCount, water: day.waterCount,
            rageCage: day.rageCageCount, state: TrackingState(rawValue: day.state) ?? .finalized,
            finalizedAt: day.finalizedAt, activePeriodID: day.activePeriodID, revision: day.revision,
            endingTimeZoneID: day.endingTimeZoneID,
            events: day.lifecycleEvents.sorted { $0.sequence < $1.sequence }.map {
                EventSnapshot(id: $0.id, kind: LifecycleKind(rawValue: $0.kind) ?? .started,
                              occurredAt: $0.occurredAt, sequence: $0.sequence,
                              timeZoneID: $0.timeZoneID, utcOffset: $0.utcOffset)
            })
    }
    private func append(_ kind: LifecycleKind, to day: TrackingDay, commandID: UUID, now: Date, zone: TimeZone) {
        let event = LifecycleEvent(id: commandID, day: day, kind: kind, now: now, zone: zone)
        modelContext.insert(event)
        // Establish both ends explicitly; SwiftData maintains the inverse relationship.
        if !day.lifecycleEvents.contains(where: { $0.id == commandID }) { day.lifecycleEvents.append(event) }
    }
    private func alreadyApplied(_ id: UUID, days: [TrackingDay]) -> TrackingDay? {
        days.first { $0.lifecycleEvents.contains { $0.id == id } }
    }
    private func finalizeOverdue(_ days: [TrackingDay], now: Date, observedZone: TimeZone?) throws {
        var changed = false
        for day in days where day.state != TrackingState.finalized.rawValue && now >= day.windowEndsAt {
            day.state = TrackingState.finalized.rawValue; day.finalizedAt = day.windowEndsAt
            day.activePeriodID = nil; day.updatedAt = now; day.revision += 1
            // Only the foreground deadline observer may supply this. Ordinary late reconciliation cannot.
            if let observedZone {
                day.endingTimeZoneID = observedZone.identifier; day.endingZoneObservedAt = now
            }
            changed = true
        }
        if changed { try commit() }
    }
    public func history(processingAt: Date? = nil) throws -> [DaySnapshot] {
        let days = try records()
        try finalizeOverdue(days, now: processingAt ?? Date(), observedZone: nil)
        return days.map(snapshot)
    }
    public func reconcile(processingAt: Date? = nil, observedEndingZone: TimeZone? = nil) throws -> [DaySnapshot] {
        let days = try records()
        try finalizeOverdue(days, now: processingAt ?? Date(), observedZone: observedEndingZone)
        return days.map(snapshot)
    }
    public func start(commandID: UUID = UUID(), invokedAt: Date? = nil,
                      processingAt: Date? = nil, zone: TimeZone = .current) throws -> DaySnapshot {
        let now = processingAt ?? Date()
        let days = try records()
        try finalizeOverdue(days, now: now, observedZone: nil)
        if let prior = alreadyApplied(commandID, days: days) { return snapshot(prior) }
        if let existing = days.first(where: { $0.state != TrackingState.finalized.rawValue }) { return snapshot(existing) }
        let window = try WindowPolicy.resolve(at: now, zone: zone, previous: days.first.map(snapshot))
        guard window.start <= now, window.end > now else { throw TrackingError.clockMovedBack }
        guard !days.contains(where: { $0.windowStartsAt < window.end && window.start < $0.windowEndsAt }) else {
            throw TrackingError.overlappingWindow
        }
        let day = TrackingDay(window: window, now: invokedAt ?? now)
        modelContext.insert(day)
        append(.started, to: day, commandID: commandID, now: invokedAt ?? now, zone: zone)
        try commit()
        return snapshot(day)
    }
    public func pause(dayID: UUID, commandID: UUID = UUID(), invokedAt: Date? = nil,
                      processingAt: Date? = nil, zone: TimeZone = .current) throws -> DaySnapshot {
        let now = processingAt ?? Date(); let days = try records()
        try finalizeOverdue(days, now: now, observedZone: nil)
        guard let day = days.first(where: { $0.id == dayID }) else { throw TrackingError.noActiveDay }
        if alreadyApplied(commandID, days: days) != nil { return snapshot(day) }
        guard now < day.windowEndsAt, day.state != TrackingState.finalized.rawValue else { throw TrackingError.cutoffReached }
        guard day.state == TrackingState.active.rawValue else { return snapshot(day) }
        day.state = TrackingState.paused.rawValue; day.activePeriodID = nil
        day.revision += 1; day.updatedAt = now
        append(.paused, to: day, commandID: commandID, now: invokedAt ?? now, zone: zone)
        try commit(); return snapshot(day)
    }
    public func resume(dayID: UUID, commandID: UUID = UUID(), invokedAt: Date? = nil,
                       processingAt: Date? = nil, zone: TimeZone = .current) throws -> DaySnapshot {
        let now = processingAt ?? Date(); let days = try records()
        try finalizeOverdue(days, now: now, observedZone: nil)
        guard let day = days.first(where: { $0.id == dayID }) else { throw TrackingError.noActiveDay }
        if alreadyApplied(commandID, days: days) != nil { return snapshot(day) }
        guard now < day.windowEndsAt, day.state != TrackingState.finalized.rawValue else { throw TrackingError.cutoffReached }
        guard day.state == TrackingState.paused.rawValue else { return snapshot(day) }
        day.state = TrackingState.active.rawValue; day.activePeriodID = UUID()
        day.revision += 1; day.updatedAt = now
        append(.resumed, to: day, commandID: commandID, now: invokedAt ?? now, zone: zone)
        try commit(); return snapshot(day)
    }
    public func adjust(dayID: UUID, periodID: UUID, category: DrinkCategory, delta: Int,
                       processingAt: Date? = nil) throws -> DaySnapshot {
        guard delta == 1 || delta == -1 else { throw TrackingError.invalidAdjustment }
        let now = processingAt ?? Date(); let days = try records()
        try finalizeOverdue(days, now: now, observedZone: nil)
        guard let day = days.first(where: { $0.id == dayID }) else { throw TrackingError.noActiveDay }
        guard now < day.windowEndsAt, day.state != TrackingState.finalized.rawValue else { throw TrackingError.cutoffReached }
        guard day.state == TrackingState.active.rawValue else { throw TrackingError.noActiveDay }
        guard day.activePeriodID == periodID else { throw TrackingError.invalidPeriod }
        let count: Int
        switch category { case .drinks: count = day.drinksCount; case .water: count = day.waterCount; case .rageCage: count = day.rageCageCount }
        if delta == -1 && count == 0 { return snapshot(day) }
        let (next, overflow) = count.addingReportingOverflow(delta)
        guard !overflow else { throw TrackingError.overflow }
        switch category { case .drinks: day.drinksCount = next; case .water: day.waterCount = next; case .rageCage: day.rageCageCount = next }
        day.revision += 1; day.updatedAt = now
        try commit(); return snapshot(day)
    }
}
