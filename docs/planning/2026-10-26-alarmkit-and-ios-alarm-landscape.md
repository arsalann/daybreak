Status: active
Created: 2026-10-26
Updated: 2026-10-26

# AlarmKit and the iOS alarm landscape

Desk research done on 2026-10-26 to support the v1 build. Every claim is tagged:
- **[confirmed]**: stated in Apple's documentation.
- **[report]**: one or more developer forum posts, not confirmed by Apple.
- **[assumption]**: our inference, still to verify in Xcode or on a device.

## TL;DR
- AlarmKit (iOS 26+) is the right engine. It gives third-party apps real alarms that ring through Silent mode and Focus, schedule one-off or weekly alarms, and show a system alert with a Stop button plus one optional secondary button. **[confirmed]**
- **The biggest risk is our core feature.** Developers report that AlarmKit alarms scheduled close together can silence each other or fire late on a locked phone. Apple hasn't answered these reports. A group of alarms 2-3 minutes apart is exactly this case. **[report]** → The build has to start with a device spike (M0 in [technical requirements](technical-requirements.md)) before anything else.
- "I'm up, cancel the rest" fits the secondary button with `.custom` behaviour and an App Intent. "Just this one" is the standard Stop. **[confirmed API; behaviour to verify]**
- A widget extension is only required if we use the countdown presentation (snooze/pre-alert). v1 doesn't, so v1 can probably ship without one. **[confirmed requirement; "probably" is an assumption]**
- The niche is real but thin. Interval-series alarm apps exist (Relarm, Simple Repeat Alarm), but we found none with shrinking (Fibonacci-style) gaps, a target alarm, or "cancel the rest".

## 1. AlarmKit API surface

### Authorization [confirmed]
- `Info.plist` must contain `NSAlarmKitUsageDescription` with a non-empty string. Without it, apps can't schedule alarms at all.
- Call `try await AlarmManager.shared.requestAuthorization()`, which returns `.authorized` or another state. If you don't call it, AlarmKit asks automatically when the first alarm is scheduled. If permission is denied, nothing gets scheduled and nothing rings.

