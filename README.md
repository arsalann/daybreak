# Daybreak

A free, open-source iOS alarm clock that always shows how long until it rings, and builds a group of alarms around one target time: a fixed interval before/after it, or Fibonacci-style gaps that shrink as the target approaches (08:00 08:29 08:42 08:50 08:55 08:58 09:00).

**Status:** early. Pure sequence logic and tests are in; the AlarmKit device feasibility spike (M0) is built but not yet run on a device. See [docs/planning](docs/planning/README.md).

- iOS 26+, Swift 6, SwiftUI, AlarmKit. No dependencies.
- No accounts, ads, analytics, tracking or network calls. See [privacy](docs/privacy.md).
- MIT licence.

## Build
1. Xcode 26 or later.
2. `cp Config/Local.xcconfig.example Config/Local.xcconfig` and set your own `DEVELOPMENT_TEAM` and `BUNDLE_ID_PREFIX`.
3. Open `Daybreak.xcodeproj`. Schemes: `Daybreak` (app + tests), `DaybreakSpike` (M0 AlarmKit test app).
4. Tests: `xcodebuild test -project Daybreak.xcodeproj -scheme Daybreak -destination 'platform=iOS Simulator,name=iPhone 17'`.

The project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`; run `xcodegen generate` after changing it.

## Known AlarmKit limits
Developers report that AlarmKit alarms close together can silence each other or fire late on a locked phone ([845563](https://developer.apple.com/forums/thread/845563), [825427](https://developer.apple.com/forums/thread/825427)). Daybreak's M0 spike tests this before the app is built. See [the research notes](docs/planning/2026-10-26-alarmkit-and-ios-alarm-landscape.md).
