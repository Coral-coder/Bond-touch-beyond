"""Synthesizes the touch notification sound: a soft kiss ("mwah"), then a soft two-note
glass bell (pure sine partials) with a light echo. Pure synthesis, no samples. Writes a 16-bit mono WAV."""
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


# --- Kiss: a soft, rounded "mwah" — a warm lip hum, a gentle pop that glides up only a
# little, and a muffled breath instead of a crisp click (the crisp version sounded sharp).
k0 = 0.0
def smooth(x, n):
    return np.convolve(x, np.ones(n) / n, mode="same")
hum = (np.sin(2 * np.pi * 190 * t) + 0.3 * np.sin(2 * np.pi * 380 * t)) * env(k0, 0.015, 0.045, 0.09) * 0.16
glide_t = np.clip(t - (k0 + 0.06), 0, None)
glide_f = 480 + 900 * np.minimum(glide_t / 0.05, 1)               # 480 → 1380 Hz over 50 ms
pop = np.sin(2 * np.pi * np.cumsum(glide_f) / RATE) * env(k0 + 0.06, 0.008, 0.03, 0.11) * 0.42
noise = rng.standard_normal(len(t))
# a soft breath: noise low-passed to below ~2 kHz, with a gentle swell
breath = (smooth(noise, 14) - smooth(noise, 60)) * env(k0 + 0.062, 0.006, 0.02, 0.07) * 0.5
out += hum + pop + breath

# --- Soft futuristic bell: pure sine partials (no FM — FM's dense overtones sounded like a
# harsh saw wave), tuned like a glass bell / vibraphone: a warm fundamental, a gentle octave,
# and two inharmonic partials that fade fast, so it shimmers for a moment and then rings pure.
def soft_bell(start, freq, amp, decay=0.7):
    tt = np.clip(t - start, 0, None)
    tone = np.zeros_like(t)
    for ratio, gain, dec in [(1.0, 1.0, decay), (2.0, 0.28, decay * 0.55),
                             (2.76, 0.10, decay * 0.25), (5.40, 0.03, decay * 0.12)]:
        tone += gain * np.sin(2 * np.pi * freq * ratio * tt) * env(start, 0.006, dec)
    # a slow, slight vibrato on the fundamental for a "sci-fi" float
    tone += 0.12 * np.sin(2 * np.pi * freq * tt * (1 + 0.003 * np.sin(2 * np.pi * 5 * tt))) * env(start, 0.02, decay)
    return tone * amp

bell = soft_bell(0.16, 1046.5, 0.30) + soft_bell(0.32, 1568.0, 0.22, 0.85)   # C6 then G6
# echo taps: the bell repeating quietly, like it's ringing in a large glass room
echoed = bell.copy()
for delay, gain in [(0.13, 0.16), (0.27, 0.06)]:
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
