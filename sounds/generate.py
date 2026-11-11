"""Procedurally generates the arch sounds for the car wash.

Every arch Speaker in Workspace.CarWash.New plays Start, then Loop (looped),
then Stop. This writes one Start / Loop / Stop set per arch into this folder as
.ogg files, ready to upload to Roblox.

    pip install numpy scipy        # plus ffmpeg on PATH for the .ogg encode
    python sounds/generate.py

Everything is synthesised from filtered noise, a motor/pump model and little
bubble "chirps", with a fixed random seed, so the output is reproducible.
Loops are seamless: their tonal parts complete whole cycles over the loop
length and their noise parts are cross-faded tail-into-head.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np
from scipy import signal

SR = 44100
OUT_DIR = Path(__file__).resolve().parent
LOOP_XFADE = 0.6  # seconds of tail cross-faded into the head of each loop
LOOP_RMS_DB = -18.0  # loudness target for the loops; starts/stops share the loop's gain
PEAK_DB = -1.0

rng = np.random.default_rng(20261111)


# ---------------------------------------------------------------- building blocks

def seconds(n: float) -> int:
    return int(round(n * SR))


def timeline(n: int) -> np.ndarray:
    return np.arange(n) / SR


def noise(n: int) -> np.ndarray:
    return rng.standard_normal(n)


def band(x: np.ndarray, lo: float | None, hi: float | None, order: int = 4) -> np.ndarray:
    if lo and hi:
        sos = signal.butter(order, [lo, hi], btype="bandpass", fs=SR, output="sos")
    elif lo:
        sos = signal.butter(order, lo, btype="highpass", fs=SR, output="sos")
    else:
        sos = signal.butter(order, hi, btype="lowpass", fs=SR, output="sos")
    y = signal.sosfilt(sos, x)
    return y / (np.sqrt(np.mean(y**2)) + 1e-12)


def wobble(n: int, rate: float, depth: float) -> np.ndarray:
    """Smooth random gain curve around 1.0 that changes about `rate` times a second."""
    points = max(4, int(n / SR * rate) + 4)
    knots = rng.uniform(-1, 1, points)
    curve = signal.resample(knots, n + SR)[:n]
    curve /= np.max(np.abs(curve)) + 1e-12
    return 1.0 + depth * curve


def ramp(n: int, start: float, end: float, at: float, length: float, shape: str = "smooth") -> np.ndarray:
    """Curve that holds `start`, moves to `end` between `at` and `at + length` seconds, then holds."""
    t = timeline(n)
    k = np.clip((t - at) / max(length, 1e-6), 0, 1)
    if shape == "smooth":
        k = k * k * (3 - 2 * k)
    elif shape == "exp":
        k = 1 - np.exp(-5 * k)
        k /= 1 - np.exp(-5)
    return start + (end - start) * k


def tone(freq: np.ndarray | float, n: int) -> np.ndarray:
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def rumble(n: int, body: float) -> np.ndarray:
    return band(noise(n), 30, 220) * 0.5 * body


def pump(n: int, base: np.ndarray | float, whine: np.ndarray | float, whine_level: float, body: float = 1.0,
         with_rumble: bool = True) -> np.ndarray:
    """Electric pump: mains-rate hum with harmonics, a motor whine and a low rumble."""
    hum = sum(tone(np.asarray(base) * h, n) * a for h, a in ((1, 1.0), (2, 0.55), (3, 0.3), (4, 0.15)))
    whine_tone = tone(whine, n) + 0.35 * tone(np.asarray(whine) * 2, n)
    out = body * 0.5 * hum + whine_level * whine_tone
    return out + rumble(n, body) if with_rumble else out


def bubbles(n: int, rate: float, fmin: float, fmax: float, tau: tuple[float, float], level: float = 1.0,
            density: np.ndarray | None = None) -> np.ndarray:
    """Short upward-chirping decaying sines: foam pops, droplets, gurgles."""
    out = np.zeros(n)
    expected = rate * n / SR
    count = rng.poisson(expected)
    starts = rng.integers(0, n, count)
    if density is not None:
        keep = rng.random(count) < np.clip(density[starts], 0, 1)
        starts = starts[keep]
    for s in starts:
        f0 = np.exp(rng.uniform(np.log(fmin), np.log(fmax)))
        decay = rng.uniform(*tau)
        length = min(int(decay * 6 * SR), n - s)
        if length < 8:
            continue
        t = np.arange(length) / SR
        f = f0 * (1 + 2.5 * t / decay * 0.1)  # Minnaert-style rising pitch
        burst = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / decay)
        attack = min(int(0.0015 * SR), length)
        burst[:attack] *= np.linspace(0, 1, attack)
        out[s:s + length] += burst * rng.uniform(0.3, 1.0)
    return out * level


def thump(n: int, at: float, freq: float = 70, decay: float = 0.09, level: float = 1.0) -> np.ndarray:
    """Valve / solenoid clunk."""
    out = np.zeros(n)
    s = seconds(at)
    length = min(seconds(decay * 6), n - s)
    t = np.arange(length) / SR
    body = np.sin(2 * np.pi * freq * t * (1 - 0.3 * t)) * np.exp(-t / decay)
    click = band(noise(length), 800, 5000) * np.exp(-t / 0.006) * 0.4
    out[s:s + length] = (body + click) * level
    return out


def air_burst(n: int, at: float, decay: float, level: float = 1.0, lo: float = 900, hi: float = 7000) -> np.ndarray:
    """Pneumatic hiss: pressure released or air injected."""
    out = np.zeros(n)
    s = seconds(at)
    length = n - s
    t = np.arange(length) / SR
    env = np.exp(-t / decay) * np.minimum(1, t / 0.01)
    out[s:] = band(noise(length), lo, hi) * env * level
    return out


# ---------------------------------------------------------------- loops / levels

def make_loop(length: float, noisy, base: float, whine: float, whine_level: float, pump_body: float) -> np.ndarray:
    """The noisy layers (and the pump rumble) are generated long and cross-faded
    tail-into-head so the seam is invisible; the pump's tones use frequencies
    that complete whole cycles over the loop, so they wrap seamlessly too."""
    n = seconds(length)
    x = seconds(LOOP_XFADE)
    raw = noisy(n + x) + rumble(n + x, pump_body)
    head = raw[:n].copy()
    k = np.linspace(0, np.pi / 2, x)
    head[:x] = raw[:x] * np.sin(k) + raw[n:n + x] * np.cos(k)  # equal-power tail into head
    return head + pump(n, base, whine, whine_level, pump_body, with_rumble=False)


def snap(freq: float, period: float) -> float:
    """Nearest frequency that completes whole cycles over `period` seconds."""
    return round(freq * period) / period


def rms_db(x: np.ndarray) -> float:
    return 20 * np.log10(np.sqrt(np.mean(x**2)) + 1e-12)


def limit(x: np.ndarray) -> np.ndarray:
    ceiling = 10 ** (PEAK_DB / 20)
    return np.tanh(x / ceiling) * ceiling if np.max(np.abs(x)) > ceiling * 0.8 else x


def fade_edges(x: np.ndarray, fade_in: float = 0.004, fade_out: float = 0.03) -> np.ndarray:
    x = x.copy()
    a, b = seconds(fade_in), seconds(fade_out)
    x[:a] *= np.linspace(0, 1, a)
    x[-b:] *= np.linspace(1, 0, b)
    return x


def write_ogg(path: Path, x: np.ndarray) -> None:
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        with wave.open(tmp.name, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", tmp.name,
             "-c:a", "libvorbis", "-q:a", "6", str(path)],
            check=True,
        )
        Path(tmp.name).unlink()


# ---------------------------------------------------------------- the arches

def presoak():
    """Low-pressure chemical mist: soft spray, gentle pump, light drip patter."""
    L = 8.0
    base, whine = snap(50, L), snap(420, L)

    def spray(n):
        return (band(noise(n), 600, 5000) * wobble(n, 1.5, 0.18) * 0.9
                + band(noise(n), 6000, 14000) * wobble(n, 3, 0.25) * 0.25
                + bubbles(n, 7, 2500, 6000, (0.002, 0.006), 0.5))

    loop = make_loop(L, spray, base, whine, 0.06, 0.25)

    n = seconds(2.4)
    spray_in = ramp(n, 0, 1, 0.35, 1.3) * (1 - 0.6 * ramp(n, 1, 0, 0.35, 1.0) * (wobble(n, 18, 1.0) > 1.2))
    start = (thump(n, 0.02, 75, 0.08, 0.9)
             + air_burst(n, 0.3, 0.25, 0.35)
             + spray(n) * spray_in
             + pump(n, base, ramp(n, 120, whine, 0, 1.6, "exp"), 0.06, 0.25) * ramp(n, 0.2, 1, 0, 0.8))

    n = seconds(2.0)
    stop = (spray(n) * ramp(n, 1, 0, 0, 0.45)
            + air_burst(n, 0.05, 0.35, 0.45)
            + thump(n, 0.0, 65, 0.07, 0.6)
            + pump(n, ramp(n, base, 20, 0.1, 1.6), ramp(n, whine, 60, 0.1, 1.6, "exp"), 0.06, 0.25) * ramp(n, 1, 0, 0.3, 1.6)
            + bubbles(n, 6, 2500, 6000, (0.002, 0.006), 0.6, ramp(n, 1, 0.2, 0.3, 1.5)))
    return start, loop, stop


def high_pressure():
    """High-pressure blast: harsh bright spray, water hammering the car, strong pump whine."""
    L = 6.0
    base, whine = snap(60, L), snap(900, L)

    def spray(n):
        return (band(noise(n), 1500, 12000) * wobble(n, 4, 0.15) * 1.0
                + band(noise(n), 250, 1500) * wobble(n, 2, 0.3) * 0.6)

    loop = make_loop(L, spray, base, whine, 0.12, 0.4)

    n = seconds(2.0)
    hit = ramp(n, 0, 1, 0.42, 0.12)
    start = (thump(n, 0.02, 80, 0.07, 1.0)
             + pump(n, base, ramp(n, 200, whine, 0, 0.8, "exp"), 0.12, 0.4) * ramp(n, 0.3, 1, 0, 0.5)
             + spray(n) * hit
             + air_burst(n, 0.42, 0.08, 0.6, 2000, 10000))

    n = seconds(1.6)
    stop = (spray(n) * ramp(n, 1, 0, 0, 0.15)
            + air_burst(n, 0.12, 0.3, 0.7)
            + thump(n, 0.0, 70, 0.06, 0.8)
            + pump(n, ramp(n, base, 15, 0.05, 1.3), ramp(n, whine, 80, 0.05, 1.3, "exp"), 0.12, 0.4) * ramp(n, 1, 0, 0.2, 1.35))
    return start, loop, stop


def foam():
    """Triple foam: air-injected foam bubbling and crackling out of the foamers."""
    L = 8.0
    base, whine = snap(45, L), snap(300, L)

    def bubbly(n, density=None):
        return (bubbles(n, 140, 300, 1600, (0.006, 0.03), 0.9, density)
                + bubbles(n, 60, 1500, 4000, (0.002, 0.008), 0.45, density)
                + band(noise(n), 2000, 6000) * wobble(n, 2, 0.3) * 0.18
                + band(noise(n), None, 700) * wobble(n, 1, 0.3) * 0.25)

    loop = make_loop(L, bubbly, base, whine, 0.03, 0.2)

    n = seconds(2.5)
    density = ramp(n, 0, 1, 0.4, 1.6)
    start = (thump(n, 0.02, 70, 0.08, 0.8)
             + air_burst(n, 0.15, 1.2, 0.35, 1500, 6000)
             + bubbly(n, density) * ramp(n, 0, 1, 0.3, 1.0)
             + pump(n, base, ramp(n, 80, whine, 0, 1.2, "exp"), 0.03, 0.2) * ramp(n, 0.2, 1, 0, 0.8))

    n = seconds(1.8)
    density = ramp(n, 1, 0, 0, 1.4)
    stop = (bubbly(n, density) * ramp(n, 1, 0.4, 0, 1.2)
            + air_burst(n, 0.05, 0.3, 0.4)
            + thump(n, 0.0, 65, 0.07, 0.6)
            + pump(n, ramp(n, base, 15, 0.1, 1.4), ramp(n, whine, 40, 0.1, 1.4), 0.03, 0.2) * ramp(n, 1, 0, 0.2, 1.4))
    return start, loop, stop


def clear_coat():
    """Clear coat: very fine atomised mist with a soft sparkle of droplets."""
    L = 8.0
    base, whine = snap(55, L), snap(520, L)

    def mist(n):
        return (band(noise(n), 3000, 14000) * wobble(n, 1.2, 0.2) * 0.8
                + band(noise(n), 800, 3000) * wobble(n, 0.8, 0.25) * 0.3
                + bubbles(n, 35, 3000, 8000, (0.001, 0.004), 0.35))

    loop = make_loop(L, mist, base, whine, 0.04, 0.18)

    n = seconds(2.2)
    start = (thump(n, 0.02, 75, 0.07, 0.6)
             + air_burst(n, 0.1, 0.5, 0.4, 2000, 9000)
             + mist(n) * ramp(n, 0, 1, 0.25, 1.4)
             + pump(n, base, ramp(n, 150, whine, 0, 1.4, "exp"), 0.04, 0.18) * ramp(n, 0.2, 1, 0, 0.8))

    n = seconds(1.8)
    stop = (mist(n) * ramp(n, 1, 0, 0, 0.6)
            + air_burst(n, 0.08, 0.25, 0.35, 2000, 9000)
            + thump(n, 0.0, 65, 0.06, 0.5)
            + pump(n, ramp(n, base, 15, 0.1, 1.4), ramp(n, whine, 60, 0.1, 1.4, "exp"), 0.04, 0.18) * ramp(n, 1, 0, 0.2, 1.4))
    return start, loop, stop


def spot_free():
    """Spot-free rain bar: soft curtain of falling water, lots of droplets."""
    L = 8.0
    base = snap(50, L)

    def rain(n, density=None):
        return (bubbles(n, 320, 1500, 5500, (0.0015, 0.005), 0.4, density)
                + band(noise(n), 400, 8000) * wobble(n, 0.7, 0.15) * 0.45
                + band(noise(n), 150, 600) * wobble(n, 0.5, 0.2) * 0.2)

    loop = make_loop(L, rain, base, snap(350, L), 0.02, 0.12)

    n = seconds(2.0)
    open_ = ramp(n, 0, 1, 0.2, 1.0)
    dark = band(noise(n), None, 900) * ramp(n, 0, 1, 0.15, 0.4) * ramp(n, 1, 0, 0.5, 1.0)  # first gush, then it opens up
    start = (thump(n, 0.02, 70, 0.08, 0.8)
             + dark * 0.6
             + rain(n, open_) * open_
             + pump(n, base, ramp(n, 80, snap(350, L), 0, 1.2, "exp"), 0.02, 0.12) * ramp(n, 0.2, 1, 0, 0.8))

    n = seconds(2.0)
    density = ramp(n, 1, 0.03, 0, 1.6, "exp")
    stop = (rain(n, density) * ramp(n, 1, 0.5, 0, 0.6)
            + thump(n, 0.0, 65, 0.07, 0.5)
            + pump(n, ramp(n, base, 15, 0.05, 1.2), ramp(n, snap(350, L), 40, 0.05, 1.2), 0.02, 0.12) * ramp(n, 1, 0, 0.1, 1.2))
    return start, loop, stop


ARCHES = {
    "presoak": presoak,
    "highpressure": high_pressure,
    "foam": foam,
    "clearcoat": clear_coat,
    "spotfree": spot_free,
}


def main() -> int:
    only = set(sys.argv[1:])
    for name, build in ARCHES.items():
        if only and name not in only:
            continue
        start, loop, stop = build()
        gain = 10 ** ((LOOP_RMS_DB - rms_db(loop)) / 20)
        parts = {
            "start": fade_edges(limit(start * gain), fade_out=0.005),
            "loop": limit(loop * gain),
            "stop": fade_edges(limit(stop * gain), fade_out=0.15),
        }
        for role, x in parts.items():
            path = OUT_DIR / f"{name}_{role}.ogg"
            write_ogg(path, x)
            print(f"{path.name:28s} {len(x) / SR:5.2f}s  rms {rms_db(x):6.1f} dB  peak {20 * np.log10(np.max(np.abs(x))):5.1f} dB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
