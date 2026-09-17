import test from 'node:test';
import assert from 'node:assert/strict';
import {
  detectPitch,
  MIN_HZ,
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
// A1 (55 Hz) is the floor: nothing below it is a sung fundamental, and the
// band underneath is where lip-trill flutter and room rumble live.
test('correct notes across A1–C7 at 44.1, 48 and 96 kHz, with strong harmonics', () => {
  for (const sr of [44100, 48000, 96000])
    for (const midi of [33, 36, 41, 48, 57, 59, 60, 61, 62, 63, 64, 65, 67, 69, 72, 84, 96])
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

/**
 * A lip trill flutters loudness at roughly 20-35 Hz over a normally-pitched
 * tone. Before the envelope was flattened, that flutter beat the vocal period
 * on low notes: sirens read as nothing, or as a note two octaves down.
 */
const lipTrill = (hz, sr, { amp = 0.08, flutterHz = 26, depth = 0.85 } = {}) =>
  Float32Array.from({ length: sr > 48000 ? 8192 : 4096 }, (_, i) => {
    const t = i / sr;
    let tone = 0;
    for (let h = 1; h <= 8; h++) tone += Math.sin(2 * Math.PI * hz * h * t) / h;
    const envelope =
      1 - depth * 0.5 * (1 - Math.cos(2 * Math.PI * flutterHz * t));
    return amp * tone * Math.max(0, envelope);
  });

test('a lip trill reads as the note sung, across the whole range', () => {
  for (const sr of [44100, 48000])
    for (const midi of [40, 42, 45, 48, 50, 53, 57, 60, 69, 81])
      for (const flutterHz of [18, 26, 34]) {
        const result = detectPitch(lipTrill(midiToFrequency(midi), sr, { flutterHz }), sr);
        assert.ok(result, `trill ${midi}/${sr}/${flutterHz}Hz detected`);
        assert.ok(
          Math.abs(frequencyToMidi(result.frequency) - midi) < 0.5,
          `trill ${midi}/${sr}/${flutterHz}Hz read as ${noteName(frequencyToMidi(result.frequency))}`,
        );
      }
});

test('flattening the envelope leaves vibrato and quiet singing alone', () => {
  const sr = 48000;
  for (const midi of [45, 52, 60, 69]) {
    const hz = midiToFrequency(midi);
    // Vibrato is shallower and far slower than a trill; it must pass through.
    const vibrato = lipTrill(hz, sr, { amp: 0.2, flutterHz: 5.5, depth: 0.3 });
    const v = detectPitch(vibrato, sr);
    assert.ok(v && Math.abs(frequencyToMidi(v.frequency) - midi) < 0.5, `vibrato ${midi}`);
    const quiet = lipTrill(hz, sr, { amp: 0.03, flutterHz: 26 });
    const q = detectPitch(quiet, sr);
    assert.ok(q && Math.abs(frequencyToMidi(q.frequency) - midi) < 0.5, `quiet trill ${midi}`);
  }
});

test('rumble below the voice is never reported as a note', () => {
  const sr = 48000;
  for (const hz of [18, 26, 33, 41, 50]) {
    const buzz = Float32Array.from({ length: 4096 }, (_, i) =>
      0.3 * Math.sin((2 * Math.PI * hz * i) / sr),
    );
    const result = detectPitch(buzz, sr);
    assert.ok(
      result === null || result.frequency >= MIN_HZ,
      `${hz}Hz reported as ${result?.frequency}`,
    );
  }
});
