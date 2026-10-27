import Foundation
import Testing
@testable import Daybreak

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()
private func instant(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

struct AlarmPlannerTests {
    @Test func presetsStartAtWindowAndKeepChildSettings() {
        var group = AlarmGroup(kind: .target)
        group.preset = .tenMinutes
        group.windowMinutes = 15
        group.applyPreset()
        #expect(group.offsets.map(\.minutes) == [-15, -10, 0])
        group.children[0].label = "Coffee"
        let id = group.children[0].id
        group.applyPreset()
        #expect(group.children[0].id == id)
        #expect(group.children[0].label == "Coffee")
    }
    @Test func fibonacciAndManualValidation() {
        var group = AlarmGroup(kind: .target)
        group.applyPreset()
        #expect(group.offsets.map(\.minutes) == [-60, -31, -18, -10, -5, -2, 0])
        group.children[0].isEnabled = false
        #expect(!group.offsets.contains(AlarmOffset(-60)))
        group.children.append(ChildAlarm(offsetMinutes: -2))
        #expect(group.validationError != nil)
        group.children = [ChildAlarm(offsetMinutes: 0)]
        #expect(group.validationError != nil)
        group.children = (1...20).map { ChildAlarm(offsetMinutes: -$0) }
        #expect(group.validationError != nil)
    }
    @Test func oneOffSkipsEarlierChildrenWithoutMovingThemToTomorrow() {
        let now = instant("2026-10-26T08:45:00Z")
        var group = AlarmGroup(kind: .target, hour: 9)
        group.applyPreset()
        group.oneOffTarget = instant("2026-10-26T09:00:00Z")
        let planned = AlarmPlanner.desired(for: group, now: now, calendar: utc)
        #expect(planned.map(\.offset).sorted() == [-10, -5, -2, 0])
        #expect(planned.compactMap { $0.nextFire(after: now, calendar: utc) }.max() == group.oneOffTarget)
    }
    @Test func midnightShiftsRepeatDaysAndChildDate() {
        let now = instant("2026-10-25T22:00:00Z")
        var group = AlarmGroup(kind: .target, hour: 0, minute: 20, repeatDays: [2])
        group.children = [ChildAlarm(offsetMinutes: -60)]
        let plans = AlarmPlanner.desired(for: group, now: now, calendar: utc)
        let child = plans.first { $0.offset == -60 }!
        #expect(child.schedule == .weekly(hour: 23, minute: 20, days: [1]))
        #expect(child.nextFire(after: now, calendar: utc) == instant("2026-10-25T23:20:00Z"))
        #expect(AlarmPlanner.occurrenceTarget(group: group, offset: -60, now: instant("2026-10-25T23:20:10Z"), calendar: utc) == instant("2026-10-26T00:20:00Z"))
    }
    @Test func suppressionPreservesOtherDaysAndBridgesNextWeek() {
        let now = instant("2026-10-26T08:40:00Z")
        var group = AlarmGroup(kind: .target, hour: 9, repeatDays: [2, 3])
        group.children = [ChildAlarm(offsetMinutes: -10)]
        group.suppressedTarget = instant("2026-10-26T09:00:00Z")
        let plans = AlarmPlanner.desired(for: group, now: now, calendar: utc)
        #expect(plans.count == 4)
        #expect(plans.filter { $0.id.hasSuffix(":bridge") }.count == 2)
        #expect(plans.contains { $0.schedule == .weekly(hour: 9, minute: 0, days: [3]) })
        #expect(plans.contains { $0.schedule == .fixed(instant("2026-11-02T09:00:00Z")) })
        let restored = AlarmPlanner.desired(for: group, now: instant("2026-10-26T09:02:00Z"), calendar: utc)
        #expect(restored.count == 2)
        #expect(restored.contains { $0.schedule == .weekly(hour: 9, minute: 0, days: [2, 3]) })
    }
    @Test func diffOnlyTouchesChangedOrMissingAlarms() {
        var group = AlarmGroup(kind: .target, repeatDays: [2])
        group.applyPreset()
        let now = instant("2026-10-25T08:00:00Z")
        let original = AlarmPlanner.desired(for: group, now: now, calendar: utc)
        let records = original.map { ScheduledRecord(id: UUID(), plan: $0) }
        let live = Set(records.map(\.id))
        #expect(ReconciliationDiff(desired: original, records: records, liveIDs: live).upserts.isEmpty)
        group.children[0].label = "Updated"
        group.children.removeLast()
        let changed = AlarmPlanner.desired(for: group, now: now, calendar: utc)
        let diff = ReconciliationDiff(desired: changed, records: records, liveIDs: live)
        #expect(diff.upserts.count == 1)
        #expect(diff.removals.count == 1)
        let missing = ReconciliationDiff(desired: original, records: records, liveIDs: live.subtracting([records[0].id]))
        #expect(missing.upserts.count == 1)
    }
    @Test func roundTripPreservesIdentitiesAndCustomization() throws {
        var group = AlarmGroup(kind: .target, repeatDays: [2, 3, 4])
        group.applyPreset()
        group.children[0].sound = .chime
        group.children[1].isEnabled = false
        group.clockStyle = .dial
        let document = AlarmDocument(groups: [group])
        let decoded = try JSONDecoder().decode(AlarmDocument.self, from: JSONEncoder().encode(document))
        #expect(decoded.groups == [group])
    }
}

@MainActor
final class FakeAlarmClient: AlarmClient {
    var plans: [UUID: PlannedAlarm] = [:]
    var ringing: Set<UUID> = []
    var scheduled: [UUID] = []
    var cancelled: [UUID] = []
    var failSchedule = false
    var failCancel = false
    func liveIDs() throws -> Set<UUID> { Set(plans.keys) }
    func ringingIDs() throws -> Set<UUID> { ringing }
    func schedule(id: UUID, plan: PlannedAlarm) async throws {
        if failSchedule { throw CocoaError(.featureUnsupported) }
        plans[id] = plan
        scheduled.append(id)
    }
    func cancel(id: UUID) throws {
        if failCancel { throw CocoaError(.featureUnsupported) }
        plans.removeValue(forKey: id)
        cancelled.append(id)
    }
    func stop(id: UUID) throws { plans.removeValue(forKey: id); ringing.remove(id) }
}

@MainActor
struct AlarmModelTests {
    private func setup() -> (AlarmModel, FakeAlarmClient, AlarmStore) {
        let client = FakeAlarmClient()
        let store = AlarmStore(url: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "alarms.json"))
        let model = AlarmModel(store: store, client: client)
        model.authorization = .authorized
        return (model, client, store)
    }
    @Test func scheduleEditAndDeleteUseStableIDs() async throws {
        let (model, client, store) = setup()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        var group = AlarmGroup(kind: .target, repeatDays: [2])
        group.applyPreset()
        #expect(await model.save(group))
        let originalIDs = Set(client.plans.keys)
        #expect(originalIDs.count == 7)
        client.scheduled = []
        #expect(await model.reconcile())
        #expect(client.scheduled.isEmpty)
        group.children[0].label = "Just this child"
        #expect(await model.save(group))
        #expect(client.scheduled.count == 1)
        #expect(Set(client.plans.keys) == originalIDs)
        // The edited alarm is replaced in place: cancelled, then re-scheduled under the same ID.
        #expect(client.cancelled == client.scheduled)
        #expect(await model.delete(group))
        #expect(client.plans.isEmpty)
        #expect(try store.load().groups.isEmpty)
    }
    @Test func schedulingFailureIsVisibleAndRetryUsesReservedID() async throws {
        let (model, client, store) = setup()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        client.failSchedule = true
        #expect(await model.save(AlarmGroup()) == false)
        #expect(model.errorMessage != nil)
        let reservedID = try #require(model.document.records.first?.id)
        #expect(try store.load().records.first?.confirmed == false)
        client.failSchedule = false
        #expect(await model.reconcile())
        #expect(client.scheduled == [reservedID])
        #expect(model.errorMessage == nil)
    }
    @Test func orphanedSystemAlarmsAreCancelled() async throws {
        let (model, client, store) = setup()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let orphan = UUID()
        client.plans[orphan] = PlannedAlarm(id: "orphan", groupID: UUID(), offset: 0, title: "Lost", schedule: .fixed(.now.addingTimeInterval(3600)), sound: .system, snoozeMinutes: 9, action: .none)
        #expect(await model.save(AlarmGroup()))
        #expect(client.cancelled == [orphan])
        #expect(client.plans[orphan] == nil)
    }
    @Test func randomSoundResolvesToConcreteSound() {
        for _ in 0..<20 { #expect(AlarmSound.random.resolved() != .random) }
        #expect(AlarmSound.chime.resolved() == .chime)
    }
    @Test func repeatingRandomAlarmIsRescheduledAfterItRings() async throws {
        let (model, client, store) = setup()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        var group = AlarmGroup(repeatDays: [1, 2, 3, 4, 5, 6, 7])
        group.sound = .random
        let start = Date.now
        #expect(await model.save(group))
        let id = try #require(model.document.records.first?.id)
        client.scheduled = []
        #expect(await model.reconcile(now: start))
        #expect(client.scheduled.isEmpty)
        #expect(await model.reconcile(now: start.addingTimeInterval(2 * 86400)))
        #expect(client.scheduled == [id])
        client.scheduled = []
        #expect(await model.reconcile(now: start.addingTimeInterval(2 * 86400)))
        #expect(client.scheduled.isEmpty)
    }
    @Test func cancelFailureKeepsGroupVisible() async throws {
        let (model, client, store) = setup()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let group = AlarmGroup()
        #expect(await model.save(group))
        client.failCancel = true
        #expect(await model.delete(group) == false)
        #expect(model.groups.contains { $0.id == group.id })
    }
    @Test func expiredOneOffIsDisabledButRingingOneIsPreserved() async throws {
        let (model, client, store) = setup()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let now = Date.now
        var group = AlarmGroup()
        group.oneOffTarget = now.addingTimeInterval(-600)
        let plan = PlannedAlarm(id: group.id.uuidString, groupID: group.id, offset: 0, title: "Alarm", schedule: .fixed(group.oneOffTarget!), sound: .system, snoozeMinutes: 9, action: .snooze)
        let id = UUID()
        model.document = AlarmDocument(groups: [group], records: [ScheduledRecord(id: id, plan: plan)])
        client.plans[id] = plan
        client.ringing = [id]
        #expect(await model.reconcile(now: now))
        #expect(model.groups[0].isEnabled)
        #expect(client.cancelled.isEmpty)
        client.ringing = []
        #expect(await model.reconcile(now: now))
        #expect(!model.groups[0].isEnabled)
        #expect(client.cancelled == [id])
    }
    @Test func snoozeSchedulesOneFixedAlarmBeforeStoppingOriginal() async throws {
        let (model, client, store) = setup()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        #expect(await model.save(AlarmGroup()))
        let id = try #require(model.document.records.first?.id)
        client.ringing = [id]
        try await model.performAction(alarmID: id)
        #expect(model.document.snoozes.count == 1)
        let snooze = try #require(model.document.snoozes.first)
        #expect(snooze.nextFire(after: .now, calendar: .current)!.timeIntervalSinceNow > 530)
        #expect(client.plans.count == 1)
        // A duplicate invocation cannot create a second snooze.
        try await model.performAction(alarmID: id)
        #expect(model.document.snoozes.count == 1)
    }
    @Test func imUpCancelsOnlyThisOneOffGroupAndIsIdempotent() async throws {
        let (model, client, store) = setup()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        var target = AlarmGroup(kind: .target)
        target.children = [ChildAlarm(offsetMinutes: -10), ChildAlarm(offsetMinutes: -5)]
        #expect(await model.save(target))
        #expect(await model.save(AlarmGroup(label: "Unrelated")))
        let record = try #require(model.document.records.first { $0.plan.groupID == target.id && $0.plan.offset == -10 })
        client.ringing = [record.id]
        try await model.performAction(alarmID: record.id)
        #expect(model.groups.first { $0.id == target.id }?.isEnabled == false)
        #expect(client.plans.values.allSatisfy { $0.groupID != target.id })
        #expect(client.plans.count == 1)
        let count = client.cancelled.count
        try await model.performAction(alarmID: record.id)
        #expect(client.cancelled.count == count)
    }
    @Test func imUpOnRepeatingGroupKeepsOtherWeekdays() async throws {
        let (model, client, store) = setup()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let targetDate = Date.now.addingTimeInterval(1800)
        let cal = Calendar.current
        let day = cal.component(.weekday, from: targetDate)
        var group = AlarmGroup(kind: .target,
            hour: cal.component(.hour, from: targetDate), minute: cal.component(.minute, from: targetDate), repeatDays: Set(1...7))
        group.children = [ChildAlarm(offsetMinutes: -30)]
        #expect(await model.save(group))
        let record = try #require(model.document.records.first { $0.plan.offset == -30 })
        client.ringing = [record.id]
        try await model.performAction(alarmID: record.id)
        #expect(model.groups[0].isEnabled)
        #expect(model.groups[0].suppressedTarget != nil)
        let targetPlan = try #require(client.plans.values.first { $0.offset == 0 && !$0.id.hasSuffix(":bridge") })
        if case .weekly(_, _, let days) = targetPlan.schedule {
            #expect(days == Set(1...7).subtracting([day]))
        } else { Issue.record("The repeating target must remain weekly") }
        #expect(client.plans.values.contains { $0.offset == 0 && $0.id.hasSuffix(":bridge") })
        let count = client.scheduled.count
        try await model.performAction(alarmID: record.id)
        #expect(client.scheduled.count == count)
    }
    @Test func corruptStoreIsNotOverwritten() async throws {
        let (model, _, store) = setup()
        _ = model
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        try Data("broken json".utf8).write(to: store.url)
        let broken = AlarmModel(store: store, client: FakeAlarmClient())
        #expect(broken.storageFailed)
        #expect(await broken.save(AlarmGroup()) == false)
        #expect(try String(contentsOf: store.url, encoding: .utf8) == "broken json")
    }
}
