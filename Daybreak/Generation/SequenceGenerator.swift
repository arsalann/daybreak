import Foundation

/// Which side(s) of the target a fixed-interval group extends to.
enum IntervalDirection: String, Codable, Sendable, CaseIterable {
    case before, after, both
}

/// How a group turns one target time into a set of alarms.
enum GenerationMode: Codable, Hashable, Sendable {
    case single
    /// `count` additional alarms per selected side, `minutes` apart (1-120).
    case interval(count: Int, minutes: Int, direction: IntervalDirection)
    /// Shrinking Fibonacci gaps walking back from the target; the first alarm sits at `-windowMinutes`.
    case fibonacci(windowMinutes: Int, firstGap: Int)
}

/// One generated alarm, as signed minutes relative to the target (negative = before).
struct AlarmOffset: Hashable, Sendable, Comparable {
    var minutes: Int
    var isTarget: Bool { minutes == 0 }

    init(_ minutes: Int) { self.minutes = minutes }

    static func < (lhs: AlarmOffset, rhs: AlarmOffset) -> Bool { lhs.minutes < rhs.minutes }
}

/// Pure rules from docs/planning/sequence-algorithms.md. No dates, no AlarmKit.
enum SequenceGenerator {
    static let maxAlarmsPerGroup = 20            // provisional default (open question 3)
    static let intervalMinutesRange = 1...120
    static let intervalCountRange = 1...19
    static let fibonacciWindowRange = 10...180
    static let fibonacciFirstGaps = [1, 2, 3]
    static let defaultFibonacciWindow = 60
    static let defaultFibonacciFirstGap = 2

    /// Sorted, de-duplicated offsets. The target (0) is always included.
    static func offsets(for mode: GenerationMode) -> [AlarmOffset] {
        let minutes: [Int]
        switch mode {
        case .single:
            minutes = [0]
        case let .interval(count, step, direction):
            let n = max(0, count), x = max(1, step)
            let before = direction == .after ? [] : (0..<n).map { -x * ($0 + 1) }
            let after = direction == .before ? [] : (0..<n).map { x * ($0 + 1) }
            minutes = before + [0] + after
        case let .fibonacci(window, firstGap):
            minutes = fibonacciBackwardDistances(window: window, firstGap: firstGap).map { -$0 }
        }
        return Set(minutes).sorted().map(AlarmOffset.init)
    }

    /// Fibonacci numbers >= `firstGap`, without the duplicate 1.
    static func fibonacciGaps(firstGap: Int, limit: Int = 40) -> [Int] {
        var (a, b) = (1, 2)
        var out: [Int] = []
        while out.count < limit {
            if a >= firstGap, out.last != a { out.append(a) }
            (a, b) = (b, a + b)
        }
        return out
    }

    /// Positive distances before the target, port of the reference Python script.
    static func fibonacciBackwardDistances(window: Int, firstGap: Int) -> [Int] {
        guard window > 0 else { return [0] }
        var offsets: [Int] = []
        var c = 0
        var lastGap = 0
        for g in fibonacciGaps(firstGap: firstGap) {
            if c + g >= window { break }
            c += g
            offsets.append(c)
            lastGap = g
        }
        // Merge a tiny leftover gap at the window start into the one before it.
        if let last = offsets.last, (window - last) * 2 < lastGap {
            offsets.removeLast()
        }
        return Array(Set([0] + offsets + [window])).sorted()
    }
}

/// Editor warnings and save-blocking problems for a generated group.
enum SequenceIssue: Hashable, Sendable {
    /// Blocks saving.
    case tooManyAlarms(count: Int, max: Int)
    /// Warning only: a gap between neighbours is below the configured threshold.
    case gapBelowThreshold(fromMinutes: Int, toMinutes: Int, gap: Int, threshold: Int)

    var blocksSaving: Bool {
        if case .tooManyAlarms = self { return true }
        return false
    }
}

enum SequenceValidator {
    static let defaultGapWarningThreshold = 2   // provisional default (open question 4)
    static let gapWarningThresholdRange = 1...10

    static func issues(for offsets: [AlarmOffset],
                       gapWarningThreshold: Int = defaultGapWarningThreshold,
                       maxAlarms: Int = SequenceGenerator.maxAlarmsPerGroup) -> [SequenceIssue] {
        var result: [SequenceIssue] = []
        if offsets.count > maxAlarms {
            result.append(.tooManyAlarms(count: offsets.count, max: maxAlarms))
        }
        let sorted = offsets.map(\.minutes).sorted()
        for (a, b) in zip(sorted, sorted.dropFirst()) where b - a < gapWarningThreshold {
            result.append(.gapBelowThreshold(fromMinutes: a, toMinutes: b, gap: b - a, threshold: gapWarningThreshold))
        }
        return result
    }
}
