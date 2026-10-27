import Foundation
import os

/// File-backed store for spike runs and an append-only event log, shared by the app and the intent.
nonisolated enum SpikeStore {
    private static let lock = OSAllocatedUnfairLock()
    private static var dir: URL { URL.documentsDirectory }
    private static var recordsURL: URL { dir.appending(path: "spike-records.json") }
    private static var logURL: URL { dir.appending(path: "spike-log.txt") }

    static func log(_ message: String) {
        let stamp = ISO8601DateFormatter.string(from: .now, timeZone: .current,
                                                formatOptions: [.withInternetDateTime, .withFractionalSeconds])
        let line = "\(stamp) \(message)\n"
        lock.withLock {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: logURL)
            }
        }
    }

    static func readLog() -> String {
        lock.withLock { (try? String(contentsOf: logURL, encoding: .utf8)) ?? "" }
    }

    static func records() -> [SpikeAlarmRecord] {
        lock.withLock {
            guard let data = try? Data(contentsOf: recordsURL) else { return [] }
            return (try? JSONDecoder().decode([SpikeAlarmRecord].self, from: data)) ?? []
        }
    }

    static func save(_ records: [SpikeAlarmRecord]) {
        lock.withLock {
            if let data = try? JSONEncoder().encode(records) { try? data.write(to: recordsURL, options: .atomic) }
        }
    }

    static func update(_ body: (inout [SpikeAlarmRecord]) -> Void) {
        var all = records()
        body(&all)
        save(all)
    }

    static func clearLog() {
        lock.withLock { try? FileManager.default.removeItem(at: logURL) }
    }
}
