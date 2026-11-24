"""Generate Neura's ambient sound loops procedurally.

Every loop is built from noise shaped in the frequency domain. FFT filtering
is circular and every modulation completes whole cycles within the loop, so
each file repeats seamlessly. No recordings or third-party audio are used.

Usage (from the repository root):

    python tools/generate_ambient_sounds.py assets/sounds

Requires numpy and ffmpeg on PATH. Writes 30-second mono MP3s at 22.05 kHz.
"""

from __future__ import annotations

import pathlib
import subprocess
import sys
import tempfile
import wave

import numpy as np

RATE = 22_050
SECONDS = 30
N = RATE * SECONDS
T = np.arange(N) / RATE


def shaped_noise(rng: np.random.Generator, shape) -> np.ndarray:
    """White noise filtered by shape(freqs) in the frequency domain."""
    spectrum = np.fft.rfft(rng.standard_normal(N))
    freqs = np.fft.rfftfreq(N, 1 / RATE)
    spectrum *= shape(freqs)
    out = np.fft.irfft(spectrum, n=N)
    return out / (np.max(np.abs(out)) + 1e-9)


def cycles(per_loop: int, phase: float = 0.0) -> np.ndarray:
    """A sine completing exactly per_loop cycles over the loop (0..1)."""
    return 0.5 + 0.5 * np.sin(2 * np.pi * per_loop * T / SECONDS + phase)


def band(low: float, high: float, slope: float = 2.0):
    def shape(f):
        f = np.maximum(f, 1.0)
        rise = 1 / (1 + (low / f) ** (2 * slope))
        fall = 1 / (1 + (f / high) ** (2 * slope))
        return rise * fall

    return shape


def rain(rng):
    # Steady hiss of distant rain plus soft droplets on glass.
    hiss = shaped_noise(rng, band(400, 5000, 1.5)) * 0.55
    drops = np.zeros(N)
    for _ in range(SECONDS * 30):
        at = rng.integers(0, N)
        length = int(RATE * rng.uniform(0.004, 0.012))
        idx = (at + np.arange(length)) % N  # wraps, so the loop stays seamless
        envelope = np.exp(-np.linspace(0, 6, length))
        drops[idx] += envelope * rng.standard_normal(length) * rng.uniform(0.1, 0.5)
    drops = np.fft.irfft(np.fft.rfft(drops) * band(1500, 7000)(np.fft.rfftfreq(N, 1 / RATE)), n=N)
    drops /= np.max(np.abs(drops)) + 1e-9
    swell = 0.85 + 0.15 * cycles(3)
    return (hiss + drops * 0.35) * swell


def room_tone(rng):
    # A warm, low room hum: brown-ish noise with a slow breath of movement.
    tone = shaped_noise(rng, lambda f: 1 / np.maximum(f, 20) ** 1.0 * band(30, 900)(f))
    return tone * (0.8 + 0.2 * cycles(2))


def ocean(rng):
    # Waves arrive about every 7.5 seconds: four swells per loop.
    body = shaped_noise(rng, band(80, 2500, 1.2))
    swell = cycles(4, -np.pi / 2) ** 2.2
    return body * (0.15 + 0.85 * swell)


def wind(rng):
    # Gusts drift through a band of airy noise.
    a = shaped_noise(rng, band(200, 1400, 1.5))
    b = shaped_noise(rng, band(500, 2500, 1.5))
    gust = cycles(2) * 0.6 + cycles(5, 1.3) * 0.4
    return a * (0.3 + 0.7 * gust) + b * 0.35 * cycles(3, 0.7)


def breathe(rng):
    # Six slow breaths a minute: three per loop, a soft in and out.
    air = shaped_noise(rng, band(150, 1800, 1.5))
    breath = cycles(3, -np.pi / 2) ** 1.6
    return air * (0.08 + 0.92 * breath)


SOUNDS = {
    "rain.mp3": rain,
    "ambient_loop.mp3": room_tone,
    "ocean.mp3": ocean,
    "wind.mp3": wind,
    "breathe.mp3": breathe,
}


def write_mp3(samples: np.ndarray, path: pathlib.Path) -> None:
    samples = samples / (np.max(np.abs(samples)) + 1e-9) * 0.5  # quiet by design
    pcm = (samples * 32767).astype("<i2")
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = pathlib.Path(tmp) / "loop.wav"
        with wave.open(str(wav_path), "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(RATE)
            wav.writeframes(pcm.tobytes())
        subprocess.run(
            ["ffmpeg", "-loglevel", "error", "-y", "-i", str(wav_path),
             "-codec:a", "libmp3lame", "-b:a", "48k", str(path)],
            check=True,
        )


def main() -> None:
    out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "assets/sounds")
    out.mkdir(parents=True, exist_ok=True)
    for index, (name, make) in enumerate(SOUNDS.items()):
        rng = np.random.default_rng(20261124 + index)
        write_mp3(make(rng), out / name)
        print(f"wrote {out / name}")


if __name__ == "__main__":
    main()
