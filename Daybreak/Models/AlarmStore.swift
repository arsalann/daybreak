import Foundation

struct AlarmDocument: Codable {
    var version = 1
    var groups: [AlarmGroup] = []
    var records: [ScheduledRecord] = []
    var snoozes: [PlannedAlarm] = []
}

struct AlarmStore {
    var url: URL
    static var live: AlarmStore {
        let root = URL.applicationSupportDirectory.appending(path: "Daybreak", directoryHint: .isDirectory)
        return AlarmStore(url: root.appending(path: "alarms.json"))
    }
    func load() throws -> AlarmDocument {
        guard FileManager.default.fileExists(atPath: url.path) else { return AlarmDocument() }
        let document = try JSONDecoder().decode(AlarmDocument.self, from: Data(contentsOf: url))
        guard document.version == 1 else { throw CocoaError(.fileReadUnknown) }
        return document
    }
    func save(_ document: AlarmDocument) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(document)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
