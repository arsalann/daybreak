Status: draft
Created: 2026-10-26
Updated: 2026-10-26

# Sequence algorithms

Exact rules for turning one target time into a group of alarms. These go into a pure `SequenceGenerator` (no AlarmKit, no dates beyond what's needed) and are unit-tested against the vectors below. The fixed interval rule is settled. **The Fibonacci rule is a proposal, so Arsalan should confirm it** (see [open questions](open-questions.md)). Until then, build exactly what's written here.

## Common rules
- All values are whole minutes. Generated times are rounded to the minute (seconds = 0).
- Public generator offsets are signed minutes relative to the target: negative before it, zero at it, positive after it. Convert them to dates by adding them to the target date with calendar arithmetic. The Fibonacci pseudocode below uses positive backward distances internally, which become negative public offsets. This handles crossing midnight (see the edge cases in the [product spec](product-spec.md)).
- The output is sorted ascending and de-duplicated. The target is always included and always flagged `isTarget = true`.
- Max group size: 20 alarms (proposed; see open questions). The editor blocks saving above that and explains why.
- Minimum supported interval is 1 minute. The user setting `minGap` (default 2, range 1-10) is a warning threshold, not a saving restriction. The editor warns about smaller gaps without silently changing or rejecting them. (Background: alarms close together may silence each other. See [research](2026-10-26-alarmkit-and-ios-alarm-landscape.md).)

## Mode 1: Fixed interval
Inputs: target `T`, count `N` (1-19), interval `X` minutes (1-120), direction `before | after | both`.

```
before: T - X*i for i in 1...N
after:  T + X*i for i in 1...N
both:   both of the above (N each side, so up to 2N + 1 alarms)
result = sorted(before + [T] + after)
```

The target is always included. "Target 9:00, 5 follow-ups every 5 min" therefore gives 6 alarms.

| Input | Output |
|---|---|
| T=09:00, N=5, X=5, after | 09:00 09:05 09:10 09:15 09:20 09:25 |
| T=09:00, N=5, X=5, before | 08:35 08:40 08:45 08:50 08:55 09:00 |
| T=09:00, N=2, X=10, both | 08:40 08:50 09:00 09:10 09:20 |
| T=09:00, N=3, X=15, before | 08:15 08:30 08:45 09:00 |

## Mode 2: Fibonacci-style (shrinking gaps)
Inputs: target `T`, window `W` minutes (10-180, default 60), first gap `g0` ∈ {1, 2, 3} (default 2; the gap right before the target).

Idea: walk backward from the target using Fibonacci gaps, so alarms get denser as the target gets closer. The first alarm always sits exactly at `T - W`.

```
gaps     = Fibonacci numbers >= g0, no duplicates  (g0=2 → 2, 3, 5, 8, 13, 21, 34, …)
offsets  = []
c = 0
for g in gaps:
    if c + g >= W: break
    c += g; offsets.append(c); lastGap = g
# Avoid a tiny first gap: if the leftover from the window start to the
# outermost alarm is less than half the gap before it, merge them.
if offsets and (W - offsets.last) * 2 < lastGap: offsets.removeLast()
offsets = [0] + offsets + [W]
result  = sorted(T - o for o in offsets)
```

### Test vectors (computed 2026-10-26 with the reference script below)
| g0 | W | Output (T = 09:00) | Gaps (min) |
|---|---|---|---|
| 2 | 10 | 08:50 08:55 08:58 09:00 | 5 3 2 |
| 2 | 15 | 08:45 08:50 08:55 08:58 09:00 | 5 5 3 2 |
| 2 | 30 | 08:30 08:42 08:50 08:55 08:58 09:00 | 12 8 5 3 2 |
| 2 | 45 | 08:15 08:29 08:42 08:50 08:55 08:58 09:00 | 14 13 8 5 3 2 |
| **2** | **60** | **08:00 08:29 08:42 08:50 08:55 08:58 09:00** (default) | 29 13 8 5 3 2 |
| 2 | 90 | 07:30 08:08 08:29 08:42 08:50 08:55 08:58 09:00 | 38 21 13 8 5 3 2 |
| 2 | 120 | 07:00 07:34 08:08 08:29 08:42 08:50 08:55 08:58 09:00 | 34 34 21 13 8 5 3 2 |
| 1 | 10 | 08:50 08:54 08:57 08:59 09:00 | 4 3 2 1 |
| 1 | 15 | 08:45 08:49 08:54 08:57 08:59 09:00 | 4 5 3 2 1 |
| 1 | 30 | 08:30 08:41 08:49 08:54 08:57 08:59 09:00 | 11 8 5 3 2 1 |
| 1 | 60 | 08:00 08:28 08:41 08:49 08:54 08:57 08:59 09:00 | 28 13 8 5 3 2 1 |
| 1 | 120 | 07:00 07:33 08:07 08:28 08:41 08:49 08:54 08:57 08:59 09:00 | 33 34 21 13 8 5 3 2 1 |
| 3 | 10 | 08:50 08:57 09:00 | 7 3 |
| 3 | 30 | 08:30 08:44 08:52 08:57 09:00 | 14 8 5 3 |
| 3 | 60 | 08:00 08:31 08:44 08:52 08:57 09:00 | 31 13 8 5 3 |
| 3 | 90 | 07:30 08:10 08:31 08:44 08:52 08:57 09:00 | 40 21 13 8 5 3 |

Crossing midnight: T = 00:20, W = 60, g0 = 2 → 23:20 23:49 00:02 00:10 00:15 00:18 00:20. The first two alarms are on the previous calendar day.

Note: the gaps are "mostly" shrinking. The merge rule can leave the outermost gap a little smaller than the next one (e.g. 33 then 34, or 4 then 5). That's accepted, because the alternative (always merging) creates big jumps like 67 minutes.

### Compared with Arsalan's example
Arsalan's example was 8:00, 8:30, 8:45, 8:50, 8:53, 8:55 … (gaps 30, 15, 5, 3, 2 …). That's the right shape, with the gaps hand-picked rather than strictly Fibonacci. The default above (W = 60, g0 = 2) gives 8:00, 8:29, 8:42, 8:50, 8:55, 8:58, 9:00, which is close. If the round numbers matter (8:30 and 8:45 rather than 8:29 and 8:42), there are two later options: snapping the outer alarms to 5-minute marks, or the fully custom offsets mode that's already a later idea.

## Reference script
Python, used to generate the vectors above. Port the logic 1:1 into Swift and use these tables as the unit tests.

```python
from datetime import datetime, timedelta

def fib_gaps(g0):
    a, b, out = 1, 2, []
    while len(out) < 40:
        if a >= g0 and (not out or a != out[-1]):
            out.append(a)
        a, b = b, a + b
    return out

def fibonacci(T, W, g0=2):
    offs, c, gl = [], 0, None
    for g in fib_gaps(g0):
        if c + g >= W:
            break
        c += g; offs.append(c); gl = g
    if offs and (W - offs[-1]) * 2 < gl:
        offs.pop()
    offs = [0] + offs + [W]
    return sorted(T - timedelta(minutes=o) for o in set(offs))

def fixed(T, N, X, direction):
    before = [T - timedelta(minutes=X * i) for i in range(1, N + 1)] if direction in ("before", "both") else []
    after  = [T + timedelta(minutes=X * i) for i in range(1, N + 1)] if direction in ("after", "both") else []
    return sorted(before + [T] + after)
```
