"""Deterministic original PCM cues, with three fierce impact takes per type."""
from pathlib import Path
import math
import random
import struct
import wave

RATE = 44100
DESTINATION = Path(__file__).resolve().parents[1] / "assets/audio/feedback"
TAU = math.tau


def bell(t, frequency, decay):
    if t < 0:
        return 0.0
    attack = min(1.0, t / 0.007)
    return attack * math.exp(-t / decay) * (
        math.sin(TAU * frequency * t)
        + 0.26 * math.sin(TAU * frequency * 2.003 * t) * math.exp(-t * 6)
        + 0.10 * math.sin(TAU * frequency * 3.997 * t) * math.exp(-t * 10)
    )


def synthesize(cue, variant=0):
    duration = {"create": 1.7, "stroke": 0.16, "grip": 0.27,
                "swing": 0.22, "hit": 0.26, "break": 0.65, "hurt": 0.29,
                "clash": 0.62, "draw_bow": 0.42, "shoot": 0.24}[cue]
    rng = random.Random(cue if variant == 0 else f"{cue}-{variant}")
    tuning = [1.0, 1.16, .87][variant]
    samples = []
    low_noise = 0.0
    for index in range(int(RATE * duration)):
        t = index / RATE
        noise = rng.uniform(-1, 1)
        low_noise = low_noise * 0.86 + noise * 0.14
        airy = noise - low_noise
        envelope = min(1, t / 0.008) * max(0, 1 - t / duration) ** 2
        if cue == "create":
            # D-major bell arpeggio, a warm root and a quiet rising air layer.
            signal = sum(0.16 * bell(t - delay, hz, 0.38)
                         for hz, delay in [(587.33, 0), (880, .045), (1174.66, .09), (1479.98, .145), (1760, .21)])
            signal += 0.13 * bell(t, 146.83, .16)
            signal += airy * .035 * math.sin(math.pi * min(t / .5, 1)) * math.exp(-t * 5)
            for delay in [.22, .39]:
                signal += .035 * bell(t - delay, 1174.66, .28)
        elif cue in ("stroke", "grip"):
            signal = .38 * bell(t, 1174.66 if cue == "stroke" else 1479.98, .045 if cue == "stroke" else .09)
            if cue == "grip":
                signal += .14 * bell(t - .035, 1760, .08)
        elif cue == "swing":
            signal = (low_noise * 1.6 + airy * .08) * math.sin(math.pi * t / duration) ** 2
            signal += .12 * math.sin(TAU * (330 * t - 250 * t * t)) * envelope
        elif cue == "clash":
            signal = .65 * low_noise * math.exp(-t * 65)
            signal += .4 * math.sin(TAU * (120 * t - 90 * t * t)) * math.exp(-t * 35)
            signal += sum(g * bell(t, hz, decay) for hz, g, decay in
                          [(1780, .23, .12), (2873, .17, .19), (4219, .10, .09), (6031, .06, .06)])
        elif cue == "draw_bow":
            signal = .10 * math.sin(TAU * (145 * t + 240 * t * t)) * envelope
            signal += .25 * low_noise * envelope * (.5 + .5 * math.sin(t * 85))
        elif cue == "shoot":
            signal = .45 * math.sin(TAU * (680 * t - 1100 * t * t)) * math.exp(-t * 35)
            signal += airy * .18 * envelope + low_noise * .7 * math.exp(-t * 26)
        elif cue == "hit":
            # Fast downward cut, hard crack and a saturated low punch.
            body = math.sin(TAU * tuning * (145 * t - 180 * t * t))
            signal = .44 * math.tanh(body * 2.3) * math.exp(-t * 32)
            signal += (airy * .62 + low_noise * 1.5) * math.exp(-t * (100 + variant * 12))
            signal += .18 * math.sin(TAU * tuning * (1500 * t - 6200 * t * t)) * math.exp(-t * 110)
        elif cue == "break":
            # Heavy overdriven impact and a dry shattering tail, without bells.
            signal = .49 * math.tanh(2.5 * math.sin(TAU * tuning * (97 * t - 65 * t * t))) * math.exp(-t * 18)
            signal += low_noise * 1.2 * math.exp(-t * 20)
            signal += airy * .7 * math.exp(-t * 90)
            for offset, strength in [(0, .24), (.045, .18), (.095, .12), (.16, .07)]:
                elapsed = t - offset
                if elapsed >= 0:
                    signal += (airy * (.8 + variant * .2) + low_noise) * strength * math.exp(-elapsed * 42)
        else:
            # A lower body slam with a sharp initial edge and a gritty low tail.
            signal = .48 * math.tanh(2.2 * math.sin(TAU * tuning * (88 * t - 65 * t * t))) * math.exp(-t * 23)
            signal += low_noise * 1.15 * math.exp(-t * 25)
            signal += airy * .48 * math.exp(-t * (105 - variant * 10))
        # Fade both boundaries to avoid a click, retain relative cue dynamics.
        attack = .0007 if cue in ("hit", "hurt", "break") else .004
        signal *= min(1, t / attack) * min(1, (duration - t) / .025)
        samples.append(signal)
    peak = max(abs(sample) for sample in samples) or 1
    gain = min(1.8, .72 / peak)
    suffix = f"_{variant + 1}" if variant else ""
    with wave.open(str(DESTINATION / f"{cue}{suffix}.wav"), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(b"".join(struct.pack("<h", round(max(-1, min(1, s * gain)) * 32767)) for s in samples))


if __name__ == "__main__":
    DESTINATION.mkdir(parents=True, exist_ok=True)
    for cue_name in ["create", "stroke", "grip", "swing", "hit", "break", "hurt", "clash", "draw_bow", "shoot"]:
        synthesize(cue_name)
        if cue_name in ("hit", "hurt", "break"):
            for variant in (1, 2): synthesize(cue_name, variant)
    print(f"Generated 16 feedback samples in {DESTINATION}")
