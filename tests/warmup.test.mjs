import test from 'node:test';
import assert from 'node:assert/strict';
import {
  makeWarmup,
  formatTime,
  scoreSample,
  scoreLabel,
} from '../lib/warmup.ts';
test('arpeggios move up a semitone after a four-beat breath', () => {
  const b = makeWarmup('arpeggio', 48, 2, 60);
  assert.equal(b.length, 4 + 3 * 36);
  assert.deepEqual(
    b.slice(0, 4).map((n) => n.midi),
    [null, null, null, null],
  );
  assert.deepEqual(
    b
      .filter((n) => n.round === 1 && n.phase === 'listen' && n.onset)
      .map((n) => n.midi),
    [48, 52, 55, 60, 55, 52, 48],
  );
  assert.ok(
    b.slice(18, 22).every((n) => n.midi === null && n.phase === 'count'),
  );
  assert.deepEqual(
    b.slice(4, 18).map((n) => n.midi),
    b.slice(22, 36).map((n) => n.midi),
  );
  assert.ok(b.slice(22, 36).every((n) => n.phase === 'sing'));
  assert.ok(b.slice(36, 40).every((n) => n.phase === 'rest'));
  assert.equal(b[40].midi, 49);
  assert.equal(b[40].time, 40);
  assert.equal(b.at(-1).round, 3);
});
test('five-note scale and maximum settings stay within C1–C7', () => {
  assert.deepEqual(
    makeWarmup('five-note', 48, 0, 120)
      .filter((n) => n.phase === 'listen' && n.onset)
      .map((n) => n.midi),
    [48, 50, 52, 53, 55, 53, 52, 50, 48],
  );
  const all = makeWarmup('arpeggio', 72, 12, 140);
  assert.equal(Math.max(...all.map((n) => n.midi ?? 0)), 96);
  for (const args of [
    ['wrong', 48, 2, 80],
    ['arpeggio', 10, 2, 80],
    ['arpeggio', 48, 99, 80],
    ['arpeggio', 48, 2, NaN],
  ])
    assert.throws(() => makeWarmup(...args));
  assert.equal(formatTime(125), '2:05');
});
test('pitch feedback requires sustained matching and distinguishes missing, low and high pitch', () => {
  let s;
  for (let i = 0; i < 10; i++) s = scoreSample(s, 60.2, 60);
  assert.equal(scoreLabel(s), 'Hit');
  s = undefined;
  for (let i = 0; i < 10; i++) s = scoreSample(s, null, 60);
  assert.equal(scoreLabel(s), 'No clear pitch');
  for (const [m, label] of [
    [59, 'Low'],
    [61, 'High'],
  ]) {
    s = undefined;
    for (let i = 0; i < 10; i++) s = scoreSample(s, m, 60);
    assert.equal(scoreLabel(s), label);
  }
  s = undefined;
  for (let i = 0; i < 10; i++) s = scoreSample(s, i < 3 ? 60 : null, 60);
  assert.equal(scoreLabel(s), 'Keep steady');
});
