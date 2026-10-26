import AlarmKit
import Foundation
import SwiftUI
import UIKit

enum SpikeRun: String, CaseIterable, Identifiable {
    case fibonacciDefault = "A · Fibonacci default (60 min, gap 2)"
    case interval3 = "B1 · 7 alarms, 3 min apart"
    case interval5 = "B2 · 7 alarms, 5 min apart"
    case interval2 = "C · 4 alarms, 2 min apart (I'm up test)"
    case weeklyRepeat = "F · Weekly repeat, 2 alarms 2 min apart"
    case capacity = "E · Capacity: 35 alarms tomorrow"

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .fibonacciDefault: "Fib"
        case .interval3: "3min"
        case .interval5: "5min"
        case .interval2: "2min"
        case .weeklyRepeat: "Weekly"
        case .capacity: "Cap"
        }
    }

    /// Offsets relative to the target (last alarm in each run).
    var offsets: [AlarmOffset] {
        switch self {
        case .fibonacciDefault: SequenceGenerator.offsets(for: .fibonacci(windowMinutes: 60, firstGap: 2))
        case .interval3: SequenceGenerator.offsets(for: .interval(count: 6, minutes: 3, direction: .before))
        case .interval5: SequenceGenerator.offsets(for: .interval(count: 6, minutes: 5, direction: .before))
        case .interval2: SequenceGenerator.offsets(for: .interval(count: 3, minutes: 2, direction: .before))
        case .weeklyRepeat: SequenceGenerator.offsets(for: .interval(count: 1, minutes: 2, direction: .before))
        case .capacity: (0..<35).map { AlarmOffset($0 - 34) }
        }
    }
}

@MainActor @Observable
final class SpikeModel {
    var authorization: AlarmManager.AuthorizationState = AlarmManager.shared.authorizationState
    var alarms: [Alarm] = []
    var records: [SpikeAlarmRecord] = SpikeStore.records()
    var log: String = SpikeStore.readLog()
    var leadMinutes = 3
    var status = ""

    private var lastStates: [UUID: Alarm.State] = [:]

