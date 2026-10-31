import Foundation

/// On-device activity log of everything Daybreak asks AlarmKit to do, and every alarm seen ringing.
/// It exists to diagnose alarms that ring at unexpected times. Never leaves the device unless shared.
enum AlarmLog {
    static var url: URL {
        URL.applicationSupportDirectory.appending(path: "Daybreak", directoryHint: .isDirectory).appending(path: "activity.log")
    }
    private static let maxBytes = 200_000

    static func write(_ message: String, now: Date = .now) {
        let line = "\(now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeZone(separator: .omitted))) \(message)\n"
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) {
            try? Data().write(to: url, options: .completeFileProtectionUntilFirstUserAuthentication)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
        if let size = try? handle.offset(), size > maxBytes { trim() }
    }

    static func read() -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
    static func clear() { try? Data().write(to: url, options: .completeFileProtectionUntilFirstUserAuthentication) }

    private static func trim() {
        let text = read()
        let kept = text.suffix(maxBytes / 2)
        let start = kept.firstIndex(of: "\n").map { kept.index(after: $0) } ?? kept.startIndex
        try? Data(kept[start...].utf8).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func describe(_ plan: PlannedAlarm, now: Date = .now) -> String {
        let schedule: String = switch plan.schedule {
        case .fixed(let date): "once \(date.formatted(date: .abbreviated, time: .shortened))"
        case let .weekly(hour, minute, days): String(format: "weekly %02d:%02d days=", hour, minute) + days.sorted().map(String.init).joined(separator: ",")
        }
        return "\"\(plan.title)\" offset=\(plan.offset) \(schedule) key=\(plan.id.prefix(8))"
    }
}

extension UUID {
    var short: String { String(uuidString.prefix(8)) }
}
