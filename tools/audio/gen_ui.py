#!/usr/bin/env python3
"""Build UI SFX (deterministic).

Usage: gen_ui.py OUT_DIR   (run from the repository root)
- click_01, back_01, saved_01: Ninja Adventure menu sounds (CC0), trimmed and levelled.
- menu_open_01, menu_close_01: original, generated as a mirrored pair.
Mono 16-bit 22.05 kHz, RMS-levelled to about -22 dBFS (a little under gameplay).
"""
import os, sys, wave
import numpy as np

SR = 22050
LEVEL = -22.0
PACK = "art/Sprites/NinjaAdventure/Sounds/Menu"


def load(path, max_len=None):
    w = wave.open(path); c = w.getnchannels(); sr = w.getframerate()
    x = np.frombuffer(w.readframes(w.getnframes()), "<i2").reshape(-1, c).mean(1) / 32768.0
    x = np.interp(np.arange(int(len(x) * SR / sr)) * sr / SR, np.arange(len(x)), x)
    on = np.where(np.abs(x) > 0.01)[0]
    x = x[on[0]: on[-1] + 1]
    if max_len and len(x) > max_len * SR:
        x = x[: int(max_len * SR)].copy()
        f = int(0.06 * SR); x[-f:] *= np.linspace(1, 0, f)  # gentle fade on the cut tail
    return x


def save(path, x, level_db=LEVEL):
    x = x - np.mean(x)
    x = x / np.sqrt(np.mean(x ** 2)) * 10 ** (level_db / 20)
    x *= min(1.0, 0.95 / np.max(np.abs(x)))
    f = int(0.003 * SR); x[:f] *= np.linspace(0, 1, f); x[-f:] *= np.linspace(1, 0, f)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    w = wave.open(path, "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((x * 32767).astype("<i2").tobytes()); w.close()


def blip(f, dur=0.07, decay=0.025):
    n = int(dur * SR); t = np.arange(n) / SR
    s = np.sin(2 * np.pi * f * t) + 0.25 * np.sin(2 * np.pi * 2 * f * t)
    return s * np.minimum(t / 0.003, 1) * np.exp(-t / decay)


def pair(freqs, gap=0.055):
    n = int((gap * (len(freqs) - 1) + 0.08) * SR); out = np.zeros(n)
    for k, f in enumerate(freqs):
        b = blip(f); s = int(k * gap * SR); out[s: s + len(b)] += b[: n - s]
    return out


def main(out):
    save(f"{out}/click_01.wav", load(f"{PACK}/Menu3.wav"))
    save(f"{out}/back_01.wav", load(f"{PACK}/Cancel.wav", max_len=0.3))
    save(f"{out}/saved_01.wav", load(f"{PACK}/Accept.wav"))
    # Open rises (A5 -> E6), close is the same two notes falling (E6 -> A5).
    save(f"{out}/menu_open_01.wav", pair([880.0, 1318.5]))
    save(f"{out}/menu_close_01.wav", pair([1318.5, 880.0]))


if __name__ == "__main__":
    main(sys.argv[1])
