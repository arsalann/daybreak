# Daybreak

A private, native iOS alarm clock with a little rhythm. Set a regular alarm, or build a sequence of individually customizable child alarms around one target time.

## Features

- Regular and target alarms in one list; tap to edit, toggle, duplicate, or swipe to delete.
- Live next-alarm countdown and individual group countdowns.
- Wheel and interactive analog clock pickers, labels, one-off alarms, and weekday repeats.
- Fibonacci, 5-minute, and 10-minute presets with a lead-in window; custom intervals before/after/both; fully manual children.
- Individual child time, label, sound, and enabled state. Preview, duplicate-time validation, 20-alarm limit, and small-gap warnings.
- System sound plus three original bundled tones with previews.
- Configurable snooze for regular alarms. Target alarms offer **I'm up** to cancel the remaining alarms in that occurrence; **Stop** silences only the current alarm.
- AlarmKit authorization, actionable error/retry states, and local JSON persistence with stable system alarm IDs.
- Dark charcoal and warm amber interface, onboarding, settings, and an original sunrise icon.

No accounts, ads, analytics, tracking, or alarm-data network calls. [Privacy](docs/privacy.md). MIT licensed. iOS 26+, Swift 6, SwiftUI, AlarmKit; no dependencies.

## Build and test

1. Install Xcode 26 or later.
2. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set your `DEVELOPMENT_TEAM` and `BUNDLE_ID_PREFIX` for a device build.
3. Open `Daybreak.xcodeproj`. `Daybreak` is the app and tests; `DaybreakSpike` is the real-device AlarmKit reliability harness.
4. Choose an available iPhone simulator, then run:

```sh
xcodebuild test -project Daybreak.xcodeproj -scheme Daybreak \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

If command-line tools are selected instead of Xcode, prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

The project is generated with XcodeGen from `project.yml`. Run `xcodegen generate` after adding source files or changing project settings. `swift Tools/generate-icon.swift` regenerates the opaque 1024px app icon.

## Scheduling and current limits

One-offs use fixed dates and skip children already in the past. Weekly schedules use local wall-clock times, shifting weekdays for children across midnight. Saving updates only changed system alarms. IDs are persisted before scheduling, so retries and relaunches can recover partially completed operations. Errors remain visible; an alarm is not presented as successfully synced when scheduling fails.

Snooze uses a new fixed alarm through a custom App Intent, so it does not require a countdown widget extension. Target alarms use the secondary button for **I'm up** instead of snooze.

For repeating targets, **I'm up** temporarily removes the affected weekday from remaining alarms and schedules a fixed bridge for next week. Foreground reconciliation and a best-effort background refresh restore the full weekly schedules. **Open Daybreak within a week after using I'm up on a repeating target.** If iOS never grants background execution and the app is never reopened, that skipped weekday is not covered beyond the bridge. Other weekdays are unaffected. This limitation is also shown in Settings.

The implementation builds and its automated tests pass, but **real-device ringing reliability is not yet certified**. The current simulator reports AlarmKit authorization denied, so simulator UI checks cover configuration/persistence rather than live ringing. Run the [device protocol](docs/research/m0-device-spike-protocol.md) before relying on it as your sole wake-up alarm. Closely spaced AlarmKit alarms have reported reliability issues; see [research](docs/planning/2026-10-26-alarmkit-and-ios-alarm-landscape.md).

See [implementation and validation notes](docs/implementation-status.md) for the verification record and remaining checks.
