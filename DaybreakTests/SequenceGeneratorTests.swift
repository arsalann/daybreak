import Testing
@testable import Daybreak

/// "HH:MM" strings for offsets around a 09:00 target.
private func clock(_ offsets: [AlarmOffset], targetHour: Int = 9, targetMinute: Int = 0) -> String {
    offsets.map { o in
        let t = ((targetHour * 60 + targetMinute + o.minutes) % 1440 + 1440) % 1440
        return String(format: "%02d:%02d", t / 60, t % 60)
    }.joined(separator: " ")
}

struct FixedIntervalTests {
    @Test(arguments: [
        (5, 5, IntervalDirection.after, "09:00 09:05 09:10 09:15 09:20 09:25"),
        (5, 5, .before, "08:35 08:40 08:45 08:50 08:55 09:00"),
        (2, 10, .both, "08:40 08:50 09:00 09:10 09:20"),
        (3, 15, .before, "08:15 08:30 08:45 09:00"),
    ])
    func vectors(count: Int, minutes: Int, direction: IntervalDirection, expected: String) {
        #expect(clock(SequenceGenerator.offsets(for: .interval(count: count, minutes: minutes, direction: direction))) == expected)
    }

    @Test func signedOffsets() {
        let offsets = SequenceGenerator.offsets(for: .interval(count: 2, minutes: 10, direction: .both))
        #expect(offsets.map(\.minutes) == [-20, -10, 0, 10, 20])
        #expect(offsets.filter(\.isTarget).map(\.minutes) == [0])
    }

    @Test func countIsPerSideAndExcludesTarget() {
        #expect(SequenceGenerator.offsets(for: .interval(count: 19, minutes: 1, direction: .after)).count == 20)
        #expect(SequenceGenerator.offsets(for: .interval(count: 3, minutes: 5, direction: .both)).count == 7)
    }

    @Test func singleIsJustTheTarget() {
        #expect(SequenceGenerator.offsets(for: .single) == [AlarmOffset(0)])
    }
}

struct FibonacciTests {
    @Test(arguments: [
        (2, 10, "08:50 08:55 08:58 09:00"),
        (2, 15, "08:45 08:50 08:55 08:58 09:00"),
        (2, 30, "08:30 08:42 08:50 08:55 08:58 09:00"),
        (2, 45, "08:15 08:29 08:42 08:50 08:55 08:58 09:00"),
        (2, 60, "08:00 08:29 08:42 08:50 08:55 08:58 09:00"),
        (2, 90, "07:30 08:08 08:29 08:42 08:50 08:55 08:58 09:00"),
        (2, 120, "07:00 07:34 08:08 08:29 08:42 08:50 08:55 08:58 09:00"),
        (1, 10, "08:50 08:54 08:57 08:59 09:00"),
        (1, 15, "08:45 08:49 08:54 08:57 08:59 09:00"),
        (1, 30, "08:30 08:41 08:49 08:54 08:57 08:59 09:00"),
        (1, 60, "08:00 08:28 08:41 08:49 08:54 08:57 08:59 09:00"),
        (1, 120, "07:00 07:33 08:07 08:28 08:41 08:49 08:54 08:57 08:59 09:00"),
        (3, 10, "08:50 08:57 09:00"),
        (3, 30, "08:30 08:44 08:52 08:57 09:00"),
        (3, 60, "08:00 08:31 08:44 08:52 08:57 09:00"),
        (3, 90, "07:30 08:10 08:31 08:44 08:52 08:57 09:00"),
    ])
    func vectors(firstGap: Int, window: Int, expected: String) {
        #expect(clock(SequenceGenerator.offsets(for: .fibonacci(windowMinutes: window, firstGap: firstGap))) == expected)
    }

    @Test func defaultIsDocumentedSequence() {
        let mode = GenerationMode.fibonacci(windowMinutes: SequenceGenerator.defaultFibonacciWindow,
                                            firstGap: SequenceGenerator.defaultFibonacciFirstGap)
        #expect(SequenceGenerator.offsets(for: mode).map(\.minutes) == [-60, -31, -18, -10, -5, -2, 0])
    }

    @Test func crossingMidnight() {
        let offsets = SequenceGenerator.offsets(for: .fibonacci(windowMinutes: 60, firstGap: 2))
        #expect(clock(offsets, targetHour: 0, targetMinute: 20) == "23:20 23:49 00:02 00:10 00:15 00:18 00:20")
    }

    @Test func gapsWithoutDuplicateOne() {
        #expect(Array(SequenceGenerator.fibonacciGaps(firstGap: 1).prefix(6)) == [1, 2, 3, 5, 8, 13])
        #expect(Array(SequenceGenerator.fibonacciGaps(firstGap: 2).prefix(4)) == [2, 3, 5, 8])
    }
}

struct ValidatorTests {
    @Test func blocksAboveMax() {
        let offsets = (0..<21).map(AlarmOffset.init)
        let issues = SequenceValidator.issues(for: offsets)
        #expect(issues.contains(.tooManyAlarms(count: 21, max: 20)))
        #expect(issues.contains { $0.blocksSaving })
    }

    @Test func twentyIsAllowed() {
        let offsets = SequenceGenerator.offsets(for: .interval(count: 19, minutes: 5, direction: .before))
        #expect(SequenceValidator.issues(for: offsets).isEmpty)
    }

    @Test func gapWarningIsNotBlocking() {
        let offsets = SequenceGenerator.offsets(for: .fibonacci(windowMinutes: 60, firstGap: 1))
        let issues = SequenceValidator.issues(for: offsets, gapWarningThreshold: 2)
        #expect(issues == [.gapBelowThreshold(fromMinutes: -1, toMinutes: 0, gap: 1, threshold: 2)])
        #expect(!issues.contains { $0.blocksSaving })
    }

    @Test func defaultFibonacciHasNoWarningsAtDefaultThreshold() {
        let offsets = SequenceGenerator.offsets(for: .fibonacci(windowMinutes: 60, firstGap: 2))
        #expect(SequenceValidator.issues(for: offsets).isEmpty)
        #expect(SequenceValidator.issues(for: offsets, gapWarningThreshold: 5).count == 2)
    }
}
