"""Synthesizes the touch notification sound: a soft kiss ("mwah"), then a futuristic two-note
FM bell with a shimmering echo. Pure synthesis, no samples. Writes a 16-bit mono WAV."""
import sys
import wave
import numpy as np

RATE = 44100
DUR = 1.6
t = np.arange(int(RATE * DUR)) / RATE
out = np.zeros_like(t)
rng = np.random.default_rng(7)


def env(start, attack, decay, length=None):
    """Exponential decay envelope starting at `start` seconds."""
    e = np.zeros_like(t)
    i0 = int(start * RATE)
    n = len(t) - i0 if length is None else int(length * RATE)
    tt = np.arange(n) / RATE
    a = np.minimum(1, tt / max(attack, 1e-4))
    e[i0:i0 + n] = a * np.exp(-tt / decay)
    return e


# --- Kiss: a little lip "m" hum, then the smack (a fast upward-gliding pop + a crisp click).
k0 = 0.0
hum = np.sin(2 * np.pi * 210 * t) * env(k0, 0.01, 0.035, 0.07) * 0.18
glide_t = np.clip(t - (k0 + 0.055), 0, None)
glide_f = 520 + 2400 * np.minimum(glide_t / 0.035, 1)          # 520 → 2920 Hz in 35 ms
pop = np.sin(2 * np.pi * np.cumsum(glide_f) / RATE) * env(k0 + 0.055, 0.002, 0.022, 0.09) * 0.55
noise = rng.standard_normal(len(t))
# crude band-pass: difference of two smoothed noises (keeps the 1.5–5 kHz "tsk" of lips)
def smooth(x, n):
    return np.convolve(x, np.ones(n) / n, mode="same")
click = (smooth(noise, 4) - smooth(noise, 18)) * env(k0 + 0.058, 0.001, 0.012, 0.05) * 0.9
out += hum + pop + click

# --- Futuristic bell: FM synthesis (inharmonic metallic partials), two notes, a fifth apart.
def fm_bell(start, freq, amp, decay=0.55):
    tt = np.clip(t - start, 0, None)
    e = env(start, 0.003, decay)
    index = 1.7 * np.exp(-tt / 0.14) + 0.3                       # bright strike, then a pure ring
    mod = np.sin(2 * np.pi * freq * 1.4 * tt)
    tone = np.sin(2 * np.pi * freq * tt + index * mod)
    # a slightly detuned twin for a shimmering, chorused, "sci-fi" ring
    twin = np.sin(2 * np.pi * freq * 1.002 * tt + index * 0.6 * mod)
    return (tone + 0.35 * twin) * e * amp

bell = fm_bell(0.16, 1318.5, 0.28) + fm_bell(0.31, 1975.5, 0.22, 0.65)   # E6 then B6
# a soft high sparkle on top
bell += np.sin(2 * np.pi * 3951 * np.clip(t - 0.31, 0, None)) * env(0.31, 0.004, 0.18) * 0.015

# echo taps: the bell repeating quietly, like it's ringing in a large glass room
echoed = bell.copy()
for delay, gain in [(0.12, 0.22), (0.25, 0.09)]:
    d = int(delay * RATE)
    echoed[d:] += bell[:-d] * gain
out += echoed

# take the glassy edge off: a gentle low-pass (3-tap smoothing)
out = np.convolve(out, np.ones(3) / 3, mode="same")
# gentle fade at the very end, normalise to -1 dBFS
out *= np.minimum(1, (DUR - t) / 0.15)
out /= np.max(np.abs(out)) / 0.89
pcm = (out * 32767).astype("<i2").tobytes()

with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(RATE)
    w.writeframes(pcm)
print("wrote", sys.argv[1], f"{DUR}s")
