Status: active
Created: 2026-10-26
Updated: 2026-10-26

# Daybreak build-agent prompt

Paste the following into the agent working in the app's repository:

```text
Build Daybreak, my free, open-source iOS alarm app, in this repository. First inspect the existing repo and its agent instructions; preserve existing work.

The planning source is in my local Chat workspace:
/Users/maya/Documents/GitHub/Chat/side_hustle/ios/alarm-app/
If that path is unavailable, retrieve the same directory from https://github.com/arsalann/Chat on main. If neither is accessible, ask me for the planning files instead of inventing requirements. Do not read the Chat repo's bruin/ folder.

Read README.md, planning/product-spec.md, planning/sequence-algorithms.md, planning/technical-requirements.md, planning/open-questions.md and research/2026-10-26-alarmkit-and-ios-alarm-landscape.md. Copy these into docs/planning/ in this app repo, adjusting relative links, so implementation has a local reference. Keep the source planning repo unchanged.

Create or update .context/daybreak/handoff.md before starting. Record decisions, TODOs, blockers and verification after every milestone. Use Daybreak for the app and Xcode project name. This is already the app repo; do not create another repository.

Confirmed scope:
- iOS 26+, Swift 6, SwiftUI, AlarmKit. Native look, dark-first.
- A live time-until-next-alarm hero, group countdowns and an editor preview.
- Single alarms and groups generated around one target time: fixed intervals before/after/both, or Fibonacci-style shrinking gaps.
- One-off and weekday repeats; distinguish the target alarm.
- Stop affects only the current alarm. “I'm up” cancels the remaining alarms in that occurrence, including the target, while preserving future repeat occurrences.
- Local persistence, MIT, free, no tracking, accounts, ads, backend or external dependencies.
- No snooze, widgets, custom sounds or Live Activities in v1 unless required for basic AlarmKit alerts and confirmed during M0.

Use the documented proposed defaults where unresolved: Fibonacci window 60 min and first gap 2 min gives 08:00, 08:29, 08:42, 08:50, 08:55, 08:58, 09:00 for a 09:00 target; max 20 alarms per group; minimum supported interval 1 min; configurable gap warning threshold default 2 min (warning, not a saving restriction). Public offsets are signed minutes: negative before the target, positive after. Interval count is additional alarms per selected side, excluding the target; interval range 1-120 min. Label the remaining product defaults as provisional.

Start with M0: a minimal device feasibility spike, before building the full UI. Verify the current Apple SDK APIs rather than trusting uncompiled planning snippets. On a real iPhone, test the documented Fibonacci sequence with the phone locked, close alarms at 3/5 minute gaps, Stop versus “I'm up”, custom intents while locked, alert-only alarms without a widget, and scheduling 30+ alarms. Record device/iOS version, expected and actual fire times, audibility and cancellation/repeat results. Never claim device verification from a simulator. If a device or signing is unavailable, build the spike and simulator-testable pure logic, document exactly what remains unverified, and request the specific device run needed. Do not proceed past the feasibility gate into M2 until the required device results are available. If alarms silence each other or fire late, report the evidence and wait for my decision before M2.

Once M0 passes, work through M1-M6 in the build guide. Diff schedules by stable group+offset keys; never cancel everything and reschedule. Validate repeating “I'm up” behaviour carefully: the proposed recovery strategy has a documented missing-future-occurrence risk and is not proven. Do not present it as reliable until tested. Test sequence vectors, signed offsets, midnight/weekday shifts, DST/time zones, reconciliation, idempotent cancellation and repeat preservation.

Progress autonomously through unblocked milestones. Keep the handoff current and end each work session with what changed, what passed, what needs a real device and the next concrete step. Do not publish to the App Store without my instruction. The name Daybreak is selected; App Store/domain/trademark availability has not been checked.
```
