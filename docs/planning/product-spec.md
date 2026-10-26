Status: approved
Created: 2026-10-26
Updated: 2026-10-26

# Daybreak: product spec v1

Scope decisions were confirmed with Arsalan on 2026-10-26. Items marked *(proposed)* are defaults chosen during planning and listed in [open questions](open-questions.md).

## Product in one line
Daybreak is a no-nonsense iOS alarm clock that always tells you how long until it rings, and lets you build a group of alarms around one target time instead of setting six alarms by hand.

## Who it's for
Arsalan first: someone who needs several alarms to get up and currently sets them one by one. Then anyone with the same habit, via a free App Store listing and a public MIT repo.

## Concepts
- **Alarm group**: one target time plus a generation mode. It produces 1-20 alarms. A plain single alarm is just a group with one alarm and no mode.
- **Target alarm**: the one "real" alarm in a group (the get-up time). It's always generated, visually distinct (bold, tinted, labelled "Target"), and by default it's the anchor time.
- **Occurrence**: one day's run of a group. For repeating groups, "cancel the rest" applies only to the current occurrence. The group rings again on its next scheduled day.

## Screens

### 1. Alarm list (home)
- **Next-alarm hero** at the top: "Next alarm in 7h 42m" plus the time and group name ("09:00 · Weekdays"). Updates live (each minute; seconds only under 1 hour, *proposed*). When there's no alarm: "No alarms set".
- **Groups** below, sorted by next fire time. Each row shows the target time (large), a compact strip of the other times ("08:00 · 08:29 · 08:42 · …"), the repeat days, an enabled toggle, and **its own countdown** ("in 7h 42m"). Disabled groups are greyed out with no countdown.
- If a group's occurrence was cancelled with "I'm up", the row shows "Done for today · next Tue 09:00 in 1d 23h".
- "+" opens the editor. Tap a row to edit it. Swipe to delete.
- Native look: `List`, large title, dark-first, system tint.

### 2. Group editor (sheet)
- Target time picker (wheel, like Clock).
- Mode segmented control: **Single** · **Interval** · **Fibonacci**.
  - Interval: count (stepper), interval in minutes (picker 1-120), direction (Before / After / Both).
  - Fibonacci: window (15 / 30 / 45 / 60 / 90 / 120 min, default 60), first gap (1 / 2 / 3 min, default 2) under an "Advanced" disclosure.
- Repeat: weekday chips (Mon-Sun). None means one-off.
- Label: plain text field for the group (*proposed* as a nice-to-have. Arsalan didn't pick labels for v1, so implement only if it costs nothing. Otherwise "Alarm").
- **Live preview**: the generated times as a vertical timeline, with the target highlighted and each alarm's countdown ("in 7h 02m"). Shows warnings inline: "Gaps under 2 min may be quiet if you sleep through them", "Max 20 alarms".
- Save validates, schedules, and returns to the list.

### 3. Ringing (system UI, not ours)
AlarmKit shows the system alarm alert (Lock Screen, Dynamic Island, banner, Apple Watch). We control the title and two buttons:
- **Stop** (system button) = "Just this one". Stops this alarm. The rest of the group stays.
- **Secondary button "I'm up"** (`.custom` behaviour → `CancelRestIntent`) = cancels every remaining alarm in this occurrence of the group, **including the target** *(proposed)*.
- The title tells you where you are, e.g. "Wake-up · 3 of 7 · target 09:00". For the target alarm: "09:00 · Target".

### 4. First launch / permissions
A one-screen explainer, then the AlarmKit authorization prompt. If permission is denied, the list shows a persistent banner with a Settings deep link. Nothing can be scheduled while it's denied.

### 5. Settings (minimal)
Minimum gap warning threshold (1-10, default 2), and an About section (version, GitHub link, privacy policy link, licence).

## Core flows
1. **Make a wake-up group:** + → set 09:00 → Fibonacci → window 60 → Mon-Fri → preview shows 08:00 08:29 08:42 08:50 08:55 08:58 09:00 → Save → list row "09:00 · in 9h 12m".
2. **Wake at 08:42:** alarm rings → tap "I'm up" → 08:50…09:00 for today are cancelled → row shows "Done for today · next Tue". Tomorrow's alarms are unaffected.
3. **Snoozy morning:** ring at 08:42 → Stop → ring at 08:50 → Stop … → target at 09:00 → Stop.
4. **One-off 5-minute follow-ups:** + → 06:30 → Interval, 5 × 5 min after → no repeat → Save. After the last alarm fires, the group shows as disabled (like Clock) and stays in the list.

## Edge cases and rules
- **Crossing midnight:** all offsets are relative to the target. A Monday 00:20 target with a 60 min window makes 23:20 and 23:49 alarms on **Sunday**. For weekly repeats, each generated alarm gets its own weekday set, shifted back one day where needed (`Locale.Weekday` for each alarm = target weekdays shifted by the day offset).
- **One-off whose times are partly in the past:** when saving, if the target is already past today, schedule for tomorrow (like Clock). If the target is still ahead but some earlier alarms have passed, schedule only the future ones and say so in the preview ("2 earlier alarms skipped").
- **DST:** use wall-clock `.relative` schedules (hour/minute), so a 09:00 alarm stays at 09:00. Generated times that land in a skipped hour (spring forward): let AlarmKit/the calendar decide, and note it in the device checklist. *(Verify on a simulator by changing time zones.)*
- **Editing a group:** recompute the desired set, then diff it against the existing AlarmKit alarms by stable ID (see technical requirements). Never cancel everything and reschedule.
- **Duplicate times** (e.g. both directions with X = 0): de-duplicate. Interval minimum is 1 minute.
- **Max 20 alarms per group** *(proposed)*. Max total alarms across groups: unknown. The app should handle AlarmKit scheduling errors gracefully and tell the user.
- **Permission revoked later:** detect on foreground, show the banner, keep the groups.
- **Time zone change while travelling:** wall-clock alarms follow local time (same as Clock).

## Out of v1 (later ideas)
- Live Activity / Lock Screen / Dynamic Island countdown before the alarm (needs a widget extension)
- Home or Lock Screen widget with the next alarm
- "Alarm set for 7h 42m from now" toast when saving
- Halving gaps mode, fully custom offsets mode, snapping to 5-minute marks
- Snooze (AlarmKit countdown `.countdown` behaviour; needs a widget extension)
- Different sound per alarm, custom sounds, gentle-to-loud progression
- Labels per alarm
- Skip next occurrence / holiday pause
- Apple Watch app (the system already mirrors the alert)
- iCloud sync, Shortcuts/App Intents for "set my wake-up group"

## Non-goals
Sleep tracking, wake-up missions or puzzles, accounts, analytics, ads, a backend.
