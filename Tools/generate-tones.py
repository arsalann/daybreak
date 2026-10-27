"""Regenerate Daybreak's original, dependency-free alarm tones.

Design rules (common alarm sound practice):
- Melodic and rhythmic, centred around 500 Hz-3 kHz where the ear is most sensitive.
- A clear repeating pattern of 6-12 s that loops cleanly (AlarmKit repeats the file).
- Starts slightly softer and builds, so the first seconds are not a jolt.
- Peaks normalised just below full scale, so every tone is about equally loud.

Classic: twin bell, digital, buzzer, cuckoo, westminster (public-domain 1793 melody).
Custom: sunrise, morning, glow.
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
ROOT = Path(__file__).resolve().parents[1] / "Daybreak" / "Resources"
TAU = 2 * math.pi


def note(name):
    """'A4' -> Hz. Sharps only."""
    names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    pitch, octave = name[:-1], int(name[-1])
    return 440 * 2 ** ((names.index(pitch) + 12 * (octave + 1) - 69) / 12)


class Track:
    def __init__(self, seconds):
        self.buffer = [0.0] * int(seconds * RATE)

    def add(self, start, seconds, sample):
        """sample(t) is evaluated for local time t in [0, seconds)."""
        offset = int(start * RATE)
        for index in range(min(int(seconds * RATE), len(self.buffer) - offset)):
            self.buffer[offset + index] += sample(index / RATE)


def partials(frequency, spec, attack=0.003):
    """spec: (ratio, level, decay per second)."""
    def sample(t):
        onset = min(t / attack, 1)
        return onset * sum(level * math.exp(-decay * t) * math.sin(TAU * frequency * ratio * t) for ratio, level, decay in spec)
    return sample


def bell(frequency, decay=1.0):
    return partials(frequency, [(0.5, 0.35, 0.6 * decay), (1, 1, 0.9 * decay), (1.19, 0.4, 1.4 * decay), (1.5, 0.25, 1.6 * decay),
                                (2, 0.45, 2 * decay), (2.74, 0.25, 3 * decay), (3.76, 0.12, 4.5 * decay), (5.4, 0.06, 7 * decay)], 0.002)


def marimba(frequency):
    return partials(frequency, [(1, 1, 4.5), (3.93, 0.3, 14), (9.2, 0.06, 40)], 0.002)


def kalimba(frequency):
    return partials(frequency, [(1, 1, 3), (2.01, 0.15, 6), (5.9, 0.12, 18)], 0.001)


def epiano(frequency, length):
    """Two-operator FM: bright attack mellowing into a sine."""
    def sample(t):
        index = 2.2 * math.exp(-t * 5)
        envelope = min(t / 0.004, 1) * math.exp(-t * 1.4) * (1 if t < length - 0.05 else max(0, (length - t) / 0.05))
        return envelope * math.sin(TAU * frequency * t + index * math.sin(TAU * frequency * t))
    return sample


def pad(frequencies, length, level=0.18):
    """Soft detuned chord with slow attack and release."""
    voices = [(frequency * detune, 1 / harmonic, harmonic) for frequency in frequencies for detune in (0.997, 1.003) for harmonic in (1, 2, 3, 4)]
    def sample(t):
        envelope = min(t / 0.6, 1) * min(max(length - t, 0) / 0.6, 1)
        return level * envelope * sum(amp * math.sin(TAU * f * h * t) for f, amp, h in voices) / len(frequencies)
    return sample


def noise_burst(length, level, seed, highpass=True):
    rng = random.Random(seed)
    previous = [0.0]
    def sample(t):
        value = rng.uniform(-1, 1)
        out = value - previous[0] if highpass else value
        previous[0] = value
        return level * out * math.exp(-t / length * 5)
    return sample


def reverb(buffer, mix=0.25, room=0.82):
    """Small Schroeder reverb: four combs and two allpasses."""
    wet = [0.0] * len(buffer)
    for delay in (1557, 1617, 1491, 1422):
        line = [0.0] * delay
        for index, value in enumerate(buffer):
            out = line[index % delay]
            line[index % delay] = value + out * room
            wet[index] += out / 4
    for delay in (225, 556):
        line = [0.0] * delay
        for index, value in enumerate(wet):
            stored = line[index % delay]
            line[index % delay] = value + stored * 0.5
            wet[index] = stored - value * 0.5
    return [(1 - mix) * dry + mix * w for dry, w in zip(buffer, wet)]


def swell(buffer, start=0.55, seconds=4):
    """Build from start level to full volume over the opening seconds."""
    ramp = int(seconds * RATE)
    return [value * (start + (1 - start) * min(index / ramp, 1)) for index, value in enumerate(buffer)]


# ---- Classic -------------------------------------------------------------------------------

def twin_bell():
    """Wind-up clock: a hammer rattling between two small bells."""
    track = Track(8.4)
    for burst in range(3):
        start = burst * 2.8
        strikes = int(2.0 * 18)
        for strike in range(strikes):
            frequency = 2093 if strike % 2 == 0 else 2489
            spec = [(1, 1, 9), (2.76, 0.5, 16), (5.4, 0.25, 30), (8.9, 0.1, 45)]
            track.add(start + strike / 18, 0.5, partials(frequency, spec, 0.0008))
            track.add(start + strike / 18, 0.01, noise_burst(0.01, 0.25, strike))
    return track.buffer


def digital():
    """Four short square-ish beeps, then a pause."""
    track = Track(8.0)
    square = lambda t: sum(math.sin(TAU * 2048 * h * t) / h for h in (1, 3, 5)) * min(t / 0.002, 1) * min(max(0.08 - t, 0) / 0.002, 1)
    for group in range(8):
        for beep in range(4):
            track.add(group * 1.0 + beep * 0.12, 0.08, square)
    return track.buffer


def buzzer():
    """Vintage electric clock buzzer with mechanical rattle."""
    track = Track(8.0)
    def buzz(t):
        rattle = 0.75 + 0.25 * math.sin(TAU * 60 * t)
        envelope = min(t / 0.01, 1) * min(max(0.6 - t, 0) / 0.01, 1)
        return envelope * rattle * sum(math.sin(TAU * 220 * h * t) / h for h in range(1, 14))
    for index in range(8):
        track.add(index * 1.0, 0.6, buzz)
    return track.buffer


def cuckoo():
    """Wooden cuckoo pipes: a falling minor third, repeated."""
    track = Track(8.0)
    def pipe(frequency, length):
        rng = random.Random(int(frequency))
        def sample(t):
            envelope = min(t / 0.03, 1) * min(max(length - t, 0) / 0.06, 1)
            glide = 1 - 0.01 * math.exp(-t * 30)
            return envelope * (math.sin(TAU * frequency * glide * t) + 0.18 * math.sin(TAU * 2 * frequency * t) + 0.012 * rng.uniform(-1, 1))
        return sample
    for call in range(6):
        start = call * 1.3
        track.add(start, 0.28, pipe(note("E5"), 0.28))
        track.add(start + 0.32, 0.5, pipe(note("C#5"), 0.5))
    return reverb(track.buffer, 0.2)


def westminster():
    """The Westminster quarters (public domain) on tower bells."""
    phrases = [["E5", "G#5", "F#5", "B4"], ["E5", "F#5", "G#5", "E5"], ["G#5", "E5", "F#5", "B4"], ["B4", "F#5", "G#5", "E5"]]
    track = Track(12.0)
    time = 0.0
    for phrase in phrases:
        for position, name in enumerate(phrase):
            track.add(time, 3.0, bell(note(name), 0.8))
            time += 0.9 if position == 3 else 0.6
    return reverb(track.buffer, 0.3, 0.86)


# ---- Custom --------------------------------------------------------------------------------

def sunrise():
    """Warm D major pad with an e-piano melody climbing through each chord. Builds over 12 s."""
    chords = [["D4", "F#4", "A4"], ["A3", "C#4", "E4"], ["B3", "D4", "F#4"], ["G3", "B3", "D4"]]
    melody = [["A4", "D5", "F#5", "A5"], ["C#5", "E5", "A5", "C#6"], ["D5", "F#5", "B5", "D6"], ["B5", "D6", "G6", "D6"]]
    track = Track(12.4)
    for bar, (chord, line) in enumerate(zip(chords, melody)):
        start = bar * 3.0
        track.add(start, 3.4, pad([note(n) for n in chord], 3.4))
        track.add(start, 3.0, partials(note(chord[0]) / 2, [(1, 0.5, 0.8)], 0.02))
        for step, name in enumerate(line):
            track.add(start + step * 0.75, 1.5, epiano(note(name), 1.5))
    return swell(reverb(track.buffer, 0.3), 0.35, 10)


def morning():
    """Upbeat marimba groove at 120 bpm: C - Am - F - G, with bass and shaker."""
    bars = [["E5", "G5", "C6", "G5", "E5", "G5", "C6", "D6"], ["E6", "C6", "A5", "C6", "E6", "C6", "A5", "G5"],
            ["F5", "A5", "C6", "A5", "F5", "A5", "C6", "D6"], ["D6", "B5", "G5", "B5", "D6", "E6", "D6", "B5"]]
    bass = ["C3", "A2", "F2", "G2"]
    track = Track(8.2)
    for bar, line in enumerate(bars):
        start = bar * 2.0
        for step, name in enumerate(line):
            track.add(start + step * 0.25, 0.9, marimba(note(name)))
        for beat in (0, 1.0):
            track.add(start + beat, 1.0, marimba(note(bass[bar])))
        for sixteenth in range(16):
            level = 0.08 if sixteenth % 2 else 0.03
            track.add(start + sixteenth * 0.125, 0.05, noise_burst(0.05, level, bar * 16 + sixteenth))
    return swell(reverb(track.buffer, 0.15), 0.6, 3)


def glow():
    """Gentle kalimba arpeggios in G major pentatonic."""
    lines = [["G5", "B5", "D6", "B5", "E6", "D6", "B5", "D6"], ["A5", "C6", "E6", "C6", "G6", "E6", "D6", "C6"],
             ["G5", "B5", "D6", "G6", "E6", "D6", "B5", "A5"], ["D5", "G5", "A5", "B5", "D6", "B5", "A5", "G5"]]
    track = Track(10.0)
    for bar, line in enumerate(lines):
        for step, name in enumerate(line):
            track.add(bar * 2.4 + step * 0.3, 1.5, kalimba(note(name)))
        track.add(bar * 2.4, 2.4, kalimba(note(line[0]) / 4))
    return swell(reverb(track.buffer, 0.3, 0.85), 0.5, 5)


TONES = {
    "twinbell": twin_bell, "digital": digital, "buzzer": buzzer, "cuckoo": cuckoo, "westminster": westminster,
    "sunrise": sunrise, "morning": morning, "glow": glow,
}

if __name__ == "__main__":
    for path in ROOT.glob("*.wav"):
        path.unlink()
    for name, render in TONES.items():
        samples = render()
        peak = max(abs(value) for value in samples) or 1
        frames = b"".join(struct.pack("<h", int(value / peak * 0.89 * 32767)) for value in samples)
        with wave.open(str(ROOT / f"{name}.wav"), "w") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(RATE)
            output.writeframes(frames)
        print(name, f"{len(samples) / RATE:.1f}s")
