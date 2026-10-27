"""Regenerate Daybreak's original, dependency-free alarm tones."""
import math
import struct
import wave
from pathlib import Path

root = Path(__file__).resolve().parents[1] / "Daybreak" / "Resources"
for name, frequencies in [
    ("daybreak", [523.25, 659.25, 783.99]),
    ("chime", [880, 1108.73, 1318.51]),
    ("pulse", [440, 440, 660, 660]),
]:
    rate = 22050
    samples = []
    for index in range(rate * 5):
        time = index / rate
        note = int(time / 0.6)
        local = time % 0.6
        envelope = min(local / 0.015, 1) * math.exp(-local * 5) if time < 4.8 else 0
        frequency = frequencies[note % len(frequencies)]
        value = 0.38 * envelope * (
            math.sin(2 * math.pi * frequency * time)
            + 0.2 * math.sin(2 * math.pi * frequency * 2 * time)
        ) / 1.2
        samples.append(struct.pack("<h", int(value * 32767)))
    with wave.open(str(root / f"{name}.wav"), "w") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes(b"".join(samples))
