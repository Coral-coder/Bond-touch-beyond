"""Synthesizes the touch notification sound: a soft kiss (a short, breathy lip smack — no
tone, so it doesn't sound like a bubble), then a warm, low, gentle chime. Pure synthesis, no
samples. Three variants:
  warm    — two soft bell notes an octave lower (C5, G5), slow attack, mostly fundamental
  marimba — two rounded wooden-bar notes (E5, B5), very short and soft
  glow    — a soft three-note major chord swelling in and out, like a warm pad
  mallet  — between bell and marimba: soft mallet notes (E5, B5) with a smooth reverb tail
  glow2   — glow, with a 35 ms breath after the kiss and a touch of reverb on the kiss;
            glow2:<chord> picks another chord from CHORDS (e.g. glow2:maj7)
  chamber — nearly pure sine chimes (E5, B5) and a soft kiss, in a small room, with an echo
Writes 16-bit mono WAVs: make_touch_chime.py <out.wav> [variant] [--kiss-only]"""
import sys
import wave
import numpy as np

RATE = 44100
rng = np.random.default_rng(7)


def write(path, out):
    out = out / (np.max(np.abs(out)) / 0.85)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((out * 32767).astype("<i2").tobytes())


def timeline(dur):
    return np.arange(int(RATE * dur)) / RATE


def env(t, start, attack, decay, length=None):
    e = np.zeros_like(t)
    i0 = int(start * RATE)
    n = len(t) - i0 if length is None else min(int(length * RATE), len(t) - i0)
    tt = np.arange(n) / RATE
    e[i0:i0 + n] = np.minimum(1, tt / max(attack, 1e-4)) * np.exp(-tt / decay)
    return e


def lowpass(x, n):
    return np.convolve(x, np.ones(n) / n, mode="same")


def kiss(t, at=0.0):
    """A soft lip smack: a breathy 'm' then two tiny muffled smacks of filtered noise."""
    noise = rng.standard_normal(len(t))
    breath = lowpass(noise, 24) * env(t, at, 0.02, 0.04, 0.08) * 0.10          # soft "m" breath
    band = lowpass(noise, 6) - lowpass(noise, 40)                              # ~1–4 kHz, no hiss
    smack = band * (env(t, at + 0.055, 0.002, 0.010, 0.04) + 0.55 * env(t, at + 0.072, 0.002, 0.008, 0.03))
    return lowpass(breath + smack * 0.9, 3)


def bell(t, start, freq, amp, decay):
    """A warm bell: mostly fundamental, a little octave, a faint quickly-fading metallic partial."""
    tt = np.clip(t - start, 0, None)
    tone = (1.0 * np.sin(2 * np.pi * freq * tt) * env(t, start, 0.012, decay)
            + 0.15 * np.sin(2 * np.pi * freq * 2 * tt) * env(t, start, 0.012, decay * 0.5)
            + 0.03 * np.sin(2 * np.pi * freq * 2.76 * tt) * env(t, start, 0.008, decay * 0.18))
    return tone * amp


def marimba(t, start, freq, amp):
    tt = np.clip(t - start, 0, None)
    tone = (np.sin(2 * np.pi * freq * tt) * env(t, start, 0.004, 0.22)
            + 0.25 * np.sin(2 * np.pi * freq * 4 * tt) * env(t, start, 0.002, 0.03))
    return tone * amp


def soft_mallet(t, start, freq, amp, decay=0.5):
    """Between a bell and a marimba: a rounded mallet strike that blooms into a smooth tone —
    mostly fundamental, a gentle octave, and only a faint, fast woody overtone."""
    tt = np.clip(t - start, 0, None)
    tone = (1.0 * np.sin(2 * np.pi * freq * tt) * env(t, start, 0.008, decay)
            + 0.12 * np.sin(2 * np.pi * freq * 2 * tt) * env(t, start, 0.006, decay * 0.45)
            + 0.06 * np.sin(2 * np.pi * freq * 4 * tt) * env(t, start, 0.003, 0.035))
    return tone * amp


def reverb(x, seconds=1.1, wet=0.32):
    """A smooth, warm reverb: the sound convolved with a soft, exponentially decaying,
    low-passed noise tail (no metallic ringing)."""
    n = int(seconds * RATE)
    tt = np.arange(n) / RATE
    ir = lowpass(rng.standard_normal(n), 10) * np.exp(-tt / (seconds / 4.5))
    ir[: int(0.012 * RATE)] *= np.linspace(0, 1, int(0.012 * RATE))      # a short pre-delay swell
    ir /= np.sqrt(np.sum(ir ** 2))
    tail = np.convolve(x, ir)[: len(x)]
    return (1 - wet) * x + wet * tail * (np.max(np.abs(x)) / max(np.max(np.abs(tail)), 1e-9))


def sine_chime(t, start, freq, amp, decay=0.6):
    """A nearly pure sine chime (overtones made it sound square): the fundamental with a
    whisper of octave, swelling in over 18 ms so there's no hard edge."""
    tt = np.clip(t - start, 0, None)
    tone = (np.sin(2 * np.pi * freq * tt) * env(t, start, 0.018, decay)
            + 0.04 * np.sin(2 * np.pi * freq * 2 * tt) * env(t, start, 0.018, decay * 0.4))
    return tone * amp


