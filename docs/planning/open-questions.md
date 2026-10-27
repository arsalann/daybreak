Status: active
Created: 2026-10-26
Updated: 2026-10-26

# Open questions

Each question has a proposed default so the build isn't blocked. The build agent uses the default unless Arsalan has answered here.

| # | Question | Proposed default | Blocks |
|---|---|---|---|
| 1 | Is the Fibonacci rule in [sequence-algorithms.md](sequence-algorithms.md) right? (Default W = 60, first gap 2 → 08:00 08:29 08:42 08:50 08:55 08:58 09:00) Or does it need 5-minute snapping to look like the original example (8:00, 8:30, 8:45 …)? | Use the rule as written. Snapping is a later idea | M1 |
| 2 | Does "I'm up, cancel the rest" also cancel the target alarm? | Yes, you're already up | M4 |
| 3 | Max alarms per group | 20 | M1 |
| 4 | Default minimum gap warning | 2 minutes, configurable 1-10 | M3 |
| 5 | Sound | System default for every alarm in v1 | n/a |
| 6 | Group labels: include in v1 (cheap) or leave out? | Include a simple optional label if trivial, otherwise "Alarm" | M3 |
| 7 | App name (resolved 2026-10-26) | **Daybreak**, chosen by Arsalan | Resolved |
| 8 | If the M0 device spike shows that close-together alarms silence each other, what's acceptable? (Accept with a warning, a bigger min gap, or rethink) | Report to Arsalan with data, decide then | M2 |
| 9 | Repo name and GitHub account (personal `arsalann`?) | Personal account, `daybreak` (proposed repo slug; availability unchecked) | M1 |
| 10 | Countdown precision: seconds shown under 1 hour? | Yes for the hero, minutes elsewhere | M3 |
