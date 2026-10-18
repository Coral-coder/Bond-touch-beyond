"""Synthesizes the touch notification sound: a soft kiss (a short, breathy lip smack — no
tone, so it doesn't sound like a bubble), then a warm, low, gentle chime. Pure synthesis, no
samples. Three variants:
  warm    — two soft bell notes an octave lower (C5, G5), slow attack, mostly fundamental
  marimba — two rounded wooden-bar notes (E5, B5), very short and soft
  glow    — a soft three-note major chord swelling in and out, like a warm pad
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


def glow(t, start, freqs, amp, length=1.1):
    tt = np.clip(t - start, 0, None)
    swell = np.where(tt < length, np.sin(np.pi * np.clip(tt / length, 0, 1)) ** 1.5, 0) * (t >= start)
    tone = sum(np.sin(2 * np.pi * f * tt) * (0.8 ** i) for i, f in enumerate(freqs))
    return tone * swell * amp


def make(variant):
    t = timeline(1.5)
    out = kiss(t)
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
        t = timeline(0.18)
        write(path, kiss(t) * np.minimum(1, (0.18 - t) / 0.04))
    else:
        write(path, make(variant))
    print("wrote", path, variant)
