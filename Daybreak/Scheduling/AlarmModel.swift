import AlarmKit
import BackgroundTasks
import Foundation
import Observation

@MainActor @Observable
final class AlarmModel {
    static let shared = AlarmModel()
    var document = AlarmDocument()
    var authorization = AlarmManager.shared.authorizationState
    var errorMessage: String?
    var isBusy = false
    var storageFailed = false
    var groups: [AlarmGroup] { document.groups }
    private let store: AlarmStore
    private let client: any AlarmClient
    private var loaded = false

    init(store: AlarmStore = .live, client: any AlarmClient = LiveAlarmClient()) {
        self.store = store
        self.client = client
        do { document = try store.load(); loaded = true }
        catch { storageFailed = true; errorMessage = "Your alarms could not be read. Your saved file has been kept intact. \(error.localizedDescription)" }
    }

    func persist() throws {
        guard loaded else { throw CocoaError(.fileReadCorruptFile) }
        try store.save(document)
    }

    func authorize() async {
        do {
            authorization = try await AlarmManager.shared.requestAuthorization()
            if authorization == .authorized { await refresh() }
        } catch { errorMessage = "Alarm permission could not be requested: \(error.localizedDescription)" }
    }

    func save(_ draft: AlarmGroup) async -> Bool {
        guard !isBusy, !storageFailed else { return false }
        guard draft.validationError == nil else { errorMessage = draft.validationError; return false }
        if draft.isEnabled && authorization != .authorized {
            await authorize()
            guard authorization == .authorized else {
                errorMessage = "Allow alarms in Settings before enabling this alarm. You can turn it off and save it for later."
                return false
            }
        }
        var group = draft
        let old = document.groups.first { $0.id == group.id }
        if group.repeatDays.isEmpty && (old == nil || old?.hour != group.hour || old?.minute != group.minute || old?.isEnabled == false || old?.repeatDays.isEmpty == false) {
            group.oneOffTarget = ScheduleMapper.resolveOneOffTarget(hour: group.hour, minute: group.minute, now: .now, calendar: .current)
        }
        if old?.hour != group.hour || old?.minute != group.minute || old?.repeatDays != group.repeatDays || old?.isEnabled != group.isEnabled {
            group.suppressedTarget = nil
        }
        let previous = document
        if let index = document.groups.firstIndex(where: { $0.id == group.id }) { document.groups[index] = group }
        else { document.groups.append(group) }
        document.snoozes.removeAll { $0.groupID == group.id }
        do { try persist() } catch {
            document = previous
            errorMessage = "Could not save the alarm: \(error.localizedDescription)"
            return false
        }
        if !group.isEnabled && authorization != .authorized {
            if !document.groups.contains(where: \.isEnabled) { errorMessage = nil }
            return true
        }
        return await reconcile()
    }

    func toggle(_ group: AlarmGroup) async {
        var changed = group
        changed.isEnabled.toggle()
        _ = await save(changed)
    }

    func delete(_ group: AlarmGroup) async -> Bool {
        guard !isBusy, !storageFailed else { return false }
        isBusy = true
        defer { isBusy = false }
        let previous = document
        do {
            // Keep the group visible if cancelling fails; never leave invisible ringing alarms.
            let records = document.records.filter { $0.plan.groupID == group.id }
            let ids = records.isEmpty ? Set<UUID>() : try client.liveIDs()
            for record in records {
                if ids.contains(record.id) { try client.cancel(id: record.id) }
            }
            document.groups.removeAll { $0.id == group.id }
            document.records.removeAll { $0.plan.groupID == group.id }
            document.snoozes.removeAll { $0.groupID == group.id }
            try persist()
            return true
        } catch {
            document = previous
            errorMessage = "Could not finish deleting this alarm. Please retry. \(error.localizedDescription)"
            return false
        }
    }

    func refresh() async {
        authorization = AlarmManager.shared.authorizationState
        guard !isBusy, !storageFailed else { return }
        _ = await reconcile()
    }

    func observe() async {
        for await _ in AlarmManager.shared.alarmUpdates {
            guard !Task.isCancelled else { return }
            // Reconcile missing future alarms, preserving currently ringing one-offs.
            await refresh()
        }
    }