def chamber(x, delays=(0.017, 0.029, 0.041, 0.056, 0.071), gains=(0.42, 0.33, 0.26, 0.19, 0.13)):
    """A small room: a cluster of early reflections off near walls (each a little duller),
    then a short soft diffuse tail."""
    out = x.copy()
    for d, g in zip(delays, gains):
        n = int(d * RATE)
        out[n:] += lowpass(x, 6)[:-n] * g
    return reverb(out, seconds=0.6, wet=0.22)


def echo(x, delays=(0.23, 0.46), gains=(0.30, 0.12)):
    """The whole sound coming back, softer and duller each time."""
    out = x.copy()
    for d, g in zip(delays, gains):
        n = int(d * RATE)
        out[n:] += lowpass(x, 10)[:-n] * g
    return out


def glow(t, start, freqs, amp, length=1.1):
    tt = np.clip(t - start, 0, None)
    swell = np.where(tt < length, np.sin(np.pi * np.clip(tt / length, 0, 1)) ** 1.5, 0) * (t >= start)
    tone = sum(np.sin(2 * np.pi * f * tt) * (0.8 ** i) for i, f in enumerate(freqs))
    return tone * swell * amp


# Chords for the glow chime (Hz). "roll" ones strum the notes in one after another.
CHORDS = {
    "major":   ([523.3, 659.3, 784.0], 0),            # C major (the original glow)
    "maj7":    ([523.3, 659.3, 784.0, 987.8], 0),     # C major 7 — dreamy, soft
    "sus2":    ([440.0, 493.9, 659.3], 0),            # A sus2 — open, floating, no major/minor
    "min9":    ([293.7, 349.2, 440.0, 523.3, 659.3], 0),  # D minor 9 — warm, a little wistful
    "fifths":  ([392.0, 587.3, 880.0], 0),            # G–D–A stacked fifths — airy, futuristic
    "add9":    ([659.3, 830.6, 987.8, 1480.0], 0),    # E add9 — bright, sparkly
    "maj7roll": ([523.3, 659.3, 784.0, 987.8], 0.06), # C major 7, strummed up (60 ms apart)
    "sus2roll": ([440.0, 493.9, 659.3, 987.8], 0.07), # A sus2, strummed up — like a harp
}


def kiss_alone():
    """The kiss on its own (the kiss button's sound) — always the same noise."""
    global rng
    rng = np.random.default_rng(7)
    t = timeline(0.18)
    return kiss(t) * np.minimum(1, (0.18 - t) / 0.04)


def make(variant):
    t = timeline(1.5)
    out = kiss(t)
    if variant.startswith("glow2"):
        # the glow chord, 35 ms later than before (a breath between kiss and chime), and the
        # kiss with a teeny bit of short reverb
        t = timeline(1.6)
        k = np.zeros_like(t)
        k[: len(kiss_alone())] = kiss_alone()
        k = reverb(k, seconds=0.35, wet=0.14)
        freqs, roll = CHORDS[variant.split(":")[1] if ":" in variant else "major"]
        chord = sum(glow(t, 0.175 + i * roll, [f], 0.16 * 0.8 ** i, 1.1 - i * roll) for i, f in enumerate(freqs))
        chord *= 0.16 * 1.4 / max(np.max(np.abs(chord)), 1e-9) * (1 + 0.15 * (len(freqs) - 3))
        out = lowpass(k + chord, 3)
        out *= np.minimum(1, (1.6 - t) / 0.12)
        return out
    if variant == "chamber":
        t = timeline(2.6)
        dry = sine_chime(t, 0.17, 659.3, 0.34, 0.6) + sine_chime(t, 0.34, 987.8, 0.27, 0.7)
        k = lowpass(kiss_alone(), 5)                       # softer: duller, and quieter below
        dry[: len(k)] += k * (np.max(np.abs(dry)) / np.max(np.abs(k))) * 0.38
        out = echo(chamber(dry))
        out *= np.minimum(1, (2.6 - t) / 0.25)
        return out
    if variant == "mallet":
        t = timeline(2.2)
        out = soft_mallet(t, 0.17, 659.3, 0.34, 0.55) + soft_mallet(t, 0.34, 987.8, 0.27, 0.65)
        out = reverb(lowpass(out, 4))
        out *= np.minimum(1, (2.2 - t) / 0.2)
        # the approved kiss (exactly the --kiss-only one), a little under the chime, in front
        k = kiss_alone()
        out[: len(k)] += k * (np.max(np.abs(out)) / np.max(np.abs(k))) * 0.55
        return out
    if variant == "marimba":
        out += marimba(t, 0.16, 659.3, 0.35) + marimba(t, 0.30, 987.8, 0.28)
    elif variant == "glow":
        out += glow(t, 0.14, [523.3, 659.3, 784.0], 0.16)
    else:
        out += bell(t, 0.16, 523.3, 0.34, 0.75) + bell(t, 0.33, 784.0, 0.26, 0.9)
    out = lowpass(out, 3)
    out *= np.minimum(1, (1.5 - t) / 0.12)
    return out


if __name__ == "__main__":
    path = sys.argv[1]
    variant = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith("--") else "warm"
    if "--kiss-only" in sys.argv:
        write(path, kiss_alone())
    else:
        write(path, make(variant))
    print("wrote", path, variant)
