import test from 'node:test';
import assert from 'node:assert/strict';
import {
  MAX_BRIDGE_SECONDS,
  trailRuns,
  smoothRun,
  runPath,
  trailPaths,
} from '../lib/trail.ts';

const LOW = 23.5,
  HIGH = 96.5;
// The real sampler runs every 70ms.
const stream = (midis, step = 0.07) =>
  midis.map((midi, i) => ({ t: i * step, midi }));

const x = (t) => t * 100;
const y = (m) => 100 - m;

test('a brief dropout does not break the line', () => {
  // One missing sample is a consonant, not the end of a phrase.
  const runs = trailRuns(stream([60, 60, null, 61, 61]), LOW, HIGH);
  assert.equal(runs.length, 1);
  assert.equal(runs[0].length, 4);
});

test('real silence does break the line', () => {
  const gap = Math.ceil(MAX_BRIDGE_SECONDS / 0.07) + 2;
  const runs = trailRuns(
    stream([60, 60, ...Array.from({ length: gap }, () => null), 64, 64]),
    LOW,
    HIGH,
  );
  assert.equal(runs.length, 2);
  assert.deepEqual(
    runs.map((r) => r.length),
    [2, 2],
  );
});

test('a lone sample still draws something', () => {
  // This is what made the trail vanish while the keys still lit: a path with
  // one point has no length, so nothing was painted.
  const runs = trailRuns(stream([null, 60, null]), LOW, HIGH);
  assert.equal(runs.length, 1);
  const d = runPath(runs[0], x, y);
  assert.ok(d.includes('L'), `single point produced "${d}"`);
  assert.ok(d.length > 0);
});

test('out-of-range and non-finite readings are dropped, not drawn', () => {
  const runs = trailRuns(
    [
      { t: 0, midi: 5 },
      { t: 0.07, midi: 60 },
      { t: 0.14, midi: 200 },
      { t: 0.21, midi: NaN },
      { t: 0.28, midi: 61 },
    ],
    LOW,
    HIGH,
  );
  assert.equal(runs.length, 1);
  assert.deepEqual(
    runs[0].map((p) => p.midi),
    [60, 61],
  );
});

test('time running backwards starts a new run rather than drawing a spike', () => {
  const runs = trailRuns(
    [
      { t: 1, midi: 60 },
      { t: 1.07, midi: 60 },
      { t: 0.2, midi: 62 },
    ],
    LOW,
    HIGH,
  );
  assert.equal(runs.length, 2);
});

test('smoothing removes a lone spike but leaves a real slide alone', () => {
  const spiky = stream([60, 60, 72, 60, 60]).map((p, i) => ({ t: i * 0.07, midi: p.midi }));
  const smoothed = smoothRun(spiky.map((p) => ({ t: p.t, midi: p.midi })));
  assert.equal(smoothed[2].midi, 60, 'the spike is pulled back to its neighbours');
  // A siren rising a semitone a sample must survive untouched.
  const slide = Array.from({ length: 8 }, (_, i) => ({ t: i * 0.07, midi: 55 + i }));
  assert.deepEqual(smoothRun(slide), slide);
  // Ends are never invented.
  assert.equal(smoothed[0].midi, 60);
  assert.equal(smoothed.at(-1).midi, 60);
});

test('smoothing never moves a point in time, or changes how many there are', () => {
  const run = Array.from({ length: 12 }, (_, i) => ({
    t: i * 0.07,
    midi: 60 + (i % 3),
  }));
  const smoothed = smoothRun(run);
  assert.equal(smoothed.length, run.length);
  smoothed.forEach((p, i) => assert.equal(p.t, run[i].t));
});

test('a short run is left alone rather than smoothed away', () => {
  const two = [
    { t: 0, midi: 60 },
    { t: 0.07, midi: 64 },
  ];
  assert.deepEqual(smoothRun(two), two);
  assert.deepEqual(smoothRun([]), []);
});

test('an unbroken phrase draws as exactly one path', () => {
  const paths = trailPaths(
    stream(Array.from({ length: 40 }, (_, i) => 55 + Math.round(i / 3))),
    LOW,
    HIGH,
    x,
    y,
  );
  assert.equal(paths.length, 1);
  assert.ok(paths[0].startsWith('M'));
  assert.ok(paths[0].split('L').length > 30);
});

test('nothing sung produces nothing drawn', () => {
  assert.deepEqual(trailPaths(stream([null, null, null]), LOW, HIGH, x, y), []);
  assert.deepEqual(trailPaths([], LOW, HIGH, x, y), []);
});

test('a siren with scattered dropouts draws as one line, not confetti', () => {
  // What a lip trill actually looked like before: heard, lost, heard again.
  const midis = Array.from({ length: 60 }, (_, i) =>
    i % 4 === 2 ? null : 45 + i * 0.5,
  );
  const paths = trailPaths(stream(midis), LOW, HIGH, x, y);
  assert.equal(paths.length, 1, 'one continuous siren');
});
