Status: active
Created: 2026-10-26
Updated: 2026-10-26

# Daybreak

> Local copy of the planning folder from the `Chat` repo (`side_hustle/ios/alarm-app/`), copied 2026-10-26 with relative links adjusted. The source remains the planning source of truth; M0 device results live in this repo under `docs/research/`.

A simple iOS alarm clock with two niche features. It always shows how long until each alarm rings, and it can generate a group of alarms from one target time: a fixed number of alarms at a set interval before or after it, or a Fibonacci-style sequence whose gaps shrink as the target approaches (e.g. 08:00 08:29 08:42 08:50 08:55 08:58 09:00). It's built for Arsalan's own mornings first. The code will be open source (MIT) and the app may be published free on the App Store. This folder holds the research and planning. The code will live in a separate public GitHub repo.

## Current status
- **Name chosen (2026-10-26): Daybreak.** Naming exploration is complete; availability has not been checked.
- **Planning complete (2026-10-26). Build not started.** The next step is the M0 device feasibility spike in [technical requirements](technical-requirements.md).
- Main risk: developers report that AlarmKit alarms close together can silence each other or fire late on a locked phone. Apple hasn't responded. M0 tests this before any real build. See [research](2026-10-26-alarmkit-and-ios-alarm-landscape.md).

## Decisions (confirmed with Arsalan, 2026-10-26)
| Topic | Decision |
|---|---|
| App name | Daybreak |
| Platform / engine | iOS 26+ only, AlarmKit only (no notification fallback) |
| Countdown | In-app only for v1: each group row and a "next alarm" hero |
| Sequence modes | Fixed interval (before/after/both) and Fibonacci-style (target + start window) |
| Ringing actions | Stop = "Just this one". Secondary button "I'm up" cancels the rest of that occurrence |
| Repeats | One-off plus weekday repeats |
| Target alarm | One alarm per group is marked as the real target and shown differently |
| Not in v1 | Snooze, per-alarm sounds, labels per alarm, Live Activity/widget countdown, halving/custom modes |
| Design | Native iOS look, Clock-app style, dark-first |
| Code | New separate public GitHub repo, MIT, free, no tracking or analytics |

## Active files
- [AlarmKit and iOS alarm landscape research](2026-10-26-alarmkit-and-ios-alarm-landscape.md)
- [Build-agent kickoff prompt](build-agent-prompt.md)
- [Product spec (v1)](product-spec.md)
- [Sequence algorithms + test vectors](sequence-algorithms.md)
- [Technical requirements / build guide](technical-requirements.md)
- [Open questions (with defaults)](open-questions.md)
- Naming history: in the source planning repo, not copied
- Session handoff: `.context/alarm-app/handoff.md` (gitignored)

## Naming preference
Names must be easy to say and remember. Use familiar words with an interesting story; avoid awkward invented blends. Round 3 was rejected for being too weird. Daybreak was selected on 2026-10-26; see the naming history in the source planning repo.

## Working principles
Keep v1 small and native. Any feature that needs a widget extension (Live Activity countdown, snooze) waits until v1 has proven reliable. Record the device test results in this folder, so the AlarmKit quirks are written down for future work.
