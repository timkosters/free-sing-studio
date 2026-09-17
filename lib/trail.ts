// Turning a stream of pitch samples into a line somebody can read.
//
// The detector reports per sample, and a real voice is not reported perfectly:
// a consonant, a breath or a moment of hoarseness drops a sample or two even
// while the singing continues. Drawn literally, that becomes a dotted scatter,
// and a lone sample between two gaps draws nothing at all, because a path with
// one point has no length. So the trail bridges brief gaps, splits only on real
// silence, and smooths the jitter that survives.
//
// Pure, so the shape of the line can be tested without audio or a DOM.

export type Sample = { t: number; midi: number | null };

/**
 * A gap this long or shorter is treated as the singing continuing: it is the
 * length of a consonant, not of stopping. Longer, and the line genuinely
 * breaks.
 */
export const MAX_BRIDGE_SECONDS = 0.28;

/** Width of the smoothing window, in samples. Odd, so there is a middle. */
const SMOOTH_WINDOW = 3;

const inRange = (midi: number | null, low: number, high: number): midi is number =>
  midi !== null && Number.isFinite(midi) && midi >= low && midi <= high;

/**
 * Split samples into runs of continuous singing.
 *
 * A run ends when the voice has been absent for longer than `maxBridge`, so
 * short dropouts stay inside one run and the line drawn from it stays whole.
 */
export function trailRuns(
  samples: Sample[],
  low: number,
  high: number,
  maxBridge: number = MAX_BRIDGE_SECONDS,
): { t: number; midi: number }[][] {
  const runs: { t: number; midi: number }[][] = [];
  let current: { t: number; midi: number }[] = [];
  let lastHeard: number | null = null;
  for (const s of samples) {
    if (!inRange(s.midi, low, high)) continue;
    if (
      lastHeard !== null &&
      (s.t - lastHeard > maxBridge || s.t < lastHeard) &&
      current.length
    ) {
      runs.push(current);
      current = [];
    }
    current.push({ t: s.t, midi: s.midi });
    lastHeard = s.t;
  }
  if (current.length) runs.push(current);
  return runs;
}

/**
 * Median-smooth one run.
 *
 * A median rather than an average on purpose: it removes a single wild sample
 * without dragging the line towards it, and it leaves a genuine slide alone,
 * because the middle of three rising values is the middle value. Ends are left
 * as they are so the line still starts and stops where the voice did.
 */
export function smoothRun(
  run: { t: number; midi: number }[],
): { t: number; midi: number }[] {
  if (run.length < SMOOTH_WINDOW) return run;
  const half = (SMOOTH_WINDOW - 1) / 2;
  return run.map((point, i) => {
    if (i < half || i >= run.length - half) return point;
    const window = run
      .slice(i - half, i + half + 1)
      .map((p) => p.midi)
      .sort((a, b) => a - b);
    return { t: point.t, midi: window[half] };
  });
}

/**
 * The SVG path for one run.
 *
 * A single-sample run still gets an explicit line to its own point, so a round
 * line cap renders it as a dot rather than as nothing at all.
 */
export function runPath(
  run: { t: number; midi: number }[],
  x: (t: number) => number,
  y: (midi: number) => number,
): string {
  if (!run.length) return '';
  const head = `M${x(run[0].t).toFixed(1)},${y(run[0].midi).toFixed(1)}`;
  if (run.length === 1)
    return `${head} L${x(run[0].t).toFixed(1)},${y(run[0].midi).toFixed(1)}`;
  return (
    head +
    run
      .slice(1)
      .map((p) => ` L${x(p.t).toFixed(1)},${y(p.midi).toFixed(1)}`)
      .join('')
  );
}

/** Every run of a trail, smoothed, as SVG path strings. */
export function trailPaths(
  samples: Sample[],
  low: number,
  high: number,
  x: (t: number) => number,
  y: (midi: number) => number,
  maxBridge: number = MAX_BRIDGE_SECONDS,
): string[] {
  return trailRuns(samples, low, high, maxBridge)
    .map((run) => runPath(smoothRun(run), x, y))
    .filter((d) => d.length > 0);
}
