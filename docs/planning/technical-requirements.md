Status: approved
Created: 2026-10-26
Updated: 2026-10-26

# Daybreak: technical requirements and v1 build guide

Written for the agent that builds the app. Read this, the [product spec](product-spec.md), the [sequence algorithms](sequence-algorithms.md) and the [AlarmKit research](2026-10-26-alarmkit-and-ios-alarm-landscape.md). Check [open questions](open-questions.md) for defaults that may still change.

## Stack (decided)
| Area | Choice |
|---|---|
| Platform | iOS 26.0+ (iPhone; iPad allowed but not designed for) |
| Language / UI | Swift 6 (strict concurrency), SwiftUI, Observation (`@Observable`) |
| Alarms | AlarmKit only. No UserNotifications fallback |
| Persistence | SwiftData, local only *(JSON in the app container is also fine. Pick whichever is simpler; the data is tiny)* |
| Tests | Swift Testing (`@Test`) for logic, XCUITest optional |
| Dependencies | None. No SPM packages, no analytics, no crash reporting SDKs, no network calls |
| Licence | MIT |
| Repo | New public GitHub repo created by the build agent; app name **Daybreak** (chosen 2026-10-26), proposed repo slug `daybreak` (availability unchecked) |

## Architecture
```
Views (SwiftUI)
  AlarmListView ── NextAlarmHero, GroupRow (countdown)
  GroupEditorView ── live preview via SequenceGenerator
        │
AppModel (@Observable, @MainActor)
        │ owns
  GroupStore (SwiftData)        AlarmScheduler ──► AlarmClient (protocol)
        │                              │                 ├─ LiveAlarmClient (AlarmManager.shared)
  AlarmGroup models             SequenceGenerator        └─ FakeAlarmClient (tests)
                                (pure functions)
  CancelRestIntent (LiveActivityIntent, app target)
```

### Models
```swift
struct AlarmGroup: Identifiable, Codable {
  var id: UUID
  var label: String
  var targetHour: Int, targetMinute: Int
  var mode: Mode            // .single | .interval(count, minutes, direction) | .fibonacci(windowMinutes, firstGap)
  var repeatDays: Set<Locale.Weekday>   // empty = one-off
  var isEnabled: Bool
  var oneOffTargetDate: Date?           // resolved when saved for one-offs
  var scheduled: [ScheduledAlarm]       // what we believe is in AlarmKit
}
struct ScheduledAlarm: Codable { var alarmID: UUID; var offsetMinutes: Int; var isTarget: Bool; var weekdays: Set<Locale.Weekday> }
struct AlarmMetadata: AlarmKit.AlarmMetadata { var groupID: UUID; var offsetMinutes: Int; var isTarget: Bool }
```

### SequenceGenerator
- Pure: `(mode) -> [Offset]` where `Offset = (minutes: Int relative to target, isTarget: Bool)`. Negative offsets are before the target; positive offsets are after. No dates. A separate validator compares gaps with the configured warning threshold.
- A separate pure function maps offsets + target + repeat days → concrete schedules (handles day shifts for times before midnight).
- Unit-tested with every vector in [sequence-algorithms.md](sequence-algorithms.md).

### AlarmScheduler (most important component)
- `reconcile(group)` computes the **desired** set of `(stable key → schedule)` and diffs it against what AlarmKit reports in `alarmUpdates`/`alarms`. It only cancels removed alarms and schedules added ones. **Never cancel everything and reschedule** (forum reports link that to alarms firing at midnight).
- Stable key = `groupID + offsetMinutes`. Keep a `key → AlarmKit UUID` map in the store.
- Runs `reconcileAll()` on: launch, foreground, every `alarmUpdates` emission (debounced), after any edit, and inside `CancelRestIntent`.
- Cleans up one-off alarms that have already fired but still show as `scheduled` (a known AlarmKit quirk).

