import Foundation
import Testing
import SwiftData
@testable import DrinkTrackerCore

private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
private let ny = TimeZone(identifier: "America/New_York")!
private let la = TimeZone(identifier: "America/Los_Angeles")!

@Test func ordinaryWindowsAndDST() {
    let before = WindowPolicy.ordinary(at: date("2027-01-08T06:00:00Z"), zone: ny)
    #expect(before.label == "2027-01-07")
    #expect(before.end == date("2027-01-08T09:00:00Z"))
    let boundary = WindowPolicy.ordinary(at: before.end, zone: ny)
    #expect(boundary.label == "2027-01-08")
    #expect(WindowPolicy.ordinary(at: date("2027-03-13T18:00:00Z"), zone: ny).duration == 23 * 3600)
    #expect(WindowPolicy.ordinary(at: date("2027-11-06T18:00:00Z"), zone: ny).duration == 25 * 3600)
}

@Test func lifecycleCountsAndImmutableCutoff() async throws {
    let store = try TrackerStorage.makeContainer(inMemory: true)
    let c = TrackingCoordinator(modelContainer: store)
    let now = date("2027-01-08T20:00:00Z")
    let command = UUID()
    let first = try await c.start(commandID: command, processingAt: now, zone: ny)
    let duplicate = try await c.start(commandID: command, processingAt: now, zone: ny)
    #expect(first.id == duplicate.id)
    let floor = try await c.adjust(dayID: first.id, periodID: first.activePeriodID!, category: .water, delta: -1, processingAt: now)
    #expect(floor.water == 0)
    let changed = try await c.adjust(dayID: first.id, periodID: first.activePeriodID!, category: .rageCage, delta: 1, processingAt: now)
    #expect(changed.drinks == 0 && changed.water == 0 && changed.rageCage == 1)
    let paused = try await c.pause(dayID: first.id, processingAt: now, zone: ny)
    #expect(paused.state == .paused)
    let resumed = try await c.resume(dayID: first.id, processingAt: now, zone: la)
    _ = try await c.pause(dayID: first.id, processingAt: now, zone: la)
    let secondResume = try await c.resume(dayID: first.id, processingAt: now, zone: la)
    #expect(secondResume.events.map(\.kind) == [.started, .paused, .resumed, .paused, .resumed])
    #expect(secondResume.events.map(\.sequence) == [0, 1, 2, 3, 4])
    #expect(secondResume.firstStartedAt == now && secondResume.window == first.window)
    #expect(secondResume.rageCage == 1 && resumed.activePeriodID != first.activePeriodID)
    await #expect(throws: TrackingError.self) {
        try await c.adjust(dayID: first.id, periodID: first.activePeriodID!, category: .drinks, delta: 1, processingAt: now)
    }
    await #expect(throws: TrackingError.self) {
        try await c.adjust(dayID: first.id, periodID: secondResume.activePeriodID!, category: .water, delta: 1, processingAt: first.window.end)
    }
    let history = try await c.history(processingAt: first.window.end.addingTimeInterval(86400))
    #expect(history.count == 1 && history[0].state == .finalized)
    #expect(history[0].finalizedAt == first.window.end && history[0].events.count == 5)
}

@Test func travelWindowsAndDateLine() async throws {
    for (origin, destination, hours) in [
        ("America/New_York", "America/Los_Angeles", 27),
        ("Asia/Tokyo", "America/New_York", 38),
        ("Pacific/Kiritimati", "Pacific/Honolulu", 48),
        ("Pacific/Honolulu", "Pacific/Kiritimati", 24)
    ] {
        let zone = TimeZone(identifier: origin)!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        let start = cal.date(from: DateComponents(year: 2027, month: 1, day: 8, hour: 15))!
        let c = TrackingCoordinator(modelContainer: try TrackerStorage.makeContainer(inMemory: true))
        let first = try await c.start(processingAt: start, zone: zone)
        let dest = TimeZone(identifier: destination)!
        _ = try await c.reconcile(processingAt: first.window.end, observedEndingZone: dest)
        let next = try await c.start(processingAt: first.window.end, zone: dest)
        #expect(next.window.duration == Double(hours * 3600))
        #expect(next.window.start == first.window.end)
        #expect(next.id != first.id && next.drinks == 0)
    }
}

