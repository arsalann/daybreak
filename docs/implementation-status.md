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

## Stray alarm hardening — 2026-10-29

A user with one 10:00 target (60-minute lead-in) heard alarms at about 10:26 PM and at another daytime time. No Daybreak planning path produces those times from that configuration. The likely cause is the AlarmKit misfire reported after cancel-and-reschedule churn (landscape doc, known issue #3). The scheduler used to cancel and reschedule the same ID on every change, the v1→v2 sound migration, Random re-rolls and repeating "I'm up". Changes:

- Every (re)schedule uses a fresh AlarmKit ID, and the old ID is cancelled. IDs are never reused.
- Orphans (live alarms with no record) are cancelled even while ringing.
- Mutations are serialized: intents, saves and deletes wait for an in-flight sync instead of failing with "busy", and refreshes requested during a sync are queued, not dropped.
- Storage load is retried. Before the first unlock after a reboot the protected file is unreadable, which used to leave the model failed for the whole process.
- Stale or redelivered snooze and "I'm up" intents are ignored unless the alarm is ringing or was due in the last 3 hours. A ringing alarm with no record is stopped.
- A background refresh is kept pending whenever the app is backgrounded.
- Settings → Activity log records every schedule, cancel, action and ringing alarm (expected or unexpected), so the next stray alarm can be diagnosed and shared.

Still open: repeating "I'm up" inherently cancels and reschedules the remaining weekly children (suppress, then restore). That is the heaviest remaining churn.
