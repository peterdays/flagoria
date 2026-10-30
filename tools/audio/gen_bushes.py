#!/usr/bin/env python3
"""Generate bush-chopping SFX (original, procedural, deterministic).

Usage: gen_bushes.py OUT_DIR   -> writes OUT_DIR/*.wav (meant for art/audio/sfx/world/bushes)
- bush_hit_01..03: leafy swish plus a light snap of thin twigs (~0.2 s), lighter than tree_chop.
- bush_break_01: crunch of snapping twigs, then leaves rustling as they settle (~0.4 s), no thud.
Mono 16-bit 22.05 kHz, RMS-levelled to about -20 dBFS (same level and format as the tree set).
"""
import os, sys, wave
import numpy as np

SR = 22050


def save(path, x, level_db=-20.0):
    x = x - np.mean(x)
    x = x / np.sqrt(np.mean(x ** 2)) * 10 ** (level_db / 20)
    x *= min(1.0, 0.95 / np.max(np.abs(x)))
    f = int(0.004 * SR); x[:int(0.001 * SR)] *= np.linspace(0, 1, int(0.001 * SR)); x[-f:] *= np.linspace(1, 0, f)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    w = wave.open(path, "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((x * 32767).astype("<i2").tobytes()); w.close()


def bp(x, fc, q):
    """Trapezoidal (zero-delay) state-variable band-pass, stable at any fc; fc may vary per sample."""
    fc = np.broadcast_to(np.asarray(fc, float), x.shape)
    y = np.zeros_like(x); s1 = s2 = 0.0; k = 1.0 / q
    for i in range(len(x)):
        g = np.tan(np.pi * min(fc[i], 0.45 * SR) / SR)
        v1 = (s1 + g * (x[i] - s2)) / (1 + g * (g + k)); v2 = s2 + g * v1
        s1 = 2 * v1 - s1; s2 = 2 * v2 - s2; y[i] = v1
    return y


def modes(dur, partials):
    """Sum of decaying sines: partials = [(freq, amp, decay_s), ...]."""
    t = np.arange(int(dur * SR)) / SR
    return sum(a * np.sin(2 * np.pi * f * t) * np.exp(-t / d) for f, a, d in partials) * np.minimum(t / 0.0008, 1)


def place(n, *parts):
    out = np.zeros(n)
    for start, sig in parts:
        s = int(start * SR); e = min(n, s + len(sig)); out[s:e] += sig[: e - s]
    return out


def soft(x, drive=2.0):
    """Gentle saturation: tames the transient peak so the hit reaches the target level."""
    return np.tanh(drive * x / np.max(np.abs(x)))


def twig(r, fc):
    """One thin twig snap: a very short bright click and a tiny, quickly damped stem resonance."""
    n = int(0.025 * SR); t = np.arange(n) / SR
    click = bp(r.normal(0, 1, n), fc, 2.5) * np.exp(-t / r.uniform(0.0015, 0.003))
    f = r.uniform(900, 1500)
    return click + modes(0.025, [(f, 0.3, 0.005), (f * 2.3, 0.15, 0.003)])


def leaves(r, dur, fc0, fc1, attack, decay, density=260):
    """Leaf swish/rustle: grainy noise through a band-pass gliding fc0 -> fc1."""
    n = int(dur * SR); t = np.arange(n) / SR; g = np.zeros(n)
    for _ in range(int(dur * density)):
        L = int(r.integers(60, 300)); s = int(r.integers(0, n - L))
        g[s:s + L] += r.uniform(0.3, 1) * np.hanning(L)
    env = np.minimum(t / attack, 1) * np.exp(-t / decay)
    return bp(r.normal(0, 1, n) * (0.3 + g), np.linspace(fc0, fc1, n), 1.1) * env


# (leaf band start, end, decay s, twig snap times s)
HITS = [(4200, 2800, 0.06, [0.008, 0.030]),
        (3400, 2300, 0.08, [0.005]),
        (5000, 3300, 0.05, [0.003, 0.016, 0.038])]


def hit(r, i):
    fc0, fc1, decay, snaps = HITS[i - 1]
    n = int(0.2 * SR)
    swish = leaves(r, 0.19, fc0, fc1, 0.010, decay)
    parts = [(t0, r.uniform(0.6, 0.9) * twig(r, r.uniform(3000, 5000))) for t0 in snaps]
    return soft(place(n, (0, swish), *parts))


def brk(r):
    n = int(0.4 * SR); parts = []; tt = 0.0
    for k in range(11):  # crunch: a cluster of twig snaps, thinning out
        parts.append((tt, r.uniform(0.5, 1.0) * twig(r, r.uniform(2500, 5000))))
        tt += r.uniform(0.006, 0.016) * (1 + k / 5)
    crunch = 0.7 * leaves(r, 0.16, 4000, 2800, 0.006, 0.07)
    settle = leaves(r, 0.30, 3600, 2600, 0.05, 0.12, density=180)
    return soft(place(n, (0, crunch), *parts, (0.08, 0.8 * settle)), 1.8)


def main(out):
    r = np.random.default_rng(2067)
    for i in range(1, 4):
        save(f"{out}/bush_hit_{i:02d}.wav", hit(r, i))
    save(f"{out}/bush_break_01.wav", brk(r))


if __name__ == "__main__":
    main(sys.argv[1])