@Test func unknownZoneAndGapUseCurrentZone() async throws {
    let c = TrackingCoordinator(modelContainer: try TrackerStorage.makeContainer(inMemory: true))
    let first = try await c.start(processingAt: date("2027-01-08T20:00:00Z"), zone: ny)
    let later = first.window.end.addingTimeInterval(5 * 86400)
    let next = try await c.start(processingAt: later, zone: la)
    #expect(next.window.timeZoneID == la.identifier && next.window.basis == .fallback)
    #expect(try await c.history(processingAt: later).count == 2)
}

@Test func concurrentTapsDoNotLoseCounts() async throws {
    let c = TrackingCoordinator(modelContainer: try TrackerStorage.makeContainer(inMemory: true))
    let now = date("2027-01-08T20:00:00Z")
    let first = try await c.start(processingAt: now, zone: ny)
    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<30 {
            group.addTask { _ = try await c.adjust(dayID: first.id, periodID: first.activePeriodID!, category: .water, delta: 1, processingAt: now) }
        }
        try await group.waitForAll()
    }
    let result = try await c.history(processingAt: now)
    #expect(result[0].water == 30 && result[0].events.count == 1)
}

@Test func diskRelaunchAndBackupExclusion() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let now = date("2027-01-08T20:00:00Z")
    let firstID: UUID
    do {
        let c = TrackingCoordinator(modelContainer: try TrackerStorage.makeContainer(directory: folder))
        let first = try await c.start(processingAt: now, zone: ny)
        firstID = first.id
        _ = try await c.adjust(dayID: first.id, periodID: first.activePeriodID!, category: .drinks, delta: 1, processingAt: now)
    }
    let reopened = TrackingCoordinator(modelContainer: try TrackerStorage.makeContainer(directory: folder))
    let history = try await reopened.history(processingAt: now)
    #expect(history.count == 1 && history[0].id == firstID && history[0].drinks == 1)
    #expect(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
}

@Test func failedSaveRollsBackStateAndLifecycleEntry() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let now = date("2027-01-08T20:00:00Z")
    let writer = TrackingCoordinator(modelContainer: try TrackerStorage.makeContainer(directory: folder))
    let first = try await writer.start(processingAt: now, zone: ny)
    let schema = Schema(versionedSchema: TrackerSchemaV1.self)
    let config = ModelConfiguration(schema: schema, url: folder.appendingPathComponent("History.store"), allowsSave: false, cloudKitDatabase: .none)
    let readOnly = TrackingCoordinator(modelContainer: try ModelContainer(for: schema, configurations: [config]))
    await #expect(throws: (any Error).self) {
        try await readOnly.pause(dayID: first.id, processingAt: now, zone: ny)
    }
    let result = try await readOnly.history(processingAt: now)
    #expect(result[0].state == .active)
    #expect(result[0].events.count == 1)
    #expect(result[0].activePeriodID == first.activePeriodID)
}

@Test func knownHandoffExpiresWithoutCreatingMissedDays() async throws {
    let c = TrackingCoordinator(modelContainer: try TrackerStorage.makeContainer(inMemory: true))
    let first = try await c.start(processingAt: date("2027-01-08T20:00:00Z"), zone: ny)
    _ = try await c.reconcile(processingAt: first.window.end, observedEndingZone: la)
    let newZone = TimeZone(identifier: "Asia/Tokyo")!
    let later = first.window.end.addingTimeInterval(4 * 86400)
    let next = try await c.start(processingAt: later, zone: newZone)
    #expect(next.window.basis == .fallback && next.window.timeZoneID == newZone.identifier)
    #expect(try await c.history(processingAt: later).count == 2)
}

@Test func readsNeverCreateDaysAndLifecycleRetriesStayIdempotent() async throws {
    let c = TrackingCoordinator(modelContainer: try TrackerStorage.makeContainer(inMemory: true))
    let now = date("2027-01-08T20:00:00Z")
    #expect(try await c.history(processingAt: now).isEmpty)
    let first = try await c.start(processingAt: now, zone: ny)
    let pauseID = UUID(), resumeID = UUID()
    _ = try await c.pause(dayID: first.id, commandID: pauseID, processingAt: now, zone: ny)
    _ = try await c.pause(dayID: first.id, commandID: pauseID, processingAt: now, zone: ny)
    _ = try await c.resume(dayID: first.id, commandID: resumeID, processingAt: now, zone: ny)
    _ = try await c.pause(dayID: first.id, processingAt: now, zone: ny)
    // Replaying an already accepted Resume must not resume a later paused period.
    let replay = try await c.resume(dayID: first.id, commandID: resumeID, processingAt: now, zone: ny)
    #expect(replay.state == .paused && replay.events.count == 4)
}
