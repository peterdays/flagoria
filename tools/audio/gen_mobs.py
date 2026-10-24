#!/usr/bin/env python3
"""Generate original mob SFX for slime, crab and piglet (procedural, deterministic).

Usage: gen_mobs.py OUT_DIR   -> writes OUT_DIR/<mob>/<mob>_<type>_NN.wav
Mono 16-bit 22.05 kHz, RMS-levelled to about -20 dBFS (idle about -26 dBFS).
Slime: wet, bouncy bloops. Crab: dry chitin clicks and snaps. Piglet: snorts, oinks, squeals.
"""
import os, sys, wave
import numpy as np

SR = 22050


def t_(dur):
    return np.arange(int(dur * SR)) / SR


def env(n, a, d, start=0.0):
    t = np.arange(n) / SR - start
    e = np.where(t < 0, 0.0, np.minimum(np.maximum(t, 0) / a, 1) * np.exp(-np.maximum(t, 0) / d))
    return e


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


def sweep(f, amp=1.0):
    """Sine with per-sample frequency array f."""
    return amp * np.sin(2 * np.pi * np.cumsum(f) / SR)


def saw(f):
    ph = np.cumsum(f) / SR
    return 2 * (ph % 1.0) - 1


def place(n, *parts):
    out = np.zeros(n)
    for start, sig in parts:
        s = int(start * SR); e = min(n, s + len(sig)); out[s:e] += sig[: e - s]
    return out


def save(path, x, level_db=-20.0):
    x = x - np.mean(x)
    x = x / np.sqrt(np.mean(x ** 2)) * 10 ** (level_db / 20)
    x *= min(1.0, 0.95 / np.max(np.abs(x)))
    f = int(0.004 * SR); x[:f] *= np.linspace(0, 1, f); x[-f:] *= np.linspace(1, 0, f)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    w = wave.open(path, "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((x * 32767).astype("<i2").tobytes()); w.close()


def puff(r, dur=0.3):
    """Soft airy whoosh shared by every death (the fx_puff sprite)."""
    n = int(dur * SR); t = np.arange(n) / SR
    return bp(r.normal(0, 1, n), 900 + 1500 * (1 - t / t[-1]), 1.2) * env(n, 0.02, 0.09)


# ---------- slime: wet, bouncy ----------
def bloop(r, f0, f1, dur, wet=0.4):
    t = t_(dur); f = f0 * (f1 / f0) ** (t / t[-1])
    s = sweep(f) * env(len(t), 0.004, dur / 3)
    s += wet * lp(r.normal(0, 1, len(t)), 900) * env(len(t), 0.002, dur / 5)
    return s


def slime(r, kind, i):
    if kind == "notice":
        return place(int(0.36 * SR), (0, bloop(r, 220, 420, 0.13)), (0.14, bloop(r, 300, 620, 0.18)))
    if kind == "attack":
        n = int(0.32 * SR)
        splat = lp(r.normal(0, 1, n), 1400 + 300 * i) * env(n, 0.003, 0.05, 0.1)
        return place(n, (0, bloop(r, 520 + 40 * i, 160, 0.12 + 0.02 * i))) + 0.9 * splat
    if kind == "hurt":
        n = int(0.3 * SR); t = np.arange(n) / SR
        f = (500 + 70 * i) * (1 + 0.25 * np.sin(2 * np.pi * (18 + 4 * i) * t)) * (1 - 0.5 * t / t[-1])
        return sweep(f) * env(n, 0.003, 0.09) + 0.5 * bp(r.normal(0, 1, n), 1200, 2) * env(n, 0.002, 0.05)
    if kind == "death":
        n = int(0.5 * SR)
        pop = bloop(r, 300, 1400, 0.08, wet=0.2)
        burst = lp(r.normal(0, 1, int(0.12 * SR)), 2000) * env(int(0.12 * SR), 0.001, 0.03)
        return place(n, (0, bloop(r, 400, 200, 0.1)), (0.1, pop), (0.17, burst), (0.18, 0.8 * puff(r)))
    if kind == "idle":
        n = int(0.3 * SR)
        return lp(r.normal(0, 1, n), 500 + 150 * i) * env(n, 0.03, 0.06) + 0.5 * place(n, (0.05, bloop(r, 160 + 30 * i, 260, 0.15)))


# ---------- crab: clicky, chitinous ----------
def click(r, fc, dur=0.03, ring=0.008):
    n = int(dur * SR); t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * fc * t) * np.exp(-t / ring)
    return tone + 0.6 * bp(r.normal(0, 1, n), fc * 1.3, 3) * np.exp(-t / (ring / 2))


