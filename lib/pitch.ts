export const midiToFrequency = (midi: number) => 440 * 2 ** ((midi - 69) / 12);
export const frequencyToMidi = (frequency: number) =>
  69 + 12 * Math.log2(frequency / 440);
export function noteName(midi: number) {
  const names = [
    'C',
    'C♯',
    'D',
    'D♯',
    'E',
    'F',
    'F♯',
    'G',
    'G♯',
    'A',
    'A♯',
    'B',
  ];
  const n = Math.round(midi);
  return names[((n % 12) + 12) % 12] + (Math.floor(n / 12) - 1);
}
/** Lowest fundamental treated as a voice: just under A1. Below is rumble, not singing. */
export const MIN_HZ = 54;
/** Highest fundamental treated as a voice, comfortably above any sung note. */
export const MAX_HZ = 2200;
/**
 * How periodic a window has to be before it counts as a note.
 *
 * Textbook YIN uses 0.10-0.15, which assumes a clean signal. A breathy voice is
 * not clean: the aperiodic part of the sound pushes the normalised difference
 * well above that even when the pitch is perfectly clear to a listener, and the
 * breathiest notes are usually the lowest ones. Measured against noise, hiss,
 * breath, mains hum and rumble, 0.30 still produced no false positives.
 */
const THRESHOLD = 0.3;

/**
 * Flatten a slow amplitude envelope while leaving the pitch periodicity alone.
 *
 * A lip trill is a normally-pitched tone whose loudness the lips flutter at
 * roughly 20-35 Hz. That flutter is a real periodicity, and a strong one: at
 * low notes it beats the vocal period, so YIN locks onto the flutter and
 * reports a note two octaves below what is being sung, or nothing at all.
 * Dividing by a short running magnitude equalises the loudness across the
 * window so only the vocal period is left for YIN to find. Vibrato, which is
 * shallower and slower, passes through untouched.
 */
function flattenEnvelope(buffer: Float32Array, sampleRate: number) {
  // About 6ms. This has to sit in a narrow band: long enough to cover most of
  // one pitch period at the bottom of the range (a 100Hz note is 10ms), or the
  // division reshapes the waveform itself and a breathy low note stops being
  // findable; short enough to still track a 20-35Hz flutter. Measured at
  // sampleRate/500 it destroyed low notes; at sampleRate/160 both survive.
  const window = Math.max(8, Math.floor(sampleRate / 160));
  const magnitude = new Float32Array(buffer.length);
  let sum = 0;
  for (let i = 0; i < buffer.length; i++) {
    sum += Math.abs(buffer[i]);
    if (i >= window) sum -= Math.abs(buffer[i - window]);
    magnitude[i] = sum / Math.min(i + 1, window);
  }
  let peak = 0;
  for (const m of magnitude) if (m > peak) peak = m;
  // Never divide by near-silence, which would only amplify noise.
  const floor = peak * 0.15;
  const out = new Float32Array(buffer.length);
  for (let i = 0; i < buffer.length; i++)
    out[i] = buffer[i] / Math.max(magnitude[i], floor);
  return out;
}

// YIN with cumulative mean normalization and parabolic interpolation.
export function detectPitch(
  buffer: Float32Array,
  sampleRate: number,
): { frequency: number; confidence: number } | null {
  if (!Number.isFinite(sampleRate) || sampleRate <= 0 || buffer.length < 1024)
    return null;
  // Reduce the lag search cost at high device sample rates. Average each block
  // before decimation; the supported singing fundamentals remain below Nyquist.
  const stride = Math.max(1, Math.floor(sampleRate / 48000));
  if (stride > 1) {
    const reduced = new Float32Array(Math.floor(buffer.length / stride));
    for (let i = 0; i < reduced.length; i++) {
      let sum = 0;
      for (let j = 0; j < stride; j++) sum += buffer[i * stride + j];
      reduced[i] = sum / stride;
    }
    buffer = reduced;
    sampleRate /= stride;
  }
  // Judge silence on the original signal: flattening normalises loudness away,
  // so gating afterwards would let room noise through as a confident note.
  let mean = 0;
  for (const n of buffer) mean += n;
  mean /= buffer.length;
  let power = 0;
  for (const n of buffer) power += (n - mean) ** 2;
  if (Math.sqrt(power / buffer.length) < 0.008) return null;
  buffer = flattenEnvelope(buffer, sampleRate);
  const maxLag = Math.min(
    Math.floor(sampleRate / MIN_HZ),
    Math.floor(buffer.length / 2) - 1,
  );
  const minLag = Math.max(2, Math.floor(sampleRate / MAX_HZ));
  const size = buffer.length - maxLag;
  const diff = new Float64Array(maxLag + 1);
  diff[0] = 1;
  let running = 0;
  for (let lag = 1; lag <= maxLag; lag++) {
    let sum = 0;
    for (let j = 0; j < size; j++) {
      const d = buffer[j] - buffer[j + lag];
      sum += d * d;
    }
    running += sum;
    diff[lag] = running === 0 ? 1 : (sum * lag) / running;
  }
  let lag = minLag;
  for (; lag < maxLag; lag++)
    if (diff[lag] < THRESHOLD) {
      while (lag + 1 < maxLag && diff[lag + 1] < diff[lag]) lag++;
      break;
    }
  if (lag >= maxLag || diff[lag] > THRESHOLD) return null;
  const a = diff[lag - 1],
    b = diff[lag],
    c = diff[lag + 1],
    den = a - 2 * b + c;
  const refined = lag + (den === 0 ? 0 : (a - c) / (2 * den));
  const frequency = sampleRate / refined;
  return frequency >= MIN_HZ && frequency <= MAX_HZ
    ? { frequency, confidence: 1 - b }
    : null;
}

// Keep at least C2–C6 visible, and expand by octaves for lower/higher singing.
export function pitchChartBounds(notes: number[]): [number, number] {
  const valid = notes.filter(Number.isFinite);
  return [
    Math.max(
      23,
      Math.min(35, Math.floor(Math.min(36, ...valid) / 12) * 12 - 1),
    ),
    Math.min(97, Math.max(85, Math.ceil(Math.max(84, ...valid) / 12) * 12 + 1)),
  ];
}
