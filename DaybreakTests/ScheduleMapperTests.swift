import Foundation
import Testing
@testable import Daybreak

private func calendar(_ tz: String) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: tz)!
    return c
}

private func date(_ s: String, _ cal: Calendar) -> Date {
    let f = DateFormatter()
    f.calendar = cal
    f.timeZone = cal.timeZone
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: s)!
}

private func string(_ d: Date, _ cal: Calendar) -> String {
    let f = DateFormatter()
    f.calendar = cal
    f.timeZone = cal.timeZone
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.string(from: d)
}

struct WeekdayShiftTests {
    @Test func midnightShiftsBackOneDay() {
        let offsets = SequenceGenerator.offsets(for: .fibonacci(windowMinutes: 60, firstGap: 2))
        let alarms = ScheduleMapper.wallClockAlarms(targetHour: 0, targetMinute: 20, offsets: offsets, repeatDays: [.monday])
        #expect(alarms[0].hour == 23 && alarms[0].minute == 20 && alarms[0].dayShift == -1)
        #expect(alarms[0].weekdays == [.sunday])
        #expect(alarms[1].weekdays == [.sunday])
        #expect(alarms[2].hour == 0 && alarms[2].minute == 2 && alarms[2].weekdays == [.monday])
        #expect(alarms.last!.weekdays == [.monday])
    }

    @Test func weekWraps() {
        #expect(ScheduleMapper.shift([.sunday, .monday], by: -1) == [.saturday, .sunday])
        #expect(ScheduleMapper.shift([.saturday], by: 1) == [.sunday])
    }

    @Test func afterMidnightShiftsForward() {
        let offsets = SequenceGenerator.offsets(for: .interval(count: 2, minutes: 10, direction: .after))
        let alarms = ScheduleMapper.wallClockAlarms(targetHour: 23, targetMinute: 55, offsets: offsets, repeatDays: [.friday])
        #expect(alarms.map(\.dayShift) == [0, 1, 1])
        #expect(alarms[2].hour == 0 && alarms[2].minute == 15 && alarms[2].weekdays == [.saturday])
    }
}

struct OneOffTests {
    let cal = calendar("Europe/London")

    @Test func targetLaterTodayStaysToday() {
        let t = ScheduleMapper.resolveOneOffTarget(hour: 9, minute: 0, now: date("2026-10-26 07:00", cal), calendar: cal)
        #expect(string(t, cal) == "2026-10-26 09:00")
    }

    @Test func pastTargetMovesToTomorrow() {
        let t = ScheduleMapper.resolveOneOffTarget(hour: 9, minute: 0, now: date("2026-10-26 09:00", cal), calendar: cal)
        #expect(string(t, cal) == "2026-10-27 09:00")
    }

    @Test func skipsPastEarlierAlarms() {
        let offsets = SequenceGenerator.offsets(for: .fibonacci(windowMinutes: 60, firstGap: 2))
        let r = ScheduleMapper.oneOffDates(target: date("2026-10-26 09:00", cal), offsets: offsets,
                                           now: date("2026-10-26 08:30", cal), calendar: cal)
        #expect(r.skippedPast == 2)
        #expect(r.scheduled.map { string($0.date, cal) }.first == "2026-10-26 08:42")
    }

    @Test func crossesMidnightIntoPreviousDay() {
        let offsets = SequenceGenerator.offsets(for: .fibonacci(windowMinutes: 60, firstGap: 2))
        let r = ScheduleMapper.oneOffDates(target: date("2026-10-27 00:20", cal), offsets: offsets,
                                           now: date("2026-10-26 20:00", cal), calendar: cal)
        #expect(string(r.scheduled[0].date, cal) == "2026-10-26 23:20")
        #expect(string(r.scheduled[2].date, cal) == "2026-10-27 00:02")
    }

    @Test func gapsStayExactAcrossFallBack() {
        // UK clocks went back 02:00 BST -> 01:00 GMT on 2026-10-25.
        let target = date("2026-10-25 01:30", cal) // first 01:30 is ambiguous; formatter picks one
        let r = ScheduleMapper.oneOffDates(target: target, offsets: [AlarmOffset(-60), AlarmOffset(0)],
                                           now: date("2026-10-24 12:00", cal), calendar: cal)
        #expect(r.scheduled[1].date.timeIntervalSince(r.scheduled[0].date) == 3600)
    }
}

struct NextFireDateTests {
    let cal = calendar("America/Toronto")

    @Test func weekdayWrap() {
        // 2026-10-30 is a Friday.
        let next = ScheduleMapper.nextFireDate(hour: 9, minute: 0, weekdays: [.monday],
                                               after: date("2026-10-30 10:00", cal), calendar: cal)
        #expect(string(next!, cal) == "2026-11-02 09:00")
    }

    @Test func sameDayLater() {
        let next = ScheduleMapper.nextFireDate(hour: 9, minute: 0, weekdays: [.monday, .friday],
                                               after: date("2026-10-30 08:59", cal), calendar: cal)
        #expect(string(next!, cal) == "2026-10-30 09:00")
    }

    @Test func oneOffWrapsPastMidnight() {
        let next = ScheduleMapper.nextFireDate(hour: 0, minute: 20, weekdays: [],
                                               after: date("2026-10-30 23:00", cal), calendar: cal)
        #expect(string(next!, cal) == "2026-10-31 00:20")
    }

    @Test func wallClockHeldAcrossDST() {
        // Toronto falls back on 2026-11-01. A 09:00 alarm stays 09:00 local.
        let next = ScheduleMapper.nextFireDate(hour: 9, minute: 0, weekdays: [.sunday],
                                               after: date("2026-10-31 12:00", cal), calendar: cal)
        #expect(string(next!, cal) == "2026-11-01 09:00")
    }

    @Test func skippedSpringForwardHourMovesLater() {
        // Toronto springs forward 02:00 -> 03:00 on 2027-03-14.
        let next = ScheduleMapper.nextFireDate(hour: 2, minute: 30, weekdays: [.sunday],
                                               after: date("2027-03-13 12:00", cal), calendar: cal)
        #expect(string(next!, cal) == "2027-03-14 03:30")
    }
}

struct CountdownFormatterTests {
    static let cases: [(Double, String)] = [
        (30, "under 1m"), (60, "1m"), (2520, "42m"), (3600, "1h"),
        (27779, "7h 42m"), (97200, "1d 3h"), (172800, "2d"),
    ]

    @Test(arguments: cases)
    func formats(seconds: Double, expected: String) {
        let now = Date(timeIntervalSince1970: 0)
        #expect(CountdownFormatter.string(from: now, to: now.addingTimeInterval(seconds)) == expected)
    }
}
