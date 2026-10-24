#!/usr/bin/env python3
"""Build world/interaction SFX (deterministic).

Usage: gen_world.py OUT_DIR   (run from the repository root)
- sword_hit_mob_01..03: Ninja Adventure hit (CC0) layered with a generated low thump for weight.
- player_respawn_01, regen_tick_01, player_join_01: original, generated.
Mono 16-bit 22.05 kHz; RMS-levelled to about -20 dBFS (regen tick about -30 dBFS).
"""
import os, sys, wave
import numpy as np

SR = 22050
PACK = "art/Sprites/NinjaAdventure/Sounds/Game"


def load(path):
    w = wave.open(path); c = w.getnchannels(); sr = w.getframerate()
    x = np.frombuffer(w.readframes(w.getnframes()), "<i2").reshape(-1, c).mean(1) / 32768.0
    x = np.interp(np.arange(int(len(x) * SR / sr)) * sr / SR, np.arange(len(x)), x)  # resample
    on = np.where(np.abs(x) > 0.01)[0]
    return x[on[0]: on[-1] + 1]  # trim silence


def save(path, x, level_db=-20.0):
    x = x - np.mean(x)
    x = x / np.sqrt(np.mean(x ** 2)) * 10 ** (level_db / 20)
    x *= min(1.0, 0.95 / np.max(np.abs(x)))
    f = int(0.004 * SR); x[:f] *= np.linspace(0, 1, f); x[-f:] *= np.linspace(1, 0, f)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    w = wave.open(path, "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((x * 32767).astype("<i2").tobytes()); w.close()


def env(n, a, d):
    t = np.arange(n) / SR
    return np.minimum(t / a, 1) * np.exp(-t / d)


def thump(f0, dur=0.16):
    n = int(dur * SR); t = np.arange(n) / SR
    f = f0 * (0.5 + 0.5 * np.exp(-t / 0.03))  # quick downward pitch drop
    return np.tanh(2.5 * np.sin(2 * np.pi * np.cumsum(f) / SR)) * env(n, 0.001, 0.05)


def chime(f, dur, decay):
    n = int(dur * SR); t = np.arange(n) / SR
    s = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * 2 * f * t) + 0.12 * np.sin(2 * np.pi * 3.01 * f * t)
    return s * env(n, 0.004, decay)


def place(n, *parts):
    out = np.zeros(n)
    for start, sig in parts:
        s = int(start * SR); e = min(n, s + len(sig)); out[s:e] += sig[: e - s]
    return out


def lp(x, fc):
    a = np.exp(-2 * np.pi * fc / SR); y = np.zeros_like(x); s = 0.0
    for i in range(len(x)):
        s = (1 - a) * x[i] + a * s; y[i] = s
    return y


def main(out):
    # Sword landing on a mob: pack hit + body thump (different from hit_land / player_hurt).
    for i, (src, f0) in enumerate([("Hit.wav", 120), ("Hit4.wav", 105), ("Hit7.wav", 135)], 1):
        hit = load(f"{PACK}/{src}"); hit /= np.sqrt(np.mean(hit ** 2))
        th = thump(f0); th /= np.sqrt(np.mean(th ** 2))
        n = max(len(hit), len(th)) + int(0.01 * SR)
        save(f"{out}/sword_hit_mob_{i:02d}.wav", place(n, (0, hit), (0.004, 0.9 * th)))

    r = np.random.default_rng(42)
    # Respawn: rising airy whoosh into a soft three-note chime (C6 E6 G6), 0.8 s.
    n = int(0.8 * SR); t = np.arange(n) / SR
    whoosh = lp(r.normal(0, 1, n), 1800) * np.sin(np.pi * np.clip(t / 0.45, 0, 1)) ** 2 * (t < 0.45)
    notes = place(n, (0.18, chime(1046.5, 0.6, 0.18)), (0.28, chime(1318.5, 0.5, 0.18)), (0.38, chime(1568.0, 0.42, 0.2)))
    save(f"{out}/player_respawn_01.wav", 0.5 * whoosh + notes)

    # Regen tick: one tiny, soft, low-ish sine blip (A5 with a quick decay), 0.12 s, about -30 dBFS.
    n = int(0.12 * SR); t = np.arange(n) / SR
    save(f"{out}/regen_tick_01.wav", np.sin(2 * np.pi * 880 * t) * env(n, 0.006, 0.025), -30.0)

    # Player join: friendly two-note rising cue (G5 -> D6), 0.42 s.
    n = int(0.42 * SR)
    save(f"{out}/player_join_01.wav", place(n, (0, chime(784.0, 0.3, 0.07)), (0.11, chime(1174.7, 0.31, 0.1))))


if __name__ == "__main__":
    main(sys.argv[1])