### Schedule mapping
- **One-off groups:** `.fixed(Date)` for each generated alarm, with the exact date computed from the resolved target date. This handles crossing midnight and skips times already in the past. (`.relative(.never)` would push a past time to tomorrow, which is wrong for a group.)
- **Repeating groups:** `.relative(time, .weekly(days))` for each generated alarm. `days` = the target weekdays, shifted back one day for alarms before midnight when the target is just after it.
- **"I'm up" on a repeating group (hard part).** Cancelling a weekly alarm also kills its future occurrences. Recommended approach, to validate in M4:
  1. For each remaining alarm in today's occurrence, cancel the weekly alarm and reschedule it as weekly **minus today's weekday**. Also schedule a one-off `.fixed` alarm for the same time next week (if that weekday is still in the group's set).
  2. Keep a `suppressedUntil` date on the group. The next `reconcileAll()` after today ends (app launch, `BGAppRefreshTask`, or any intent run) restores the full weekly set and removes the fixed stand-ins.
  3. If the app never runs again, the stand-ins still cover next week. The week after would be missing, so ask for `BGAppRefreshTask` and document this limitation.
  - Alternative if this proves flaky: schedule everything as rolling `.fixed` alarms for the next 2 occurrences and refresh on every app/intent/background run. That's simpler but relies more on the app getting run time.
- **Titles:** `"\(label) · \(i) of \(n)"`, target: `"\(time) · Target"`. Tint: system accent. Target alarms could use a different tint *(check whether `tintColor` per alarm is visible)*.

### Ringing actions
- Stop: system default, `stopIntent: nil`. Don't rely on a stop intent running (forum report).
- Secondary: `secondaryButton: AlarmButton(text: "I'm up", textColor:…, systemImageName: "sun.max")`, `secondaryButtonBehavior: .custom`, `secondaryIntent: CancelRestIntent(groupID:, occurrenceDate:)`.
- `CancelRestIntent: LiveActivityIntent`, in the **app target**. It stops the current alarm, cancels the remaining alarms in this occurrence (offsets later than the ringing one), and updates the store. It must be **idempotent** (it may run twice or after a relaunch) and safe if some IDs are already gone. *(Verify on device that a `.custom` secondary intent runs while the phone is locked without opening the app. If it always opens the app, that's acceptable, but note it.)*

### Countdown UI
- `TimelineView(.everyMinute)` for rows. For the hero: `Text(timerInterval:)` or `.periodic(by: 1)` when under 1 hour.
- Next fire date: take the next real date from AlarmKit where available, otherwise compute it from the schedule. One helper, `nextFireDate(for:)`, unit-tested including weekday wrap and midnight.
- Formatting: `Duration`/`DateComponentsFormatter` → "7h 42m", "42m", "under 1m", "1d 3h".

## Targets, capabilities and Info.plist
- App target only for v1. **No widget extension** unless M0 shows alert-only alarms need one. (Apple requires one only for the countdown presentation.)
- `Info.plist`: `NSAlarmKitUsageDescription` = "Daybreak schedules the wake-up alarms you create so they ring even in Silent mode or Focus." Plus `BGTaskSchedulerPermittedIdentifiers` if using `BGAppRefreshTask`, and Background Modes → Background fetch.
- No push, no App Groups (unless a widget is added later), no Critical Alerts entitlement.

## Milestones
| # | Goal | Done when |
|---|---|---|
| **M0** | **Device feasibility spike** (throwaway target or branch, real iPhone on iOS 26.x latest) | A written result in this folder (`research/YYYY-MM-DD-m0-device-spike.md`) covering: (a) 7 alarms at Fibonacci default gaps, phone locked, untouched: which are audible and on time? (b) the same at a 3/5 min min gap; (c) does the `.custom` secondary intent run while locked and can it cancel siblings; (d) do alert-only alarms work with no widget extension; (e) 30+ alarms scheduled at once: any errors? **If (a) shows silent alarms, stop and report to Arsalan before M2.** |
| M1 | Repo, project skeleton, SequenceGenerator + date mapping + tests | All vectors pass. CI runs `xcodebuild test` |
| M2 | AlarmScheduler with diff/reconcile for one-off groups, FakeAlarmClient tests | Create/edit/delete one-off groups on device. No duplicate alarms after edits |
| M3 | List + editor UI with live preview and countdowns | Flows 1 and 4 in the product spec work |
| M4 | "I'm up" CancelRestIntent | Flow 2 works on a locked device for one-off and repeating groups |
| M5 | Weekly repeats + crossing midnight + restore logic + BG refresh | Device checklist passes |
| M6 | Polish, onboarding/permission, settings, app icon, privacy policy page, TestFlight | Arsalan uses it daily for a week |

## Testing
- **Unit (Swift Testing):** the generator vectors, midnight/weekday shifting, `nextFireDate`, the reconcile diff (desired vs actual → adds/removes), idempotent cancel-rest, max group size validation and minimum-gap warnings.
- **FakeAlarmClient** records `schedule`/`cancel` calls and lets you inject `alarmUpdates`.
- **Device checklist** (record the results in the handoff): Silent switch on, Focus on, locked, Always On Display, Low Power Mode, after a reboot, app force-quit, volume buttons during an alarm, Apple Watch mirroring, DST (change the time zone or wait), time zone travel, permission denied then granted.

## Repo setup
```
daybreak/
  Daybreak.xcodeproj
  Daybreak/ (App, Models, Scheduling, Generation, Views, Intents, Resources)
  DaybreakTests/
  Config/Base.xcconfig, Config/Local.xcconfig.example   # Local.xcconfig is git-ignored (DEVELOPMENT_TEAM, bundle ID prefix)
  docs/privacy.md                                       # served via GitHub Pages for the App Store
  .github/workflows/test.yml                            # xcodebuild test on macos-latest, iOS 26 simulator
  LICENSE (MIT), README.md, .gitignore (Xcode)
```
- No secrets, certificates or provisioning profiles in the repo. Contributors set their own team ID in `Local.xcconfig`.
- README: what it does, screenshots, build instructions, the known AlarmKit limits (link the forum threads).

## App Store readiness (M6)
- Privacy nutrition label: Data Not Collected. Privacy policy URL (GitHub Pages).
- Free, no IAP. Category: Utilities (or Lifestyle).
- Screenshots: list with countdown, editor with Fibonacci preview, ringing alert.
- App Review notes: explain the alarm groups and that every alarm is created by the user.
- App name: Daybreak (chosen by Arsalan). Icon still needs a decision before submission.
