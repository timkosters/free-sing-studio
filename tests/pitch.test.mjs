import test from 'node:test';
import assert from 'node:assert/strict';
import {
  detectPitch,
  midiToFrequency,
  frequencyToMidi,
  noteName,
  pitchChartBounds,
} from '../lib/pitch.ts';
const signal = (hz, sr, kind = 'pure') =>
  Float32Array.from({ length: sr > 48000 ? 8192 : 4096 }, (_, i) => {
    const a = (2 * Math.PI * hz * i) / sr;
    return kind === 'harmonic'
      ? 0.1 * Math.sin(a) + 0.3 * Math.sin(2 * a) + 0.15 * Math.sin(3 * a)
      : 0.3 * Math.sin(a);
  });
test('correct notes across C1–C7 at 44.1, 48 and 96 kHz, with strong harmonics', () => {
  for (const sr of [44100, 48000, 96000])
    for (const midi of [24, 28, 36, 41, 48, 57, 59, 60, 61, 62, 63, 64, 65, 67, 69, 72, 84, 96])
      for (const kind of ['pure', 'harmonic']) {
        const result = detectPitch(signal(midiToFrequency(midi), sr, kind), sr);
        assert.ok(result, `${midi}/${sr}/${kind} detected`);
        assert.ok(
          Math.abs(frequencyToMidi(result.frequency) - midi) * 100 < 8,
          `${midi}/${sr}/${kind}: ${result.frequency}`,
        );
      }
});
test('free singing chart expands to include low and high notes', () => {
  assert.deepEqual(pitchChartBounds([]), [35,85]);
  assert.deepEqual(pitchChartBounds([24,63,96]), [23,97]);
  for (const note of [24,41,63,85,96]) {
    const [low,high] = pitchChartBounds([note]);
    assert.ok(low <= note && high >= note);
    assert.ok(low < 63 && high > 63);
  }
  assert.deepEqual(pitchChartBounds([NaN,Infinity]), [35,85]);
});
test('silence, DC, sub-threshold sound and seeded noise are rejected', () => {
  assert.equal(detectPitch(new Float32Array(4096), 48000), null);
  assert.equal(detectPitch(new Float32Array(4096).fill(0.4), 48000), null);
  assert.equal(
    detectPitch(
      signal(311.13, 48000).map((v) => v * 0.001),
      48000,
    ),
    null,
  );
  let seed = 34;
  const noise = Float32Array.from({ length: 4096 }, () => {
    seed = (seed * 1664525 + 1013904223) >>> 0;
    return (seed / 2 ** 32 - 0.5) * 0.5;
  });
  assert.equal(detectPitch(noise, 48000), null);
});
test('frequency/cents retain direction and octave, with correct note labels', () => {
  assert.equal(noteName(63), 'D♯4');
  assert.equal(noteName(57), 'A3');
  assert.equal(noteName(69), 'A4');
  assert.ok(
    Math.abs(
      (frequencyToMidi(midiToFrequency(63) * 2 ** (0.3 / 12)) - 63) * 100 - 30,
    ) < 0.0001,
  );
  assert.ok(
    Math.abs(frequencyToMidi(440) - frequencyToMidi(220) - 12) < 0.0001,
  );
});
