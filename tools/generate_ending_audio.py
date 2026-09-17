"""Reproducible original PCM for the final observation; no external samples."""
from pathlib import Path
import math
import random
import struct
import wave

ROOT = Path(__file__).resolve().parents[1] / 'resources' / 'audio'
RATE = 22050


def write(name, duration, sample):
    rng = random.Random(941)
    data = bytearray()
    low = 0.0
    for i in range(round(RATE * duration)):
        t = i / RATE
        low = low * 0.985 + rng.uniform(-1, 1) * 0.015
        value = sample(t, low)
        for channel in range(2):
            side = value + math.sin(2 * math.pi * 73 * t + channel * 0.25) * 0.008
            data.extend(struct.pack('<h', round(max(-0.95, min(0.95, side)) * 32767)))
    with wave.open(str(ROOT / name), 'wb') as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(data)


def drone(t, low):
    # Integer cycles in the 12-second loop, with a breathing, subdued fifth.
    tones = sum(math.sin(2 * math.pi * f * t) * a for f, a in
                [(36, .26), (54, .12), (72, .08), (85.0, .025), (108, .025)])
    return tones * (0.78 + 0.14 * math.sin(2 * math.pi * t / 12)) + low * 0.06 * math.sin(math.pi * t / 12)**2


def rupture(t, low):
    envelope = min(1, t / 5) * max(0, 1 - t / 36)**0.8
    phase = 2 * math.pi * (47 * t - 0.20 * t * t)
    body = math.sin(phase) * .30 + math.sin(phase * 1.5) * .08
    shimmer = math.sin(2 * math.pi * 147 * t) * .035 + math.sin(2 * math.pi * 220 * t) * .025
    return envelope * (body + shimmer + low * .7)


if __name__ == '__main__':
    ROOT.mkdir(parents=True, exist_ok=True)
    write('ending_drone.wav', 12, drone)
    write('ending_rupture.wav', 36, rupture)
    print('ENDING_AUDIO_GENERATED: stereo 22050Hz, 12s loop and 36s swell')
