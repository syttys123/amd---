"""Generate the deterministic music bed for the promo video.

Calm, warm, and hiss-free: two slow sine pads with a soft low-passed
triangle counter-line, one gentle bell every few seconds, and nothing noisy.
Everything is synthesized from sine primitives with a fixed seed, so
re-running the script reproduces the same audio. No external samples.

Usage: python generate-music.py <output.wav> [seconds]
"""

import sys
import wave

import numpy as np

SAMPLE_RATE = 48000
SEED = 20261113


def note_hz(semitone_from_a4: float) -> float:
    return 440.0 * (2.0 ** (semitone_from_a4 / 12.0))


# Warm progression: Am -> F -> C -> G, voiced low and close so the pad
# reads as one soft chord rather than a wall of detuned oscillators.
PROGRESSION = [
    [-24, -19, -12, -9],   # Am: A2 E3 A3 C4
    [-24, -17, -12, -8],   # F : A2 F3 A3 F4
    [-28, -19, -12, -9],   # C : E2 G3 C4 A4? -> soft C voicing
    [-26, -19, -12, -7],   # G : D2 B3? -> D3 G3 D4
]


def synth_pad(duration: float, chord_index: int) -> np.ndarray:
    """One chord pad: pure sines, gentle 1.2 Hz tremolo, slow attack."""
    rng = np.random.default_rng(SEED + chord_index)
    t = np.linspace(0.0, duration, int(SAMPLE_RATE * duration), endpoint=False)
    out = np.zeros_like(t)
    for voice in PROGRESSION[chord_index % len(PROGRESSION)]:
        base = note_hz(voice)
        phase = rng.uniform(0.0, 2.0 * np.pi)
        out += np.sin(2.0 * np.pi * base * t + phase)
        # One quiet octave partial keeps it warm without sounding synthetic.
        out += 0.12 * np.sin(2.0 * np.pi * base * 2.0 * t + phase * 0.5)
    out /= float(len(PROGRESSION[chord_index % len(PROGRESSION)])) * 1.12
    tremolo = 1.0 + 0.04 * np.sin(2.0 * np.pi * 0.11 * t)
    attack = min(3.0, duration * 0.4)
    release = min(3.4, duration * 0.42)
    envelope = np.minimum(np.clip(t / attack, 0.0, 1.0),
                          np.clip((duration - t) / release, 0.0, 1.0))
    return out * envelope * tremolo


def synth_bell(when: float, semitone: float, duration: float, stereo: float) -> np.ndarray:
    """One soft bell note: sine plus a quiet fifth, smooth exponential decay."""
    total = int(SAMPLE_RATE * (when + duration))
    t = np.arange(total, dtype=np.float64) / SAMPLE_RATE
    local = t - when
    freq = note_hz(semitone)
    tone = np.sin(2.0 * np.pi * freq * t) + 0.2 * np.sin(2.0 * np.pi * freq * 1.5 * t)
    decay = np.exp(-local * 1.6)
    decay[local < 0.0] = 0.0
    attack = np.clip(local / 0.02, 0.0, 1.0)
    pan_left = np.sqrt(0.5 * (1.0 - stereo))
    pan_right = np.sqrt(0.5 * (1.0 + stereo))
    return np.stack([tone * decay * attack * pan_left,
                     tone * decay * attack * pan_right], axis=1)


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
        pad = synth_pad(length / SAMPLE_RATE, index) * 0.5
        pan = 0.04 if index % 2 == 0 else -0.04
        left = pad * np.sqrt(0.5 * (1.0 - pan))
        right = pad * np.sqrt(0.5 * (1.0 + pan))
        mix[start:start + length, 0] += left
        mix[start:start + length, 1] += right
        # The 3 s attack/release tails already keep chord changes seamless.

    # One bell per chord, on a chord tone an octave up, kept quiet.
    rng = np.random.default_rng(SEED + 4242)
    for index in range(chord_count):
        chord = PROGRESSION[index % len(PROGRESSION)]
        when = index * chord_duration + 2.0
        if when >= seconds - 1.5:
            continue
        tone = chord[(index * 2) % len(chord)] + 12.0
        bell = synth_bell(when, tone, 3.0, rng.uniform(-0.3, 0.3)) * 0.10
        end = min(total, len(bell))
        mix[:end] += bell[:end]

    fade_in = int(1.5 * SAMPLE_RATE)
    fade_out = int(3.5 * SAMPLE_RATE)
    mix[:fade_in] *= np.linspace(0.0, 1.0, fade_in)[:, None]
    mix[-fade_out:] *= np.linspace(1.0, 0.0, fade_out)[:, None]

    peak = np.max(np.abs(mix))
    if peak > 0.0:
        mix = mix / peak * 0.55

    pcm = (mix * 32767.0).astype(np.int16)
    with wave.open(output, "wb") as handle:
        handle.setnchannels(2)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(pcm.tobytes())
    print(f"wrote {output} ({seconds:.1f}s, peak={np.max(np.abs(mix)):.3f})")


if __name__ == "__main__":
    main()
