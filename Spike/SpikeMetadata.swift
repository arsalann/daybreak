import AlarmKit
import Foundation

nonisolated struct SpikeMetadata: AlarmMetadata {
    var runID: String
    var offsetMinutes: Int
    var isTarget: Bool
}

/// One alarm the spike scheduled, with its expected fire time. Persisted so the
/// "I'm up" intent (which may run without UI) can find siblings.
nonisolated struct SpikeAlarmRecord: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var runID: String
    var runName: String
    var index: Int
    var total: Int
    var offsetMinutes: Int
    var isTarget: Bool
    var expected: Date?
    var weekly: Bool
    /// Filled in by the tester after the run.
    var observation: String?
}
