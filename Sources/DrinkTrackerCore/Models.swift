import Foundation
import SwiftData

public enum TrackerSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] { [TrackingDay.self, LifecycleEvent.self] }

    @Model public final class TrackingDay {
        @Attribute(.unique) public var id: UUID
        @Attribute(.unique) public var windowKey: String
        public var labelDate: String
        public var windowStartsAt: Date
        public var windowEndsAt: Date
        public var windowTimeZoneID: String
        public var zoneBasis: String
        public var endingTimeZoneID: String?
        public var endingZoneObservedAt: Date?
        public var firstStartedAt: Date
        public var drinksCount: Int
        public var waterCount: Int
        public var rageCageCount: Int
        public var state: String
        public var finalizedAt: Date?
        public var activePeriodID: UUID?
        public var revision: Int
        public var updatedAt: Date
        @Relationship(deleteRule: .deny, inverse: \LifecycleEvent.trackingDay)
        public var lifecycleEvents: [LifecycleEvent] = []

        public init(window: TrackingWindow, now: Date) {
            id = UUID(); windowKey = window.key; labelDate = window.label
            windowStartsAt = window.start; windowEndsAt = window.end
            windowTimeZoneID = window.timeZoneID; zoneBasis = window.basis.rawValue
            firstStartedAt = now; drinksCount = 0; waterCount = 0; rageCageCount = 0
            state = TrackingState.active.rawValue; activePeriodID = UUID(); revision = 1; updatedAt = now
        }
    }
    @Model public final class LifecycleEvent {
        @Attribute(.unique) public var id: UUID
        public var trackingDay: TrackingDay?
        public var kind: String
        public var occurredAt: Date
        public var sequence: Int
        public var timeZoneID: String
        public var utcOffset: Int
        public init(id: UUID, day: TrackingDay, kind: LifecycleKind, now: Date, zone: TimeZone) {
            self.id = id; trackingDay = day; self.kind = kind.rawValue; occurredAt = now
            sequence = day.lifecycleEvents.count; timeZoneID = zone.identifier
            utcOffset = zone.secondsFromGMT(for: now)
        }
    }
}
public typealias TrackingDay = TrackerSchemaV1.TrackingDay
public typealias LifecycleEvent = TrackerSchemaV1.LifecycleEvent
public enum TrackerMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [TrackerSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

public enum TrackerStorage {
    public static func makeContainer(inMemory: Bool = false, directory: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: TrackerSchemaV1.self)
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            var folder = try directory ?? FileManager.default.url(for: .applicationSupportDirectory,
                  in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("DrinkTrackerStore", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
            config = ModelConfiguration(schema: schema, url: folder.appendingPathComponent("History.store"), cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: TrackerMigrationPlan.self, configurations: [config])
    }
}
