// Pitch Quest: one piano target at a time, matched and held steadily to advance.
// Everything here is pure so the hold logic can be unit-tested without audio.

export const QUEST_LOWEST = 36; // C2
export const QUEST_HIGHEST = 84; // C6
export const HOLD_SECONDS = 1;
export const QUEST_TOLERANCE_CENTS = 50;
export const QUEST_COUNTS = [5, 8, 12, 16] as const;

/** Clamp and order a chosen comfortable range; guarantees at least two semitones. */
export function normalizeQuestRange(low: number, high: number): [number, number] {
  const clamp = (n: number) =>
    Math.min(
      QUEST_HIGHEST,
      Math.max(QUEST_LOWEST, Number.isFinite(n) ? Math.round(n) : 60),
    );
  let a = clamp(low),
    b = clamp(high);
  if (a > b) [a, b] = [b, a];
  if (b - a < 2) {
    if (b + (2 - (b - a)) <= QUEST_HIGHEST) b = a + 2;
    else a = b - 2;
  }
  return [a, b];
}

// Small deterministic generator (mulberry32) so target sequences are reproducible in tests.
function seededRandom(seed: number) {
  let a = (Math.floor(Number.isFinite(seed) ? seed : 1) >>> 0) || 1;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * Build a sequence of targets inside [low, high] with gentle leaps.
 * Starts near the middle, never repeats the same note twice in a row,
 * and keeps every leap within five semitones so nothing feels like a push.
 */
export function makeQuestTargets(
  low: number,
  high: number,
  count: number,
  seed = 1,
): number[] {
  const [a, b] = normalizeQuestRange(low, high);
  const n = Math.max(1, Math.min(40, Math.floor(count) || 1));
  const random = seededRandom(seed);
  const targets: number[] = [];
  let current = Math.round((a + b) / 2);
  for (let i = 0; i < n; i++) {
    if (i > 0) {
      const lo = Math.max(a, current - 5),
        hi = Math.min(b, current + 5);
      const options: number[] = [];
      for (let m = lo; m <= hi; m++) if (m !== current) options.push(m);
      current = options[Math.floor(random() * options.length)] ?? current;
    }
    targets.push(current);
  }
  return targets;
}

/** True when a detected pitch sits inside the tolerance window of the target. */
export function isOnTarget(
  midi: number | null,
  target: number,
  tolerance = QUEST_TOLERANCE_CENTS,
) {
  return midi !== null && Math.abs(midi - target) * 100 <= tolerance;
}

/**
 * Advance the hold timer by one sample. Matching samples add their duration;
 * unmatched or silent samples drain the timer twice as fast instead of
 * resetting it, so a single wobble does not throw away a good hold.
 */
export function advanceHold(
  hold: number,
  midi: number | null,
  target: number,
  dt: number,
  tolerance = QUEST_TOLERANCE_CENTS,
) {
  const step = Math.min(0.25, Math.max(0, dt));
  return isOnTarget(midi, target, tolerance)
    ? Math.min(HOLD_SECONDS, hold + step)
    : Math.max(0, hold - step * 2);
}

export const holdComplete = (hold: number) => hold >= HOLD_SECONDS - 1e-9;

export type QuestOutcome = 'hit' | 'skip';

export type QuestRun = {
  targets: number[];
  index: number;
  hold: number;
  /** Targets that were matched and held, in order. */
  matched: number[];
  skipped: number;
  /** One entry per target already passed, in order. */
  outcomes: QuestOutcome[];
  /** Seconds spent on each matched target, including the one-second hold. */
  times: number[];
};

export function startQuestRun(targets: number[]): QuestRun {
  return {
    targets,
    index: 0,
    hold: 0,
    matched: [],
    skipped: 0,
    outcomes: [],
    times: [],
  };
}

export const questFinished = (run: QuestRun) => run.index >= run.targets.length;

export const currentTarget = (run: QuestRun): number | null =>
  questFinished(run) ? null : run.targets[run.index];

/** Apply one pitch sample. Returns the new run and whether a target was just matched. */
export function questSample(
  run: QuestRun,
  midi: number | null,
  dt: number,
  elapsedOnTarget: number,
): { run: QuestRun; advanced: boolean } {
  const target = currentTarget(run);
  if (target === null) return { run, advanced: false };
  const hold = advanceHold(run.hold, midi, target, dt);
  if (!holdComplete(hold)) return { run: { ...run, hold }, advanced: false };
  return {
    run: {
      ...run,
      hold: 0,
      index: run.index + 1,
      matched: [...run.matched, target],
      outcomes: [...run.outcomes, 'hit'],
      times: [...run.times, Math.max(HOLD_SECONDS, elapsedOnTarget)],
    },
    advanced: true,
  };
}

export function skipTarget(run: QuestRun): QuestRun {
  if (questFinished(run)) return run;
  return {
    ...run,
    hold: 0,
    index: run.index + 1,
    skipped: run.skipped + 1,
    outcomes: [...run.outcomes, 'skip'],
  };
}

export type QuestSummary = {
  matched: number;
  total: number;
  skipped: number;
  averageSeconds: number | null;
  low: number | null;
  high: number | null;
};

export function summarizeQuest(run: QuestRun): QuestSummary {
  return {
    matched: run.matched.length,
    total: run.targets.length,
    skipped: run.skipped,
    averageSeconds: run.times.length
      ? run.times.reduce((a, b) => a + b, 0) / run.times.length
      : null,
    low: run.matched.length ? Math.min(...run.matched) : null,
    high: run.matched.length ? Math.max(...run.matched) : null,
  };
}

/** Rough label for a completed run without ranking the singer. */
export function questVerdict(summary: QuestSummary): string {
  if (summary.total === 0) return 'Nothing to report yet.';
  if (summary.matched === summary.total) return 'Every target matched.';
  if (summary.matched === 0) return 'No targets matched this time. That happens.';
  return `${summary.matched} of ${summary.total} targets matched.`;
}
