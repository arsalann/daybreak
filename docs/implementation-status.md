# Implementation and validation — 2026-10-27

The placeholder was replaced by the full native list/editor and scheduling implementation. The latest user request extends the original v1 scope with manual children, per-child customization, clock input styles, sounds, and regular-alarm snooze.

## Structure

- `Models/AlarmGroup.swift`: persisted regular/target configuration and child settings, presets, validation.
- `Models/AlarmStore.swift`: versioned, atomically written local JSON; unreadable data is preserved.
- `Scheduling/AlarmPlanner.swift`: pure fixed/weekly plans, midnight shifting, occurrence suppression, reconciliation diff.
- `Scheduling/AlarmClient.swift`: AlarmKit adapter, alert actions, system/custom sounds.
- `Scheduling/AlarmModel.swift`: serialized MainActor mutations, write-ahead system IDs, retries, foreground/background reconciliation.
- `Intents/AlarmActionIntent.swift`: regular snooze and target I'm up, including cold launches.
- `Views/`: unified list, live countdowns, wheel/analog editor, weekday selection, presets, child settings, onboarding, and settings.

A preset is explicitly applied, with confirmation before replacing existing children. Matching offsets retain child customization; editing a child switches the sequence to Manual. Target moves shift children with it. Disabled children remain editable but are not scheduled. The lead-in window always includes the exact start, even when it is not a multiple of the chosen interval.

## Verification

- Xcode 27.1, Swift 6 strict concurrency, iPhone 17 simulator (iOS 27.0).
- App and device-spike simulator builds pass. **41 tests in 9 suites pass**, with no compiler warnings in the final app test run. Automated tests cover the original sequence/date vectors, preset windows, manual validation, JSON round trips, midnight weekday shifts, weekly suppression/bridging/restoration, incremental updates, scheduling failure/retry, cancellation failure, corrupt storage, expired/alerting one-offs, snooze, and idempotent I'm up.
- Simulator interaction verified: onboarding/denial banner, wheel-to-analog selection, selecting the target hour, weekday presets, label entry, editing a child's time/label/sound, saving regular and target alarms to the unified list, and persistence after relaunch. Persisted JSON was checked against the UI edits.
- The first simulator run exposed an omitted `NSAlarmKitUsageDescription` in the built plist. It is now explicitly declared in `project.yml` info properties for both the app and spike; the built plist was verified.
- AlarmKit authorization still returns denied on a fresh simulator bundle identity with the corrected metadata. Live ringing, locked-device intents, and sound delivery are **not verified** by these UI checks. Tests use an injected fake AlarmClient to exercise scheduling behavior without pretending system authorization succeeded.

## Remaining release checks

Run the existing physical-device spike and record actual audible times. Check Silent/Focus, lock screen, reboot, force quit, Low Power Mode, close gaps, capacity, custom tones, repeated snooze, stopped one-off cleanup, and denied/re-granted access. Verify I'm up from a child and target, crossing midnight and DST, with the app terminated. Confirm background restoration after suppression. Test Dynamic Type and VoiceOver on a device.

Repeating I'm up retains the original plan's background-execution limitation: a fixed bridge covers the skipped weekday next week, then full weekly restoration needs an app/background run. The UI and README tell users to reopen within a week. This needs further device validation before calling the app production-ready.

One-off fixed dates retain their absolute time after timezone travel; repeating alarms follow local time. Widgets, native countdown Live Activities, and App Store/TestFlight publication remain outside this implementation. No physical-device or store deployment was performed.
