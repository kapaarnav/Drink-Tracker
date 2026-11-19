import Foundation
import Observation
import SwiftData
import DrinkTrackerCore

@MainActor @Observable final class AppServices {
    static let shared = AppServices()
    @ObservationIgnored private var coordinator: TrackingCoordinator?
    private let activities = LiveActivityManager()
    private(set) var days: [DaySnapshot] = []
    private(set) var busy = false
    private(set) var storageError: String?
    var actionError: String?
    private(set) var cardStatus: String?
    var current: DaySnapshot? { days.first { $0.effectiveState(at: Date()) != .finalized } }

    init() {
        coordinator = nil
        _ = loadCoordinator()
    }
    private func loadCoordinator() -> TrackingCoordinator? {
        if let coordinator { return coordinator }
        do {
            let loaded = TrackingCoordinator(modelContainer: try TrackerStorage.makeContainer(
                inMemory: ProcessInfo.processInfo.arguments.contains("--ui-testing")))
            coordinator = loaded
            storageError = nil
            return loaded
        } catch {
            storageError = error.localizedDescription
            return nil
        }
    }
    private func accept(_ snapshots: [DaySnapshot]) {
        var latest = Dictionary(uniqueKeysWithValues: days.map { ($0.id, $0) })
        for snapshot in snapshots where snapshot.revision >= (latest[snapshot.id]?.revision ?? 0) {
            latest[snapshot.id] = snapshot
        }
        days = latest.values.sorted { $0.window.start > $1.window.start }
    }
    func refresh(observeDeadline: Bool = false) async {
        guard let coordinator = loadCoordinator() else { return }
        do {
            accept(try await coordinator.reconcile(observedEndingZone: observeDeadline ? .current : nil))
            await publishLatest()
        } catch { storageError = error.localizedDescription }
    }
    private func publishLatest(request: Bool = false) async {
        // Read again after actor suspension, rather than publishing an older command result.
        guard let coordinator = loadCoordinator() else { return }
        do {
            accept(try await coordinator.history())
            await activities.publish(current, request: request)
            cardStatus = activities.status
        } catch { actionError = error.localizedDescription }
    }
    func start() async {
        await perform(request: true) { c in _ = try await c.start(invokedAt: Date(), zone: .current) }
    }
    func pause() async {
        guard let day = current else { return }
        await perform { c in _ = try await c.pause(dayID: day.id, invokedAt: Date(), zone: .current) }
    }
    func resume() async {
        guard let day = current else { return }
        await perform(request: true) { c in _ = try await c.resume(dayID: day.id, invokedAt: Date(), zone: .current) }
    }
    func adjust(_ category: DrinkCategory, delta: Int) async {
        guard let day = current, let period = day.activePeriodID else { return }
        await perform { c in _ = try await c.adjust(dayID: day.id, periodID: period, category: category, delta: delta) }
    }
    private func perform(request: Bool = false, _ operation: @Sendable (TrackingCoordinator) async throws -> Void) async {
        guard let coordinator = loadCoordinator() else { return }
        busy = true
        defer { busy = false }
        do { try await operation(coordinator); await publishLatest(request: request) }
        catch { actionError = error.localizedDescription; await publishLatest() }
    }
    func restoreCard() async { await publishLatest(request: true) }
    func handleIntent(day: String, period: String, category: String, delta: Int) async {
        guard let coordinator = loadCoordinator(), let dayID = UUID(uuidString: day), let periodID = UUID(uuidString: period),
              let category = DrinkCategory(rawValue: category) else { return }
        do {
            _ = try await coordinator.adjust(dayID: dayID, periodID: periodID, category: category, delta: delta)
            await publishLatest()
        } catch {
            actionError = error.localizedDescription
            await publishLatest()
            await activities.reportFailure(error)
        }
    }
}
