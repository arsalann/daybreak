import Foundation

struct AlarmDocument: Codable {
    static let currentVersion = 2
    var version = currentVersion
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
        var document = try JSONDecoder().decode(AlarmDocument.self, from: Data(contentsOf: url))
        guard (1...AlarmDocument.currentVersion).contains(document.version) else { throw CocoaError(.fileReadUnknown) }
        if document.version < 2 {
            // Version 2 replaced the bundled tones. Re-schedule so AlarmKit stops pointing at deleted sound files.
            for index in document.records.indices { document.records[index].confirmed = false }
            document.version = 2
        }
        return document
    }
    func save(_ document: AlarmDocument) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(document)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
