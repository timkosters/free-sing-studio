// Synthetic voice for the labeled demo mode. It never touches the microphone.
// Every function is deterministic in time so a walkthrough recording looks the
// same each run and the behaviour can be unit-tested.

export type SyntheticSample = { midi: number | null; level: number };

/** Breath gap at the start of every phrase, in seconds. */
export const DEMO_BREATH = 0.3;
/** Seconds it takes the synthetic voice to settle onto a target after the breath. */
export const DEMO_SETTLE = 0.45;

/**
 * A pitch that breathes, scoops up to the target, settles within a few cents
 * and then sustains with a light vibrato. `local` is seconds since the current
 * target appeared; `global` gives the vibrato a continuous phase.
 * Targets whose semitone is divisible by three overshoot and correct first, so a
 * demo quest visibly shows a wrong note being fixed before the hold fills.
 */
export function syntheticVoice(
  local: number,
  target: number,
  global = local,
): SyntheticSample {
  if (!Number.isFinite(local) || local < DEMO_BREATH)
    return { midi: null, level: 0.05 };
  const t = local - DEMO_BREATH;
  const wobbly = Math.round(target) % 3 === 0;
  // Scoop from just below the note.
  let offset = -1.4 * Math.exp(-t / (DEMO_SETTLE / 3));
  if (wobbly && t < 1.1) {
    // Overshoot by ~1.2 semitones then glide back down.
    offset += 1.2 * Math.max(0, 1 - Math.exp(-t / 0.08)) * Math.exp(-Math.max(0, t - 0.5) / 0.14);
  }
  const vibrato = 0.08 * Math.sin(2 * Math.PI * 5.4 * global) * Math.min(1, t / 0.6);
  const drift = 0.03 * Math.sin(global * 0.7);
  return {
    midi: target + offset + vibrato + drift,
    level: 0.45 + 0.1 * Math.sin(2 * Math.PI * 5.4 * global) + 0.15 * Math.min(1, t / 0.4),
  };
}

const MELODY = [60, 62, 64, 65, 67, 65, 64, 62, 60, 64, 67, 72, 67, 64, 60, 55];
export const MELODY_NOTE_SECONDS = 1.3;

/** Which note of the built-in demo melody is active at time t, and how long it has been. */
export function demoMelody(t: number): { target: number; local: number } {
  const time = Number.isFinite(t) && t > 0 ? t : 0;
  const index = Math.floor(time / MELODY_NOTE_SECONDS) % MELODY.length;
  return { target: MELODY[index], local: time % MELODY_NOTE_SECONDS };
}

/** Free-singing demo: wander through the melody with the synthetic voice. */
export function demoFreeSample(t: number): SyntheticSample {
  const { target, local } = demoMelody(t);
  return syntheticVoice(local, target, t);
}
