import AlarmKit
import Foundation
import SwiftUI

@MainActor
protocol AlarmClient {
    func liveIDs() throws -> Set<UUID>
    func ringingIDs() throws -> Set<UUID>
    func schedule(id: UUID, plan: PlannedAlarm) async throws
    func cancel(id: UUID) throws
    func stop(id: UUID) throws
}

struct DaybreakMetadata: AlarmMetadata {
    var groupID: UUID
    var offset: Int
}

@MainActor
final class LiveAlarmClient: AlarmClient {
    func liveIDs() throws -> Set<UUID> { Set(try AlarmManager.shared.alarms.map(\.id)) }
    func ringingIDs() throws -> Set<UUID> { Set(try AlarmManager.shared.alarms.filter { $0.state == .alerting }.map(\.id)) }
    func cancel(id: UUID) throws { try AlarmManager.shared.cancel(id: id) }
    func stop(id: UUID) throws { try AlarmManager.shared.stop(id: id) }
    func schedule(id: UUID, plan: PlannedAlarm) async throws {
        let schedule: Alarm.Schedule
        switch plan.schedule {
        case .fixed(let date): schedule = .fixed(date)
        case let .weekly(hour, minute, days):
            schedule = .relative(.init(time: .init(hour: hour, minute: minute),
                repeats: .weekly(days.sorted().map(ScheduleMapper.weekday(forCalendarWeekday:)))))
        }
        let secondary: AlarmButton? = switch plan.action {
        case .none: nil
        case .snooze: AlarmButton(text: "Snooze", textColor: .orange, systemImageName: "zzz")
        case .imUp: AlarmButton(text: "I'm up", textColor: .orange, systemImageName: "sun.max")
        }
        let title = LocalizedStringResource(stringLiteral: plan.title)
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: title, secondaryButton: secondary,
                                           secondaryButtonBehavior: secondary == nil ? nil : .custom)
        } else {
            alert = legacyAlert(title: title, secondary: secondary)
        }
        let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert),
            metadata: DaybreakMetadata(groupID: plan.groupID, offset: plan.offset), tintColor: .orange)
        let config = AlarmManager.AlarmConfiguration.alarm(schedule: schedule, attributes: attributes,
            stopIntent: nil,
            secondaryIntent: plan.action == .none ? nil : AlarmActionIntent(alarmID: id),
            sound: plan.sound.filename.map { .named($0) } ?? .default)
        _ = try await AlarmManager.shared.schedule(id: id, configuration: config)
    }
    @available(iOS, deprecated: 26.1)
    private func legacyAlert(title: LocalizedStringResource, secondary: AlarmButton?) -> AlarmPresentation.Alert {
        AlarmPresentation.Alert(title: title,
            stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle"),
            secondaryButton: secondary, secondaryButtonBehavior: secondary == nil ? nil : .custom)
    }
}
