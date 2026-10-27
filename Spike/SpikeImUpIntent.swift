import AlarmKit
import AppIntents
import Foundation

/// M0: the "I'm up" secondary button. Stops the ringing alarm and cancels every later
/// alarm in the same run. Idempotent: missing IDs are logged and skipped.
struct SpikeImUpIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "I'm up"
    static let description = IntentDescription("Cancel the rest of this Daybreak spike run.")
    static let openAppWhenRun = false
    static let isDiscoverable = false

    @Parameter(title: "Run") var runID: String
    @Parameter(title: "Alarm") var alarmID: String
    @Parameter(title: "Offset") var offsetMinutes: Int

    init() {}

    init(runID: String, alarmID: UUID, offsetMinutes: Int) {
        self.runID = runID
        self.alarmID = alarmID.uuidString
        self.offsetMinutes = offsetMinutes
    }

    func perform() async throws -> some IntentResult {
        let manager = AlarmManager.shared
        SpikeStore.log("INTENT I'm up run=\(runID.prefix(8)) offset=\(offsetMinutes) alarm=\(alarmID.prefix(8))")
        if let id = UUID(uuidString: alarmID) {
            do { try manager.stop(id: id); SpikeStore.log("INTENT stop ok \(alarmID.prefix(8))") }
            catch { SpikeStore.log("INTENT stop failed \(alarmID.prefix(8)): \(error)") }
        }
        let live = Set(((try? manager.alarms) ?? []).map(\.id))
        let rest = SpikeStore.records().filter { $0.runID == runID && $0.offsetMinutes > offsetMinutes }
        for record in rest {
            guard live.contains(record.id) else {
                SpikeStore.log("INTENT skip (already gone) offset=\(record.offsetMinutes)")
                continue
            }
            do { try manager.cancel(id: record.id); SpikeStore.log("INTENT cancel ok offset=\(record.offsetMinutes)") }
            catch { SpikeStore.log("INTENT cancel failed offset=\(record.offsetMinutes): \(error)") }
        }
        return .result()
    }
}
