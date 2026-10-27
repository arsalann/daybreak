"""Regenerate Daybreak's original, dependency-free alarm tones."""
import math
import random
import struct
import wave
from pathlib import Path

root = Path(__file__).resolve().parents[1] / "Daybreak" / "Resources"
rate = 22050
length = 5.0


def tone(frequency, time, harmonics=(1, 0.2)):
    return sum(level * math.sin(2 * math.pi * frequency * (n + 1) * time) for n, level in enumerate(harmonics))


def notes(frequencies, step=0.6, decay=5, harmonics=(1, 0.2), swell=False):
    def sample(time):
        note = int(time / step)
        local = time % step
        envelope = min(local / 0.015, 1) * math.exp(-local * decay) if time < length - 0.2 else 0
        if swell:
            envelope *= 0.35 + 0.65 * time / length
        return envelope * tone(frequencies[note % len(frequencies)], time, harmonics) / sum(harmonics)
    return sample


def beeps(frequency, pattern):
    """pattern: on/off durations in seconds, repeated."""
    period = sum(pattern)
    def sample(time):
        local, on = time % period, False
        for index, duration in enumerate(pattern):
            if local < duration:
                on = index % 2 == 0
                break
            local -= duration
        return (0.8 if on else 0) * math.copysign(1, math.sin(2 * math.pi * frequency * time)) * 0.35
    return sample


def birds():
    rng = random.Random(7)
    chirps = [(rng.uniform(0, length - 0.4), rng.uniform(2400, 3600), rng.uniform(0.06, 0.14)) for _ in range(22)]
    def sample(time):
        value = 0
        for start, base, duration in chirps:
            local = time - start
            if 0 <= local < duration:
                frequency = base + 1800 * local / duration
                value += math.sin(math.pi * local / duration) * math.sin(2 * math.pi * frequency * local)
        return value * 0.6
    return sample


def ocean():
    rng = random.Random(3)
    state = [0.0]
    def sample(time):
        state[0] = 0.995 * state[0] + 0.05 * rng.uniform(-1, 1)
        wave_level = 0.5 - 0.5 * math.cos(2 * math.pi * time / 2.5)
        return state[0] * wave_level * 2 + 0.25 * wave_level * math.sin(2 * math.pi * 392 * time)
    return sample


tones = {
    "daybreak": notes([523.25, 659.25, 783.99]),
    "chime": notes([880, 1108.73, 1318.51]),
    "pulse": notes([440, 440, 660, 660]),
    "bells": notes([1046.5, 783.99, 880, 659.25], step=0.8, decay=2.2, harmonics=(1, 0.5, 0.25, 0.12)),
    "marimba": notes([523.25, 587.33, 659.25, 783.99, 880, 783.99, 659.25, 587.33], step=0.3, decay=9, harmonics=(1, 0.05, 0.3)),
    "sunrise": notes([261.63, 329.63, 392, 523.25, 659.25, 783.99, 1046.5], step=0.45, decay=3, swell=True),
    "harp": notes([392, 493.88, 587.33, 783.99, 987.77, 1174.66], step=0.18, decay=4, harmonics=(1, 0.3, 0.1)),
    "classic": beeps(1000, [0.12, 0.08, 0.12, 0.08, 0.12, 0.08, 0.12, 0.6]),
    "beacon": beeps(1400, [0.5, 0.5]),
    "birdsong": birds(),
    "ocean": ocean(),
}

for name, sample in tones.items():
    frames = []
    for index in range(int(rate * length)):
        value = max(-1, min(1, 0.38 * sample(index / rate)))
        frames.append(struct.pack("<h", int(value * 32767)))
    with wave.open(str(root / f"{name}.wav"), "w") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes(b"".join(frames))
