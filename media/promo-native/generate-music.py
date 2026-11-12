"""Generate the deterministic ambient music bed for the promo video.

The bed is an original composition: a slow pad progression with gentle
detune, a sparse bell-like arpeggio, and soft stereo air. Everything is
synthesized from sine/noise primitives with a fixed seed, so re-running the
script reproduces the same audio. No external samples are used.

Usage: python media/promo-native/generate-music.py <output.wav> [seconds]
"""

import sys
import wave

import numpy as np

SAMPLE_RATE = 48000
SEED = 20261112


def note_hz(semitone_from_a4: float) -> float:
    return 440.0 * (2.0 ** (semitone_from_a4 / 12.0))


# Chord progression: Am7 -> Fmaj7 -> Cmaj7 -> G(add9), expressed as
# semitone offsets from A4 for each voice (negative = below A4).
PROGRESSION = [
    [-24, -17, -12, -10, -5],   # A2 E3 A3 C4 E4 (Am7)
    [-24, -16, -12, -9, -4],    # A2 F3 A3 C? -> F3 A3 C4 E4 (Fmaj7 over A2)
    [-28, -21, -12, -9, -4],    # E2 B3? -> E2 E3 C4 E4 G4 (Cmaj7 over E2)
    [-26, -19, -12, -7, -2],    # F#? -> G2 D3 G3 B3 D4 (G add9 voicing)
]


def synth_pad(duration: float, chord_index: int) -> np.ndarray:
    """One chord pad with slow attack and release, slightly detuned."""
    rng = np.random.default_rng(SEED + chord_index)
    t = np.linspace(0.0, duration, int(SAMPLE_RATE * duration), endpoint=False)
    out = np.zeros_like(t)
    for voice in PROGRESSION[chord_index % len(PROGRESSION)]:
        base = note_hz(voice)
        for detune in (-3.5, 0.0, 3.5):
            freq = base * (2.0 ** (detune / 1200.0))
            phase = rng.uniform(0.0, 2.0 * np.pi)
            out += np.sin(2.0 * np.pi * freq * t + phase)
    voices = sum(len(p) for p in [PROGRESSION[chord_index % len(PROGRESSION)]]) * 3
    out /= max(voices, 1)
    attack = min(2.2, duration * 0.35)
    release = min(3.0, duration * 0.4)
    envelope = np.minimum(np.clip(t / attack, 0.0, 1.0),
                          np.clip((duration - t) / release, 0.0, 1.0))
    return out * envelope


def synth_pluck(when: float, semitone: float, duration: float, stereo: float) -> np.ndarray:
    """A soft bell pluck with exponential decay, placed at `when` seconds."""
    rng = np.random.default_rng(SEED + int(when * 1000))
    total = int(SAMPLE_RATE * (when + duration))
    t = np.arange(total, dtype=np.float64) / SAMPLE_RATE
    local = t - when
    freq = note_hz(semitone)
    tone = np.zeros(total, dtype=np.float64)
    for mult, gain in ((1.0, 1.0), (2.0, 0.35), (3.01, 0.12)):
        phase = rng.uniform(0.0, 2.0 * np.pi)
        tone += gain * np.sin(2.0 * np.pi * freq * mult * t + phase)
    decay = np.exp(-local * 2.4)
    decay[local < 0.0] = 0.0
    attack = np.clip(local / 0.006, 0.0, 1.0)
    pan_left = np.sqrt(0.5 * (1.0 - stereo))
    pan_right = np.sqrt(0.5 * (1.0 + stereo))
    left = tone * decay * attack * pan_left
    right = tone * decay * attack * pan_right
    return np.stack([left, right], axis=1)


def synth_air(duration: float) -> np.ndarray:
    """Very low level filtered-noise 'air' for stereo width."""
    rng = np.random.default_rng(SEED + 777)
    count = int(SAMPLE_RATE * duration)
    noise = rng.normal(0.0, 1.0, count)
    # one-pole low-pass to keep it dark
    alpha = 0.08
    lp = np.empty_like(noise)
    acc = 0.0
    for i, sample in enumerate(noise):
        acc += alpha * (sample - acc)
        lp[i] = acc
    fade = np.linspace(0.0, 1.0, count) ** 0.5
    return np.stack([lp * fade, np.roll(lp, 17) * fade], axis=1) * 0.05


def main() -> None:
    output = sys.argv[1] if len(sys.argv) > 1 else "music-bed.wav"
    seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 110.0

    chord_count = 4
    chord_duration = seconds / chord_count
    total = int(SAMPLE_RATE * seconds)
    mix = np.zeros((total, 2), dtype=np.float64)

    for index in range(chord_count):
        start = int(index * chord_duration * SAMPLE_RATE)
        length = min(total - start, int(chord_duration * SAMPLE_RATE) + 1)
        if length <= 0:
            break
        pad = synth_pad(length / SAMPLE_RATE, index) * 0.42
        pan = 0.06 if index % 2 == 0 else -0.06
        left = pad * np.sqrt(0.5 * (1.0 - pan))
        right = pad * np.sqrt(0.5 * (1.0 + pan))
        mix[start:start + length, 0] += left
        mix[start:start + length, 1] += right

    # Sparse arpeggio: each chord gets three plucks on chord tones.
    rng = np.random.default_rng(SEED + 4242)
    for index in range(chord_count):
        chord = PROGRESSION[index % len(PROGRESSION)]
        for step in range(3):
            when = index * chord_duration + 1.6 + step * chord_duration * 0.28
            if when >= seconds - 1.0:
                continue
            tone = chord[(step * 2 + index) % len(chord)] + 12.0
            pluck = synth_pluck(when, tone, 3.2, rng.uniform(-0.55, 0.55)) * 0.16
            end = min(total, len(pluck))
            mix[:end] += pluck[:end]

    air = synth_air(seconds)
    mix += air

    fade_in = int(2.0 * SAMPLE_RATE)
    fade_out = int(4.0 * SAMPLE_RATE)
    mix[:fade_in] *= np.linspace(0.0, 1.0, fade_in)[:, None]
    mix[-fade_out:] *= np.linspace(1.0, 0.0, fade_out)[:, None]

    peak = np.max(np.abs(mix))
    if peak > 0.0:
        mix = mix / peak * 0.62

    pcm = (mix * 32767.0).astype(np.int16)
    with wave.open(output, "wb") as handle:
        handle.setnchannels(2)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(pcm.tobytes())
    print(f"wrote {output} ({seconds:.1f}s, peak={np.max(np.abs(mix)):.3f})")


if __name__ == "__main__":
    main()