def crab(r, kind, i):
    if kind == "notice":
        n = int(0.34 * SR)
        return place(n, *[(k * 0.055, click(r, 2600 + 300 * k)) for k in range(5)])
    if kind == "attack":
        n = int(0.3 * SR); thud = sweep(np.linspace(180, 90, int(0.1 * SR))) * env(int(0.1 * SR), 0.002, 0.03)
        return place(n, (0, 0.5 * click(r, 2000)), (0.05 + 0.01 * i, 1.4 * click(r, 3200 - 300 * i, 0.04, 0.01)), (0.06 + 0.01 * i, 0.8 * thud))
    if kind == "hurt":
        n = int(0.3 * SR); parts = []
        for k in range(6 + i):
            parts.append((r.uniform(0, 0.12), r.uniform(0.4, 1) * click(r, r.uniform(1800, 4200), 0.02, 0.004)))
        crunch = bp(r.normal(0, 1, n), 2500, 1.5) * env(n, 0.001, 0.04)
        return place(n, *parts) + 0.6 * crunch
    if kind == "death":
        n = int(0.5 * SR)
        crack = place(int(0.15 * SR), *[(k * 0.012, click(r, 3500 - 250 * k, 0.03, 0.006)) for k in range(7)])
        return place(n, (0, crack), (0.12, puff(r)))
    if kind == "idle":
        n = int(0.28 * SR)
        return place(n, (0.02, 0.8 * click(r, 2400 + 200 * i)), (0.12 + 0.03 * i, 0.6 * click(r, 2700 + 200 * i)))


# ---------- piglet: snorty, grunting ----------
def voice(r, f, formants, breath=0.15):
    src = saw(f) + breath * r.normal(0, 1, len(f))
    return sum(g * bp(src, fc, q) for fc, q, g in formants)


PIG = [(700, 6, 1.0), (1300, 8, 0.6), (2600, 10, 0.25)]
NASAL = [(350, 4, 1.0), (1100, 6, 0.4)]


def oink(r, f0, f1, dur, wobble=0.0):
    t = t_(dur); f = np.linspace(f0, f1, len(t)) * (1 + wobble * np.sin(2 * np.pi * 9 * t))
    return voice(r, f, PIG) * env(len(t), 0.015, dur / 2.5)


def snort(r, dur=0.12, fc=500):
    n = int(dur * SR); flutter = 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 38 * np.arange(n) / SR))
    return bp(r.normal(0, 1, n), fc, 3) * flutter * env(n, 0.01, dur / 3)


def piglet(r, kind, i):
    if kind == "notice":
        n = int(0.4 * SR)
        return place(n, (0, snort(r, 0.1)), (0.1, oink(r, 380, 520, 0.22)))
    if kind == "attack":
        n = int(0.32 * SR); f0 = 150 + 25 * i
        return place(n, (0, 0.6 * snort(r, 0.08, 400)), (0.05, oink(r, f0, f0 * 0.8, 0.2 + 0.02 * i)))
    if kind == "hurt":
        return oink(r, 650 + 60 * i, 900 + 80 * i, 0.26 + 0.02 * i, wobble=0.04)
    if kind == "death":
        n = int(0.55 * SR)
        return place(n, (0, oink(r, 900, 420, 0.3, wobble=0.05)), (0.24, puff(r)))
    if kind == "idle":
        n = int(0.32 * SR)
        if i == 1:
            return place(n, (0, snort(r, 0.1, 450)), (0.14, 0.8 * snort(r, 0.12, 380)))
        return oink(r, 330, 290, 0.24)


COUNTS = {"notice": 1, "attack": 3, "hurt": 3, "death": 1, "idle": 2}
MOBS = {"slime": slime, "crab": crab, "piglet": piglet}

if __name__ == "__main__":
    out = sys.argv[1]
    for m, (mob, fn) in enumerate(MOBS.items()):
        for k, (kind, count) in enumerate(COUNTS.items()):
            for i in range(1, count + 1):
                r = np.random.default_rng(1000 * m + 10 * k + i)
                save(f"{out}/{mob}/{mob}_{kind}_{i:02d}.wav", fn(r, kind, i), -26.0 if kind == "idle" else -20.0)
