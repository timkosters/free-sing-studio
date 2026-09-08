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
  let mean = 0;
  for (const n of buffer) mean += n;
  mean /= buffer.length;
  let power = 0;
  for (const n of buffer) power += (n - mean) ** 2;
  if (Math.sqrt(power / buffer.length) < 0.008) return null;
  const maxLag = Math.min(
    Math.floor(sampleRate / 30),
    Math.floor(buffer.length / 2) - 1,
  );
  const minLag = Math.max(2, Math.floor(sampleRate / 2200));
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
    if (diff[lag] < 0.15) {
      while (lag + 1 < maxLag && diff[lag + 1] < diff[lag]) lag++;
      break;
    }
  if (lag >= maxLag || diff[lag] > 0.15) return null;
  const a = diff[lag - 1],
    b = diff[lag],
    c = diff[lag + 1],
    den = a - 2 * b + c;
  const refined = lag + (den === 0 ? 0 : (a - c) / (2 * den));
  const frequency = sampleRate / refined;
  return frequency >= 30 && frequency <= 2200
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
