import Foundation

/// A generated alarm expressed as a wall-clock time for a repeating group.
struct WallClockAlarm: Hashable, Sendable {
    var offsetMinutes: Int
    var hour: Int
    var minute: Int
    /// Days relative to the target day: -1 when the alarm falls on the previous calendar day.
    var dayShift: Int
    var weekdays: Set<Locale.Weekday>
}

/// Pure mapping from offsets + target to concrete schedules. No AlarmKit.
enum ScheduleMapper {
    /// Calendar order used for weekday shifting (Sunday first, like `Calendar.component(.weekday)`).
    static let weekdayOrder: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]

    static func weekday(forCalendarWeekday value: Int) -> Locale.Weekday {
        weekdayOrder[((value - 1) % 7 + 7) % 7]
    }

    static func shift(_ days: Set<Locale.Weekday>, by shift: Int) -> Set<Locale.Weekday> {
        Set(days.compactMap { day in
            weekdayOrder.firstIndex(of: day).map { weekdayOrder[(($0 + shift) % 7 + 7) % 7] }
        })
    }

    /// Wall-clock time and weekday set for each offset of a repeating group.
    static func wallClockAlarms(targetHour: Int, targetMinute: Int,
                                offsets: [AlarmOffset],
                                repeatDays: Set<Locale.Weekday>) -> [WallClockAlarm] {
        offsets.map { offset in
            let total = targetHour * 60 + targetMinute + offset.minutes
            let dayShift = Int((Double(total) / 1440).rounded(.down))
            let inDay = total - dayShift * 1440
            return WallClockAlarm(offsetMinutes: offset.minutes,
                                  hour: inDay / 60, minute: inDay % 60,
                                  dayShift: dayShift,
                                  weekdays: shift(repeatDays, by: dayShift))
        }
    }

    /// The target date for a one-off group: today at the time if still ahead of `now`, otherwise tomorrow (like Clock).
    static func resolveOneOffTarget(hour: Int, minute: Int, now: Date, calendar: Calendar) -> Date {
        let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today).flatMap {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: $0)
        } ?? today
    }

    /// Absolute fire dates for a one-off group. Offsets are elapsed minutes from the target, so gaps
    /// stay exact across DST changes. Alarms not after `now` are skipped.
    static func oneOffDates(target: Date, offsets: [AlarmOffset], now: Date,
                            calendar: Calendar) -> (scheduled: [(offset: AlarmOffset, date: Date)], skippedPast: Int) {
        var scheduled: [(AlarmOffset, Date)] = []
        var skipped = 0
        for offset in offsets.sorted() {
            guard let date = calendar.date(byAdding: .minute, value: offset.minutes, to: target) else { continue }
            if date > now { scheduled.append((offset, date)) } else { skipped += 1 }
        }
        return (scheduled, skipped)
    }

    /// Next wall-clock fire date strictly after `after` for a weekly alarm (or one-off if `weekdays` is empty).
    static func nextFireDate(hour: Int, minute: Int, weekdays: Set<Locale.Weekday>,
                             after: Date, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        components.second = 0
        if weekdays.isEmpty {
            return calendar.nextDate(after: after, matching: components, matchingPolicy: .nextTimePreservingSmallerComponents)
        }
        return weekdays.compactMap { day -> Date? in
            var c = components
            c.weekday = (weekdayOrder.firstIndex(of: day) ?? 0) + 1
            return calendar.nextDate(after: after, matching: c, matchingPolicy: .nextTimePreservingSmallerComponents)
        }.min()
    }
}

enum CountdownFormatter {
    /// "1d 3h", "7h 42m", "42m", "under 1m". Seconds are dropped (rounded down to the minute).
    static func string(from now: Date, to date: Date) -> String {
        let totalMinutes = Int((date.timeIntervalSince(now) / 60).rounded(.down))
        guard totalMinutes >= 1 else { return "under 1m" }
        let days = totalMinutes / 1440, hours = (totalMinutes % 1440) / 60, minutes = totalMinutes % 60
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(minutes)m"
    }
}
