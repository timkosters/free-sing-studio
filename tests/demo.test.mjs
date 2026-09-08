import test from 'node:test';
import assert from 'node:assert/strict';
import {
  DEMO_BREATH,
  MELODY_NOTE_SECONDS,
  syntheticVoice,
  demoMelody,
  demoFreeSample,
} from '../lib/demo.ts';
import { advanceHold, holdComplete } from '../lib/quest.ts';

test('synthetic voice breathes, then settles onto the target within a few cents', () => {
  assert.equal(syntheticVoice(0, 60).midi, null);
  assert.equal(syntheticVoice(DEMO_BREATH - 0.01, 60).midi, null);
  assert.equal(syntheticVoice(NaN, 60).midi, null);
  const early = syntheticVoice(DEMO_BREATH + 0.02, 61).midi;
  assert.ok(early < 61 - 0.5, 'scoops up from below');
  for (const target of [50, 61, 67, 76]) {
    for (let t = DEMO_BREATH + 1.2; t < 4; t += 0.05) {
      const { midi, level } = syntheticVoice(t, target, t + 3);
      assert.ok(Math.abs(midi - target) * 100 < 20, `${target}@${t}: ${midi}`);
      assert.ok(level > 0 && level <= 1);
    }
  }
  assert.deepEqual(syntheticVoice(1, 60, 5), syntheticVoice(1, 60, 5));
});

test('targets divisible by three overshoot before correcting, and every target can complete a hold', () => {
  const peak = Math.max(
    ...Array.from({ length: 20 }, (_, i) => syntheticVoice(DEMO_BREATH + 0.1 + i * 0.02, 60).midi),
  );
  assert.ok(peak > 60.6, `overshoot: ${peak}`);
  const steady = Math.max(
    ...Array.from({ length: 20 }, (_, i) => syntheticVoice(DEMO_BREATH + 0.1 + i * 0.02, 61).midi),
  );
  assert.ok(steady < 61.5, `no overshoot: ${steady}`);
  for (const target of [57, 60, 62, 63]) {
    let hold = 0,
      t = 0,
      done = null;
    while (t < 5 && done === null) {
      hold = advanceHold(hold, syntheticVoice(t, target, t).midi, target, 0.07);
      if (holdComplete(hold)) done = t;
      t += 0.07;
    }
    assert.ok(done !== null && done < 3, `${target} completes by ${done}`);
  }
});

test('demo melody cycles deterministically and produces a playable trace', () => {
  const first = demoMelody(0);
  assert.equal(first.target, 60);
  assert.equal(first.local, 0);
  const second = demoMelody(MELODY_NOTE_SECONDS + 0.1);
  assert.equal(second.target, 62);
  assert.ok(Math.abs(second.local - 0.1) < 1e-9);
  assert.equal(demoMelody(-4).target, 60);
  assert.equal(demoMelody(NaN).target, 60);
  const notes = new Set();
  let voiced = 0,
    total = 0;
  for (let t = 0; t < 40; t += 0.07) {
    const { midi } = demoFreeSample(t);
    total++;
    if (midi !== null) {
      voiced++;
      notes.add(Math.round(midi));
      assert.ok(midi > 50 && midi < 76);
    }
  }
  assert.ok(notes.size >= 5, 'melody visits several notes');
  assert.ok(voiced / total > 0.6, 'mostly voiced');
  assert.ok(voiced < total, 'includes breaths');
});
