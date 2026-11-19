import Foundation

public enum WindowPolicy {
    private static func calendar(_ zone: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }
    private static func label(_ date: Date, calendar c: Calendar) -> String {
        let parts = c.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    private static func fourAM(_ day: Date, calendar c: Calendar) -> Date {
        c.date(bySettingHour: 4, minute: 0, second: 0, of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first)!
    }
    public static func ordinary(at now: Date, zone: TimeZone, basis: ZoneBasis = .current) -> TrackingWindow {
        let c = calendar(zone)
        let today = c.startOfDay(for: now)
        let boundary = fourAM(today, calendar: c)
        let labelDay = now < boundary ? c.date(byAdding: .day, value: -1, to: today)! : today
        return TrackingWindow(start: fourAM(labelDay, calendar: c),
                              end: fourAM(c.date(byAdding: .day, value: 1, to: labelDay)!, calendar: c),
                              label: label(labelDay, calendar: c), timeZoneID: zone.identifier, basis: basis)
    }
    public static func resolve(at now: Date, zone: TimeZone, previous: DaySnapshot?) throws -> TrackingWindow {
        guard let previous else { return ordinary(at: now, zone: zone) }
        guard now >= previous.window.end else { throw TrackingError.clockMovedBack }
        if let endingID = previous.endingTimeZoneID, let endingZone = TimeZone(identifier: endingID) {
            let c = calendar(endingZone)
            let parts = previous.window.label.split(separator: "-").compactMap { Int($0) }
            let priorLabel = c.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))!
            var candidateDate = c.date(byAdding: .day, value: 2, to: priorLabel)!
            var end = fourAM(candidateDate, calendar: c)
            while end <= previous.window.end {
                candidateDate = c.date(byAdding: .day, value: 1, to: candidateDate)!
                end = fourAM(candidateDate, calendar: c)
            }
            if now < end {
                let labelDay = c.date(byAdding: .day, value: -1, to: candidateDate)!
                return TrackingWindow(start: previous.window.end, end: end, label: label(labelDay, calendar: c),
                                      timeZoneID: endingID, basis: .handoff)
            }
        }
        let fallback = ordinary(at: now, zone: zone, basis: .fallback)
        return TrackingWindow(start: max(fallback.start, previous.window.end), end: fallback.end,
                              label: fallback.label, timeZoneID: fallback.timeZoneID, basis: .fallback)
    }
}
