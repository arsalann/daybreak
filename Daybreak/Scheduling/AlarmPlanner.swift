import Foundation

enum PlannedSchedule: Codable, Hashable {
    case fixed(Date)
    case weekly(hour: Int, minute: Int, days: Set<Int>)

    func nextFire(after now: Date, calendar: Calendar) -> Date? {
        switch self {
        case .fixed(let date): return date > now ? date : nil
        case let .weekly(hour, minute, days):
            return ScheduleMapper.nextFireDate(hour: hour, minute: minute,
                weekdays: Set(days.map(ScheduleMapper.weekday(forCalendarWeekday:))), after: now, calendar: calendar)
        }
    }
}

struct PlannedAlarm: Codable, Hashable, Identifiable {
    /// Stable semantic key. System UUIDs are persisted separately by the scheduler.
    var id: String
    var groupID: UUID
    var childID: UUID?
    var offset: Int
    var title: String
    var schedule: PlannedSchedule
    var sound: AlarmSound
    var snoozeMinutes: Int
    var action: RingAction
    func nextFire(after now: Date, calendar: Calendar) -> Date? { schedule.nextFire(after: now, calendar: calendar) }
}

enum RingAction: String, Codable { case none, snooze, imUp }

struct ScheduledRecord: Codable, Hashable, Identifiable {
    var id: UUID
    var plan: PlannedAlarm
    var confirmed = true
}

enum AlarmPlanner {
    static func desired(for group: AlarmGroup, now: Date, calendar: Calendar) -> [PlannedAlarm] {
        guard group.isEnabled else { return [] }
        let children = group.activeChildren.sorted { $0.offsetMinutes < $1.offsetMinutes }
        let entries: [(UUID?, Int, String, AlarmSound)] = children.map { ($0.id, $0.offsetMinutes, $0.label, $0.sound) }
            + [(nil, 0, "", group.sound)]
        var result: [PlannedAlarm] = []
        for (childID, offset, label, sound) in entries {
            let key = childID?.uuidString ?? group.id.uuidString
            let title = label.isEmpty ? (offset == 0 && group.kind == .target ? "\(group.displayName) · Target" : group.displayName) : label
            let action: RingAction = group.kind == .target ? .imUp : (group.snoozeEnabled ? .snooze : .none)
            func plan(_ schedule: PlannedSchedule, suffix: String = "") -> PlannedAlarm {
                PlannedAlarm(id: key + suffix, groupID: group.id, childID: childID, offset: offset,
                             title: title, schedule: schedule, sound: sound, snoozeMinutes: group.snoozeMinutes, action: action)
            }
            if group.repeatDays.isEmpty {
                let target = group.resolvedTarget(now: now, calendar: calendar)
                if group.suppressedTarget == target { continue }
                let fire = target.addingTimeInterval(Double(offset) * 60)
                if fire > now { result.append(plan(.fixed(fire))) }
            } else {
                let mapped = ScheduleMapper.wallClockAlarms(targetHour: group.hour, targetMinute: group.minute,
                    offsets: [AlarmOffset(offset)], repeatDays: group.weekdays)[0]
                var days = Set(mapped.weekdays.compactMap { ScheduleMapper.weekdayOrder.firstIndex(of: $0).map { $0 + 1 } })
                // Suppress only the remaining times of this occurrence. Keep other weekdays repeating.
                // A fixed bridge covers the removed weekday next week until foreground/background restores it.
                if let suppressed = group.suppressedTarget {
                    let fire = suppressed.addingTimeInterval(Double(offset) * 60)
                    let end = suppressed.addingTimeInterval(Double(group.offsets.last?.minutes ?? 0) * 60 + 60)
                    if now < end, fire > now {
                        let day = calendar.component(.weekday, from: fire)
                        days.remove(day)
                        if let bridge = calendar.date(byAdding: .day, value: 7, to: fire) {
                            result.append(plan(.fixed(bridge), suffix: ":bridge"))
                        }
                    }
                }
                if !days.isEmpty { result.append(plan(.weekly(hour: mapped.hour, minute: mapped.minute, days: days))) }
            }
        }
        return result
    }

    static func occurrenceTarget(group: AlarmGroup, offset: Int, now: Date, calendar: Calendar) -> Date {
        if group.repeatDays.isEmpty { return group.resolvedTarget(now: now, calendar: calendar) }
        // The ringing child can be on the preceding/following calendar day.
        let approximate = now.addingTimeInterval(Double(-offset) * 60)
        return calendar.date(bySettingHour: group.hour, minute: group.minute, second: 0, of: approximate) ?? approximate
    }
}

struct ReconciliationDiff {
    var upserts: [PlannedAlarm]
    var removals: [ScheduledRecord]
    init(desired: [PlannedAlarm], records: [ScheduledRecord], liveIDs: Set<UUID>) {
        let wanted = Dictionary(uniqueKeysWithValues: desired.map { ($0.id, $0) })
        let existing = Dictionary(uniqueKeysWithValues: records.map { ($0.plan.id, $0) })
        upserts = desired.filter { plan in
            guard let old = existing[plan.id] else { return true }
            return !old.confirmed || old.plan != plan || !liveIDs.contains(old.id)
        }
        removals = records.filter { wanted[$0.plan.id] == nil }
    }
}
