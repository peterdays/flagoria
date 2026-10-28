#!/usr/bin/env python3
"""Generate tree-chopping SFX (original, procedural, deterministic).

Usage: gen_trees.py OUT_DIR   -> writes OUT_DIR/*.wav (meant for art/audio/sfx/world/trees)
- tree_chop_01..03: dry woody axe 'tok' with a short body resonance (< 0.25 s).
- tree_crack_01: splintering crack plus a short creak (~0.5 s).
- tree_fall_01: leafy rustle and a soft thud (~0.7 s).
- wood_pickup_01..02: light hollow wooden 'clonk' pair (~0.2 s).
- leaf_rustle_01: tiny leaf shake to layer on chops (~0.25 s, about 6 dB quieter).
Mono 16-bit 22.05 kHz, RMS-levelled to about -20 dBFS (rustle about -26 dBFS).
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
    """State-variable band-pass; fc may be a scalar or a per-sample array."""
    fc = np.broadcast_to(np.asarray(fc, float), x.shape)
    y = np.zeros_like(x); lo = bd = 0.0; damp = 1.0 / q
    for i in range(len(x)):
        f = 2 * np.sin(np.pi * min(fc[i], SR / 6) / SR)
        lo += f * bd; hp = x[i] - lo - damp * bd; bd += f * hp; y[i] = bd
    return y


def lp(x, fc):
    a = np.exp(-2 * np.pi * fc / SR); y = np.zeros_like(x); s = 0.0
    for i in range(len(x)):
        s = (1 - a) * x[i] + a * s; y[i] = s
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


def burst(r, dur, fc, q, decay):
    n = int(dur * SR); t = np.arange(n) / SR
    return bp(r.normal(0, 1, n), fc, q) * np.exp(-t / decay)


def rustle(r, dur, swell=0.3, grains=60):
    n = int(dur * SR); t = np.arange(n) / SR; g = np.zeros(n)
    for _ in range(grains):
        L = int(r.integers(80, 400)); s = int(r.integers(0, n - L))
        g[s:s + L] += r.uniform(0.3, 1) * np.hanning(L)
    shape = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** swell
    return bp(r.normal(0, 1, n) * (0.25 + g), 4500, 0.8) * shape


def soft(x, drive=2.5):
    """Gentle saturation: tames the transient peak so the hit reaches the target level."""
    return np.tanh(drive * x / np.max(np.abs(x)))


def chop(r, i):
    body = [180, 205, 165][i - 1] * r.uniform(0.98, 1.02)
    dur = 0.2
    hit = burst(r, dur, [2200, 1800, 2600][i - 1], 2.0, 0.006)
    res = modes(dur, [(body, 1.0, 0.035), (body * 2.6, 0.5, 0.022), (body * 5.4, 0.25, 0.012)])
    return soft(1.4 * hit + res)


def crack(r):
    n = int(0.5 * SR); parts = []
    tt = 0.0
    for k in range(14):  # splinters, accelerating then thinning
        parts.append((tt, r.uniform(0.4, 1.0) * burst(r, 0.03, r.uniform(1500, 4500), 3, r.uniform(0.002, 0.006))))
        tt += r.uniform(0.004, 0.018) * (1 + k / 6)
    snap = 1.8 * burst(r, 0.08, 1600, 1.5, 0.012) + modes(0.08, [(150, 0.8, 0.03)])
    # creak: irregular friction pulses through a gliding woody resonance
    cn = int(0.24 * SR); ct = np.arange(cn) / SR
    rate = 55 + 25 * np.sin(2 * np.pi * 3 * ct) + r.normal(0, 4, cn)
    pulses = (np.diff(np.floor(np.cumsum(rate) / SR), prepend=0) > 0).astype(float)
    creak = bp(pulses + 0.05 * r.normal(0, 1, cn), 700 + 250 * ct / ct[-1], 8) * np.sin(np.pi * ct / ct[-1])
    return soft(place(n, (0, snap), *parts, (0.24, 1.5 * creak)), 2.0)


def fall(r):
    n = int(0.7 * SR); t = np.arange(n) / SR
    leaves = rustle(r, 0.52, swell=0.6, grains=110)
    th = int(0.24 * SR); tt = np.arange(th) / SR
    thud = np.sin(2 * np.pi * np.cumsum(75 * (0.6 + 0.4 * np.exp(-tt / 0.04))) / SR) * np.exp(-tt / 0.07)
    thud += 0.6 * lp(r.normal(0, 1, th), 400) * np.exp(-tt / 0.04)
    settle = rustle(r, 0.2, swell=1, grains=20)
    return place(n, (0, leaves), (0.44, 2.2 * thud), (0.46, 0.4 * settle))


def clonk(f, dur=0.12):
    # wood-block style partial ratios (1 : 2.57 : 4.9), short and hollow, low and dry unlike a coin
    return modes(dur, [(f, 1.0, 0.03), (f * 2.57, 0.35, 0.012), (f * 4.9, 0.12, 0.006)])


def pickup(i):
    f = [420.0, 500.0][i - 1]
    n = int(0.2 * SR)
    return place(n, (0, clonk(f)), (0.07, 0.9 * clonk(f * 1.5)))


def main(out):
    r = np.random.default_rng(2026)
    for i in range(1, 4):
        save(f"{out}/tree_chop_{i:02d}.wav", chop(r, i))
    save(f"{out}/tree_crack_01.wav", crack(r))
    save(f"{out}/tree_fall_01.wav", fall(r))
    for i in range(1, 3):
        save(f"{out}/wood_pickup_{i:02d}.wav", pickup(i))
    save(f"{out}/leaf_rustle_01.wav", rustle(r, 0.25, swell=0.8, grains=40), -26.0)


if __name__ == "__main__":
    main(sys.argv[1])