    func observe() async {
        SpikeStore.log("APP launch/observe \(Self.deviceSummary)")
        refreshLocal()
        for await snapshot in AlarmManager.shared.alarmUpdates {
            alarms = snapshot.sorted { ($0.id.uuidString) < ($1.id.uuidString) }
            let now = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.id, $0.state) })
            for (id, state) in now where lastStates[id] != state {
                SpikeStore.log("UPDATE \(label(for: id)) -> \(state)")
            }
            for id in lastStates.keys where now[id] == nil {
                SpikeStore.log("UPDATE \(label(for: id)) -> removed")
            }
            lastStates = now
            refreshLocal()
        }
    }

    func requestAuthorization() async {
        do { authorization = try await AlarmManager.shared.requestAuthorization() }
        catch { status = "Authorization error: \(error)" }
        SpikeStore.log("AUTH \(authorization)")
        refreshLocal()
    }

    func schedule(_ run: SpikeRun) async {
        let runID = UUID().uuidString
        let cal = Calendar.current
        let start = cal.date(bySetting: .second, value: 0, of: Date.now.addingTimeInterval(60)) ?? .now
        let firstAlarm = cal.date(byAdding: .minute, value: max(0, leadMinutes - 1), to: start)!
        let offsets = run.offsets
        let first = offsets.first?.minutes ?? 0
        let target = run == .capacity
            ? cal.date(byAdding: .day, value: 1, to: firstAlarm)!.addingTimeInterval(Double(-first) * 60)
            : firstAlarm.addingTimeInterval(Double(-first) * 60)
        var newRecords: [SpikeAlarmRecord] = []
        var failures = 0
        for (i, offset) in offsets.enumerated() {
            let fire = target.addingTimeInterval(Double(offset.minutes) * 60)
            let id = UUID()
            let schedule: Alarm.Schedule
            if run == .weeklyRepeat {
                let c = cal.dateComponents([.hour, .minute, .weekday], from: fire)
                let day = ScheduleMapper.weekday(forCalendarWeekday: c.weekday!)
                schedule = .relative(.init(time: .init(hour: c.hour!, minute: c.minute!), repeats: .weekly([day])))
            } else {
                schedule = .fixed(fire)
            }
            let title: LocalizedStringResource = offset.isTarget
                ? "\(fire.formatted(date: .omitted, time: .shortened)) · Target"
                : "\(run.shortName) · \(i + 1) of \(offsets.count)"
            let alert = Self.alert(title: title)
            let attributes = AlarmAttributes(
                presentation: AlarmPresentation(alert: alert),
                metadata: SpikeMetadata(runID: runID, offsetMinutes: offset.minutes, isTarget: offset.isTarget),
                tintColor: offset.isTarget ? .orange : .accentColor)
            let config = AlarmManager.AlarmConfiguration.alarm(
                schedule: schedule, attributes: attributes, stopIntent: nil,
                secondaryIntent: SpikeImUpIntent(runID: runID, alarmID: id, offsetMinutes: offset.minutes))
            do {
                _ = try await AlarmManager.shared.schedule(id: id, configuration: config)
                newRecords.append(SpikeAlarmRecord(id: id, runID: runID, runName: run.shortName, index: i + 1,
                                                   total: offsets.count, offsetMinutes: offset.minutes,
                                                   isTarget: offset.isTarget, expected: fire,
                                                   weekly: run == .weeklyRepeat))
                SpikeStore.log("SCHEDULE \(run.shortName) \(i + 1)/\(offsets.count) offset=\(offset.minutes) expected=\(fire.formatted(.iso8601)) id=\(id.uuidString.prefix(8))")
            } catch {
                failures += 1
                SpikeStore.log("SCHEDULE FAILED \(run.shortName) \(i + 1)/\(offsets.count): \(error)")
            }
        }
        SpikeStore.update { $0.append(contentsOf: newRecords) }
        let total = (try? AlarmManager.shared.alarms.count) ?? -1
        status = "\(run.shortName): scheduled \(newRecords.count), failed \(failures). AlarmKit now reports \(total) alarms."
        SpikeStore.log("RESULT \(status)")
        refreshLocal()
    }

    func cancelAll() {
        for alarm in (try? AlarmManager.shared.alarms) ?? [] {
            do { try AlarmManager.shared.cancel(id: alarm.id) }
            catch { SpikeStore.log("CANCEL failed \(alarm.id.uuidString.prefix(8)): \(error)") }
        }
        SpikeStore.log("CANCEL ALL requested")
        refreshLocal()
    }

    func setObservation(_ value: String, for record: SpikeAlarmRecord) {
        SpikeStore.update { all in
            if let i = all.firstIndex(where: { $0.id == record.id }) { all[i].observation = value }
        }
        SpikeStore.log("OBSERVED \(record.runName) \(record.index)/\(record.total) offset=\(record.offsetMinutes): \(value)")
        refreshLocal()
    }

    func clearHistory() {
        SpikeStore.save([])
        SpikeStore.clearLog()
        refreshLocal()
    }

    func refreshLocal() {
        records = SpikeStore.records()
        log = SpikeStore.readLog()
        authorization = AlarmManager.shared.authorizationState
    }

    func label(for id: UUID) -> String {
        guard let r = records.first(where: { $0.id == id }) else { return id.uuidString.prefix(8) + " (unknown)" }
        return "\(r.runName) \(r.index)/\(r.total) offset=\(r.offsetMinutes)"
    }

    var report: String {
        let f = Date.FormatStyle().hour().minute().second()
        let rows = records.map { r in
            "\(r.runName)\t\(r.index)/\(r.total)\t\(r.offsetMinutes)\t\(r.isTarget ? "target" : "")\t\(r.expected?.formatted(f) ?? "-")\t\(r.observation ?? "")"
        }.joined(separator: "\n")
        return """
        Daybreak M0 spike report
        \(Self.deviceSummary)
        Authorization: \(authorization)

        run\tindex\toffset\ttarget\texpected\tobserved
        \(rows)

        --- event log ---
        \(log)
        """
    }

    /// iOS 26.1 dropped the custom stop button; 26.0 still requires one.
    static func alert(title: LocalizedStringResource) -> AlarmPresentation.Alert {
        let imUp = AlarmButton(text: "I'm up", textColor: .orange, systemImageName: "sun.max")
        if #available(iOS 26.1, *) {
            return AlarmPresentation.Alert(title: title, secondaryButton: imUp, secondaryButtonBehavior: .custom)
        }
        return legacyAlert(title: title, secondary: imUp)
    }

    @available(iOS, deprecated: 26.1)
    private static func legacyAlert(title: LocalizedStringResource, secondary: AlarmButton) -> AlarmPresentation.Alert {
        AlarmPresentation.Alert(title: title,
                                stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle"),
                                secondaryButton: secondary, secondaryButtonBehavior: .custom)
    }

    static var deviceSummary: String {
        var info = utsname()
        uname(&info)
        let model = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return "device=\(model) iOS=\(UIDevice.current.systemVersion) tz=\(TimeZone.current.identifier)"
    }
}
