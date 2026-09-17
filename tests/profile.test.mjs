import test from 'node:test';
import assert from 'node:assert/strict';
import { routineById } from '../lib/daily.ts';
import {
  emptyProfile,
  profileIsEmpty,
  rowToProfile,
  profileToRow,
  personalizeStep,
  personalizeSteps,
} from '../lib/profile.ts';

const stepById = (id) => {
  for (const r of ['quick', 'full', 'bridge']) {
    const found = routineById(r).steps.find((s) => s.id === id);
    if (found) return found;
  }
  throw new Error(`no step ${id}`);
};

test('a server row is range-checked rather than trusted', () => {
  assert.deepEqual(rowToProfile(null), emptyProfile());
  assert.deepEqual(rowToProfile('nonsense'), emptyProfile());
  const p = rowToProfile({
    low_note: 200,
    high_note: 'C4',
    break_low: 65,
    break_high: 61,
    songs: ['Blackbird', '   ', 42, 'Vienna'],
    hard_line: '   ',
  });
  assert.equal(p.low, null, 'out of range note dropped');
  assert.equal(p.high, null, 'non-numeric note dropped');
  // A break entered the wrong way round is still usable.
  assert.deepEqual([p.breakLow, p.breakHigh], [61, 65]);
  assert.deepEqual(p.songs, ['Blackbird', 'Vienna']);
  assert.equal(p.hardLine, null, 'whitespace-only line dropped');
});

test('a profile survives a round trip through its row', () => {
  const p = rowToProfile({
    low_note: 42,
    high_note: 78,
    break_low: 65,
    break_high: 69,
    songs: ['Blackbird'],
    hard_line: 'Into the light of a dark black night',
  });
  assert.deepEqual(rowToProfile(profileToRow(p)), p);
  assert.equal(profileIsEmpty(p), false);
  assert.equal(profileIsEmpty(emptyProfile()), true);
});

test('an empty profile leaves every step exactly as shipped', () => {
  for (const id of ['bridge', 'hard-line', 'noi', 'song', 'goo', 'belly']) {
    const step = stepById(id);
    assert.equal(personalizeStep(step, emptyProfile()), step, id);
  }
  const steps = routineById('full').steps;
  assert.equal(personalizeSteps(steps, emptyProfile()), steps);
});

test('the bridge names this singer’s break instead of anyone else’s', () => {
  const generic = stepById('bridge');
  assert.ok(!/F4|A4/.test(generic.cue + generic.detail.join(' ')), 'ships without fixed notes');
  const p = { ...emptyProfile(), breakLow: 65, breakHigh: 69 };
  const personal = personalizeStep(generic, p);
  assert.match(personal.cue, /F4/);
  assert.match(personal.cue, /A4/);
  assert.match(personal.detail[0], /F4 to A4/);
  // A higher voice gets its own notes, not the same ones.
  const higher = personalizeStep(generic, { ...emptyProfile(), breakLow: 69, breakHigh: 72 });
  assert.match(higher.cue, /A4/);
  assert.match(higher.cue, /C5/);
  assert.ok(!higher.cue.includes('F4'));
});

test('a half-filled profile personalises only the half it can', () => {
  const p = { ...emptyProfile(), hardLine: 'Into the light' };
  assert.match(personalizeStep(stepById('hard-line'), p).cue, /Into the light/);
  // Break still unknown, so the bridge stays generic.
  assert.equal(personalizeStep(stepById('bridge'), p), stepById('bridge'));
  assert.equal(personalizeStep(stepById('song'), p), stepById('song'));
});

test('songs read as a sentence, however many there are', () => {
  const one = personalizeStep(stepById('song'), { ...emptyProfile(), songs: ['Blackbird'] });
  assert.equal(one.detail[0], 'Blackbird. Pick one.');
  const three = personalizeStep(stepById('song'), {
    ...emptyProfile(),
    songs: ['Blackbird', 'Vienna', 'Bless the Telephone'],
  });
  assert.equal(three.detail[0], 'Blackbird, Vienna or Bless the Telephone. Pick one.');
});

test('the low-note step reaches one semitone past what is known', () => {
  const p = { ...emptyProfile(), low: 42 };
  const step = personalizeStep(stepById('noi'), p);
  assert.match(step.detail[3], /F♯2/);
  assert.match(step.detail[3], /F2/);
});

test('personalising a routine never changes its shape or timing', () => {
  const steps = routineById('full').steps;
  const p = {
    low: 42,
    high: 78,
    breakLow: 65,
    breakHigh: 69,
    songs: ['Blackbird'],
    hardLine: 'Into the light',
  };
  const out = personalizeSteps(steps, p);
  assert.equal(out.length, steps.length);
  out.forEach((s, i) => {
    assert.equal(s.id, steps[i].id);
    assert.equal(s.seconds, steps[i].seconds);
    assert.equal(s.engine, steps[i].engine);
    assert.ok(s.detail.length > 0 && s.cue.length > 0);
  });
});
