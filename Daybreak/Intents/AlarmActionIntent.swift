import AppIntents
import Foundation

struct AlarmActionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Daybreak alarm action"
    static let description = IntentDescription("Snooze an alarm or finish today's wake-up sequence.")
    static let openAppWhenRun = false
    static let isDiscoverable = false
    @Parameter(title: "Alarm") var alarmID: String
    init() {}
    init(alarmID: UUID) { self.alarmID = alarmID.uuidString }
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }
        try await AlarmModel.shared.performAction(alarmID: id)
        return .result()
    }
}