### Schedules [confirmed]
- `Alarm.Schedule.relative(.init(time: .init(hour:minute:), repeats: .never | .weekly([Locale.Weekday])))`: a wall-clock time, one-off or on chosen weekdays.
- `Alarm.Schedule.fixed(Date)`: an absolute date and time.
- Optional `Alarm.CountdownDuration` (`preAlert`, `postAlert`). This is for timers and for the snooze/"repeat" behaviour.
- **[assumption]** For us, `.relative` with weekly repeats maps naturally onto repeating groups (one AlarmKit alarm per generated time, each with the group's weekdays). Times that cross midnight need care: an alarm at 23:50 that belongs to a 00:20 Monday target is really on Sunday (see the product spec edge cases).

### Presentation and buttons [confirmed]
- `AlarmPresentation(alert:countdown:paused:)`. Only `alert` is required.
- `AlarmPresentation.Alert(title:, stopButton:, secondaryButton:, secondaryButtonBehavior:)`.
  - `secondaryButtonBehavior: .countdown` turns the secondary button into a Repeat/snooze action that fires again after `postAlert`.
  - `secondaryButtonBehavior: .custom` runs `secondaryIntent`. Apple's sample uses it for an "Open" button that launches the app.
- `AlarmAttributes(presentation:, metadata:, tintColor:)` wraps the presentation into ActivityKit attributes. `metadata` is our own `AlarmMetadata` type, which can carry the group ID and an `isTarget` flag.
- `AlarmManager.AlarmConfiguration(countdownDuration:, schedule:, attributes:, stopIntent:, secondaryIntent:)`, then `try await AlarmManager.shared.schedule(id: UUID, configuration:)`.
- The system forwards the alert to a paired Apple Watch automatically.

### State and management [confirmed]
- `AlarmManager.shared.alarmUpdates` is an async stream of the current alarms. An alarm missing from the stream is no longer scheduled.
- `cancel(id:)`, `stop(id:)`, `pause(id:)`, `resume(id:)` (exact throwing signatures to check in Xcode).

### Widget extension [confirmed]
- Apple: "AlarmKit expects a widget extension if an app supports a countdown presentation. Otherwise, the system may unexpectedly dismiss alarms and fail to alert."
- v1 has no snooze or countdown, so we can probably skip it. **[assumption]** If M0 shows alert-only alarms misbehaving without one, add a minimal widget extension.

### Limits
- We found no documented maximum number of alarms per app. **[unknown]** One developer reports about 60 fixed alarms working (with the issues below). M0 tests 30+.
- Sounds: the default system sound or a local sound file (`.named(...)`). No streaming. You can't set the volume or the alert duration. The alarm rings until the user acts. **[report + confirmed sound API]**

## 2. Known problems (developer reports, unanswered by Apple as of 2026-10-26)
| # | Issue | Source | Impact on us |
|---|---|---|---|
| 1 | Overlapping alarms silence each other. Alarms at +60/+180/+300 s: each new alarm silences the one ringing, and with nobody touching the phone all three end up silent. Stopping one makes the next audible. iPhone 16 Plus, iOS 26.6.2. FB24757864. | [thread 845563](https://developer.apple.com/forums/thread/845563) | **High.** If you sleep through 8:55 and 8:58 arrives, you might hear nothing. Must reproduce in M0. |
| 2 | Dense "fan-out" alarms (a series over ~50 min) sometimes fire 20 s to 4+ min late on a locked device. Rebooting helps temporarily. | [thread 825427](https://developer.apple.com/forums/thread/825427) | **High.** This is the same pattern as our groups. |
| 3 | Cancelling and rescheduling every alarm on each update caused alarms at midnight or late. The fix that worked was stable IDs and diffing (only add or remove what changed). An Apple DTS engineer asked for a bug report. | [thread 815714](https://developer.apple.com/forums/thread/815714) | **Design rule:** the scheduler must diff, never wipe and replace. |
| 4 | `stopIntent` didn't run when the alarm was dismissed from an unlocked screen. Swipe-to-dismiss can't be detected. | [thread 815064](https://developer.apple.com/forums/thread/815064), [Steve Troughton-Smith via mjtsai](https://mjtsai.com/blog/?p=48163) | Don't rely on Stop callbacks to update state. Reconcile from `alarmUpdates` instead. |
| 5 | A non-repeating alarm stays listed as `Scheduled` after it fires (also in Apple's sample). | [thread 796901](https://developer.apple.com/forums/thread/796901) | Clean up fired one-off alarms on app launch. Don't trust the state alone. |
| 6 | Volume buttons stop the audio but don't clear the alarm. | [thread 800265](https://developer.apple.com/forums/thread/800265) | Minor. Note in the device test checklist. |
| 7 | You can't make an alarm ring briefly and then stop without the user. | [thread 787924](https://developer.apple.com/forums/thread/787924) | Every alarm in a group rings until handled, which makes #1 worse. |
| 8 | Custom secondary-button intents: open questions on failures and on runs overlapping or being redelivered after a relaunch. | [849075](https://developer.apple.com/forums/thread/849075), [849069](https://developer.apple.com/forums/thread/849069) | Make "cancel the rest" idempotent. |

### What this means for the design
- Pick a default minimum gap of 2 minutes (not 1). Make the minimum gap configurable.
- **[assumption, to test in M0]** Ideas if #1 reproduces:
  1. Accept it. Stop on the ringing alarm makes the next one audible, so the user still hears something when they interact. The danger is only while asleep.
  2. Make "Just this one" work like Stop and tell the user in onboarding that sleeping through several alarms in a row may be quieter.
  3. Use one AlarmKit alarm per group with the `.countdown` repeat behaviour (`postAlert` = the next gap). AlarmKit only supports one fixed `postAlert`, though, so shrinking gaps would need the secondary intent to reschedule. This conflicts with the "cancel the rest" button.
  4. Raise a Feedback Assistant report and watch the threads. iOS point releases may fix it.
- If M0 shows the problem is severe and unfixable, go back to Arsalan before building M2+.

## 3. Why not notifications
Before iOS 26, third-party "alarms" were local notifications. Notification sounds are capped at about 30 seconds, the ring/silent switch and Focus mute them, and nothing rings if the app was force-quit and the user missed the banner. Apps like Alarmy worked around this by keeping the app open with background audio. Arsalan chose iOS 26+ with AlarmKit only, so none of this applies. It's noted here only to explain the decision. **[general knowledge, not re-sourced]**

## 4. Competitor scan
| App | What it does | Gap we fill |
|---|---|---|
| Stock Clock | Single alarms. The usual workaround is creating several alarms 5-10 min apart by hand, with snooze off. ([Digital Citizen](https://www.digitalcitizen.life/how-to-change-snooze-time-on-iphone/), [All Things How](https://allthings.how/how-to-change-snooze-time-on-iphone/)) | Manual and fiddly. No group dismiss. Clock shows the time until the alarm only briefly after you set it. |
| [Relarm: 5minute interval alarm](https://apps.apple.com/us/app/-/id6756233213) | A series at a fixed interval (1-10 min) and count, puzzle unlock, persistent sounds. | Fixed intervals only. No shrinking gaps, no target concept. |
| [Simple Repeat Alarm](https://apps.apple.com/ca/app/simple-repeat-alarm/id6751460680) | Start, end and interval (e.g. 5-120 min), rings at each interval. | Fixed intervals only. |
| Midnight Alarm Clock ([Mac Life](https://gb.readly.com/magazines/mac-life/2024-03-26/65fc5b22a248dda1c51d3b41)) | Organizes alarms into folders. | Grouping without generation. |
| Alarmy, Sleep Cycle | Wake-up missions and sleep tracking. **[general knowledge]** | Different focus. Heavy, subscription-based. |

Takeaway: interval-series alarms are an established small niche. What's different about ours is shrinking gaps, the target alarm, "cancel the rest", an always-visible countdown, and being free, open source and tracking-free. Not checked: ratings, downloads, or whether the competitors use AlarmKit.

## 5. App Store and open-source notes
- **[assumption]** Review risk is low. Use AlarmKit as intended, write a clear `NSAlarmKitUsageDescription`, and offer no hidden functionality.
- Privacy: no data collected → "Data Not Collected" nutrition label. A privacy policy URL is still required. A short page in the repo (GitHub Pages) works.
- MIT licence. Keep signing out of the repo: no `.p8`/`.p12`/provisioning profiles. Put `DEVELOPMENT_TEAM` in a git-ignored `Local.xcconfig` with a checked-in `Local.xcconfig.example`, so contributors use their own team ID.
- The app name, icon and screenshots are needed before submission. See name ideas (in the source planning repo, not copied).

## Sources (accessed 2026-10-26)
- Apple: [Scheduling an alarm with AlarmKit](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit), [AlarmManager.AlarmConfiguration](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarmconfiguration), [WWDC25 session 230: Wake up to the AlarmKit API](https://developer.apple.com/wwdc25/230)
- Notes: [WWDC Notes, session 230](https://wwdcnotes.com/documentation/wwdc25-230-wake-up-to-the-alarmkit-api/), [DEV Community write-up](https://dev.to/arshtechpro/wwdc-2025-wake-up-to-the-alarmkit-api-ios-26-4e67)
- Forums: linked in the table above
- Competitors: linked in the table above
