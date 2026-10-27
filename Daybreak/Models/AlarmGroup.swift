import Foundation

enum AlarmKind: String, Codable, CaseIterable, Identifiable {
    case regular, target
    var id: Self { self }
    var title: String { self == .regular ? "Regular" : "Target" }
}

enum ClockStyle: String, Codable, CaseIterable, Identifiable {
    case wheel, dial
    var id: Self { self }
    var title: String { self == .wheel ? "Wheel" : "Clock" }
}

enum SequencePreset: String, Codable, CaseIterable, Identifiable {
    case fibonacci, tenMinutes, fiveMinutes, interval, manual
    var id: Self { self }
    var title: String {
        switch self {
        case .fibonacci: "Fibonacci"
        case .tenMinutes: "Every 10 min"
        case .fiveMinutes: "Every 5 min"
        case .interval: "Custom interval"
        case .manual: "Manual"
        }
    }
}

enum AlarmSound: String, Codable, CaseIterable, Identifiable {
    case system, daybreak, chime, pulse
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var filename: String? { self == .system ? nil : "\(rawValue).wav" }
}

struct ChildAlarm: Codable, Identifiable, Hashable {
    var id = UUID()
    var offsetMinutes: Int
    var label = ""
    var isEnabled = true
    var sound: AlarmSound = .system
}

struct AlarmGroup: Codable, Identifiable, Hashable {
    var id = UUID()
    var label = ""
    var kind: AlarmKind = .regular
    var hour = 7
    var minute = 0
    /// Calendar weekdays, Sunday = 1. Repeats refer to the target's day.
    var repeatDays: Set<Int> = []
    var isEnabled = true
    var clockStyle: ClockStyle = .wheel
    var sound: AlarmSound = .system
    var snoozeMinutes = 9
    var snoozeEnabled = true
    var preset: SequencePreset = .fibonacci
    var windowMinutes = 60
    var firstGap = 2
    var intervalMinutes = 5
    var intervalCount = 5
    var direction: IntervalDirection = .before
    var children: [ChildAlarm] = []
    var oneOffTarget: Date?
    var suppressedTarget: Date?

    var displayName: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (kind == .target ? "Wake-up" : "Alarm") : trimmed
    }
    var activeChildren: [ChildAlarm] { kind == .target ? children.filter(\.isEnabled) : [] }
    var offsets: [AlarmOffset] { (activeChildren.map { AlarmOffset($0.offsetMinutes) } + [AlarmOffset(0)]).sorted() }
    var weekdays: Set<Locale.Weekday> { Set(repeatDays.map(ScheduleMapper.weekday(forCalendarWeekday:))) }
    var repeatDescription: String {
        if repeatDays.isEmpty { return "Once" }
        if repeatDays.count == 7 { return "Every day" }
        if repeatDays == Set(2...6) { return "Weekdays" }
        if repeatDays == [1, 7] { return "Weekends" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return [2, 3, 4, 5, 6, 7, 1].filter { repeatDays.contains($0) }.map { symbols[$0 - 1] }.joined(separator: ", ")
    }
    var timeDate: Date {
        get { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now }
        set {
            hour = Calendar.current.component(.hour, from: newValue)
            minute = Calendar.current.component(.minute, from: newValue)
        }
    }
    func clockDate(offset: Int = 0, calendar: Calendar = .current) -> Date {
        let total = ((hour * 60 + minute + offset) % 1440 + 1440) % 1440
        return calendar.date(bySettingHour: total / 60, minute: total % 60, second: 0, of: .now) ?? .now
    }
    func relativeLabel(_ offset: Int) -> String {
        offset < 0 ? "\(-offset) min before" : "\(offset) min after"
    }
    mutating func applyPreset() {
        let generated: [AlarmOffset]
        switch preset {
        case .fibonacci:
            generated = SequenceGenerator.offsets(for: .fibonacci(windowMinutes: windowMinutes, firstGap: firstGap))
        case .fiveMinutes, .tenMinutes:
            let step = preset == .fiveMinutes ? 5 : 10
            generated = Array(Set(SequenceGenerator.offsets(for: .interval(count: windowMinutes / step, minutes: step, direction: .before)) + [AlarmOffset(-windowMinutes)])).sorted()
        case .interval:
            generated = SequenceGenerator.offsets(for: .interval(count: intervalCount, minutes: intervalMinutes, direction: direction))
        case .manual: return
        }
        children = generated.filter { !$0.isTarget }.map { offset in
            children.first(where: { $0.offsetMinutes == offset.minutes }) ?? ChildAlarm(offsetMinutes: offset.minutes, sound: sound)
        }
    }
    var validationError: String? {
        if children.count > 19 && kind == .target { return "Use up to 19 child alarms plus your target. Shorten the window or increase the interval." }
        if kind == .target {
            let values = children.map(\.offsetMinutes)
            if values.contains(0) { return "A child alarm must be before or after the target." }
            if Set(values).count != values.count { return "Two child alarms have the same time. Give each one a different offset." }
            if values.contains(where: { abs($0) > 720 }) { return "Keep child alarms within 12 hours of the target." }
        }
        return nil
    }
    func resolvedTarget(now: Date, calendar: Calendar) -> Date {
        oneOffTarget ?? ScheduleMapper.resolveOneOffTarget(hour: hour, minute: minute, now: now, calendar: calendar)
    }
    func nextFire(now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard isEnabled else { return nil }
        return AlarmPlanner.desired(for: self, now: now, calendar: calendar).compactMap { $0.nextFire(after: now, calendar: calendar) }.min()
    }
}
