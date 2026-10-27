Status: active
Created: 2026-10-26
Updated: 2026-10-26

# M0 device feasibility spike: protocol

The `DaybreakSpike` target ("Daybreak M0" on the home screen) is a throwaway app for testing AlarmKit on a real iPhone before the real build. Results go in `docs/research/YYYY-MM-DD-m0-device-spike.md`. **Simulator runs don't count as device verification.**

## Setup
1. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set your team. Then `xcodebuild -scheme DaybreakSpike -destination 'id=<UDID>' -allowProvisioningUpdates` or run from Xcode.
2. Open Daybreak M0 → **Request AlarmKit authorization** → Allow.
3. Note the device and iOS version shown under Setup. Ringer volume up. Silent mode as you normally sleep.
4. Run one test at a time. Use **Cancel all alarms** and **Clear records and log** between tests.

Every spike alarm is alert-only (no widget extension, no countdown presentation), has the system Stop button, and an "I'm up" secondary button (`.custom` → `SpikeImUpIntent`, `openAppWhenRun = false`). Times are `.fixed(Date)` except test F.

## Tests
| # | Button | What to do | Record |
|---|---|---|---|
| a | A · Fibonacci default | Lock the phone, leave it face down and untouched for the full ~63 min (gaps 29 13 8 5 3 2). Have a second clock or a screen/audio recording to note when each alarm is heard. | For each of the 7 alarms: heard? on time (seconds late)? did a new alarm silence the ringing one? |
| a2 | A again | Same, but tap **Stop** on each alarm as it rings. | Each alarm audible after stopping the previous one? |
| b | B1 (3 min) and B2 (5 min) | Separate runs, locked, untouched. | Same as (a). |
| c | C · 4 alarms, 2 min apart | Locked. On alarm 2 tap **I'm up** without unlocking. | Did the app open or ask for Face ID? Did alarms 3 and 4 (target) stay silent? Open the app later: log should show `INTENT cancel ok` lines. |
| c2 | C again | Tap **Stop** on alarm 1, **I'm up** on alarm 2 while unlocked. | Same as (c). |
| d | (all) | Covered by every run: no widget extension. | Any alarm dismissed without alerting, or missing Lock Screen/Dynamic Island UI? |
| e | E · Capacity | Tap once (35 alarms tomorrow). Tap again for 70. | Status line: scheduled/failed counts, any `maximumLimitReached`. Then **Cancel all alarms** and check AlarmKit reports 0. |
| f | F · Weekly repeat | Two weekly alarms today, 2 min apart. Stop alarm 1, then I'm up on alarm 2 (it is the target, so nothing after it). | After both, open the app: are both still listed as `scheduled` (next week preserved)? Cancelling a weekly alarm removes all future occurrences — this test only checks Stop keeps the repeat. |
| g | (any one-off run) | After it finishes, open the app. | Do fired one-off alarms still show `scheduled` (known quirk #5)? |

## After each test
- In **Records**, tap each alarm and choose what happened.
- **Export report** (share sheet → AirDrop/Files) and attach it to the results file. It contains the device/iOS version, expected times and the event log.
- The log only captures `UPDATE` state changes while the app is running, so "actual fire time" while locked comes from your own observation (or a screen recording on another device).

## Gate
If (a) shows silent or late alarms, stop and report to Arsalan with the data before M2 (open question 8).