    @discardableResult
    func reconcile(now: Date = .now) async -> Bool {
        guard !isBusy, !storageFailed else { return false }
        guard authorization == .authorized else { return !document.groups.contains(where: \.isEnabled) }
        isBusy = true
        defer { isBusy = false }
        do {
            let liveIDs = try client.liveIDs()
            let ringingIDs = try client.ringingIDs()
            for index in document.groups.indices {
                let group = document.groups[index]
                if let suppressed = group.suppressedTarget,
                   suppressed.addingTimeInterval(Double(group.offsets.last?.minutes ?? 0) * 60 + 60) < now {
                    document.groups[index].suppressedTarget = nil
                }
                if group.repeatDays.isEmpty, let target = group.oneOffTarget,
                   target.addingTimeInterval(Double(group.offsets.last?.minutes ?? 0) * 60 + 60) < now {
                    // Leave an active alert intact, then disable the finished one-off.
                    let active = document.records.contains { $0.plan.groupID == group.id && ringingIDs.contains($0.id) }
                        || document.snoozes.contains { $0.groupID == group.id && $0.nextFire(after: now, calendar: .current) != nil }
                    if !active { document.groups[index].isEnabled = false }
                }
            }
            document.snoozes.removeAll { plan in
                plan.nextFire(after: now, calendar: .current) == nil && !document.records.contains { $0.plan.id == plan.id && ringingIDs.contains($0.id) }
            }
            var desired = document.groups.flatMap { AlarmPlanner.desired(for: $0, now: now, calendar: .current) }
            desired += document.snoozes
            // A fixed alarm disappears from the future plan as it starts ringing. Don't cancel it.
            for record in document.records where liveIDs.contains(record.id) {
                if case .fixed(let fire) = record.plan.schedule, fire <= now,
                   (ringingIDs.contains(record.id) || now.timeIntervalSince(fire) < 60),
                   let group = document.groups.first(where: { $0.id == record.plan.groupID }), group.isEnabled,
                   group.suppressedTarget == nil, !desired.contains(where: { $0.id == record.plan.id }) {
                    desired.append(record.plan)
                }
            }
            let diff = ReconciliationDiff(desired: desired, records: document.records, liveIDs: liveIDs)
            let known = Set(document.records.map(\.id))
            // Free system slots first: AlarmKit caps alarms per app (error code 0, maximumLimitReached).
            for record in diff.removals {
                if liveIDs.contains(record.id) { try client.cancel(id: record.id) }
                document.records.removeAll { $0.id == record.id }
                try persist()
            }
            // Alarms the system holds that no record knows about (e.g. from an earlier failed sync) are orphans.
            for id in liveIDs.subtracting(known).subtracting(ringingIDs) { try client.cancel(id: id) }
            for plan in diff.upserts {
                let index = document.records.firstIndex { $0.plan.id == plan.id }
                let id = index.map { document.records[$0].id } ?? UUID()
                let record = ScheduledRecord(id: id, plan: plan, confirmed: false)
                if let index { document.records[index] = record } else { document.records.append(record) }
                try persist() // Write-ahead ID: a crash cannot orphan an alarm in the system.
                // Replace rather than re-schedule an ID the system already holds.
                if liveIDs.contains(id) && !ringingIDs.contains(id) { try client.cancel(id: id) }
                try await client.schedule(id: id, plan: plan)
                if let index = document.records.firstIndex(where: { $0.id == id }) { document.records[index].confirmed = true }
                try persist()
            }
            try persist()
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Your changes are saved, but some alarms could not be synced. Tap Retry before relying on them. \(Self.describe(error))"
            return false
        }
    }

    func performAction(alarmID: UUID) async throws {
        // All UI and intents share this MainActor instance, including cold intent launches.
        guard !isBusy else { throw AlarmActionError.busy }
        guard let record = document.records.first(where: { $0.id == alarmID }),
              let index = document.groups.firstIndex(where: { $0.id == record.plan.groupID }) else { return }
        let now = Date.now
        switch record.plan.action {
        case .none: return
        case .snooze:
            // Same deterministic key makes duplicate intent invocations idempotent.
            let key = record.plan.id + ":snooze"
            if !document.snoozes.contains(where: { $0.id == key }) {
                var snooze = record.plan
                snooze.id = key
                snooze.schedule = .fixed(now.addingTimeInterval(Double(snooze.snoozeMinutes) * 60))
                document.snoozes.append(snooze)
                try persist()
            }
            guard await reconcile() else { throw AlarmActionError.sync }
            if try client.ringingIDs().contains(alarmID) { try client.stop(id: alarmID) }
        case .imUp:
            let group = document.groups[index]
            let target = AlarmPlanner.occurrenceTarget(group: group, offset: record.plan.offset, now: now, calendar: .current)
            document.groups[index].suppressedTarget = target
            if group.repeatDays.isEmpty { document.groups[index].isEnabled = false }
            try persist()
            if try client.ringingIDs().contains(alarmID) { try client.stop(id: alarmID) }
            guard await reconcile() else { throw AlarmActionError.sync }
            Self.requestBackgroundRefresh(after: target.addingTimeInterval(Double(group.offsets.last?.minutes ?? 0) * 60 + 120))
        }
    }

    static func describe(_ error: Error) -> String {
        if let alarmError = error as? AlarmManager.AlarmError, case .maximumLimitReached = alarmError {
            return "iOS limits how many alarms one app can schedule. Turn off or shorten some alarm sequences."
        }
        let ns = error as NSError
        return "\(ns.localizedDescription) (\(ns.domain) \(ns.code))"
    }

    static var backgroundID: String { (Bundle.main.bundleIdentifier ?? "org.example.daybreak") + ".refresh" }
    static func requestBackgroundRefresh(after date: Date = .now.addingTimeInterval(3600)) {
        let request = BGAppRefreshTaskRequest(identifier: backgroundID)
        request.earliestBeginDate = date
        try? BGTaskScheduler.shared.submit(request)
    }
}

enum AlarmActionError: LocalizedError {
    case busy, sync
    var errorDescription: String? {
        self == .busy ? "Daybreak is saving changes. Please try again." : "Some alarms could not be updated. Open Daybreak to retry."
    }
}
