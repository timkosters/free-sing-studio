import test from 'node:test';
import assert from 'node:assert/strict';
import {
  HOLD_SECONDS,
  QUEST_LOWEST,
  QUEST_HIGHEST,
  normalizeQuestRange,
  makeQuestTargets,
  isOnTarget,
  advanceHold,
  holdComplete,
  startQuestRun,
  questSample,
  skipTarget,
  questFinished,
  currentTarget,
  summarizeQuest,
  questVerdict,
} from '../lib/quest.ts';

test('quest range is ordered, clamped to C2–C6 and at least two semitones wide', () => {
  assert.deepEqual(normalizeQuestRange(48, 60), [48, 60]);
  assert.deepEqual(normalizeQuestRange(60, 48), [48, 60]);
  assert.deepEqual(normalizeQuestRange(0, 200), [QUEST_LOWEST, QUEST_HIGHEST]);
  assert.deepEqual(normalizeQuestRange(55, 55), [55, 57]);
  assert.deepEqual(normalizeQuestRange(84, 84), [82, 84]);
  assert.deepEqual(normalizeQuestRange(NaN, 62), [60, 62]);
});

test('targets stay inside the chosen range, avoid repeats and keep leaps gentle', () => {
  for (const seed of [1, 7, 42, 999]) {
    const targets = makeQuestTargets(50, 62, 16, seed);
    assert.equal(targets.length, 16);
    assert.equal(targets[0], 56);
    for (let i = 0; i < targets.length; i++) {
      assert.ok(targets[i] >= 50 && targets[i] <= 62, `in range: ${targets[i]}`);
      if (i > 0) {
        assert.notEqual(targets[i], targets[i - 1]);
        assert.ok(Math.abs(targets[i] - targets[i - 1]) <= 5);
      }
    }
  }
  assert.deepEqual(makeQuestTargets(60, 62, 5, 3), makeQuestTargets(60, 62, 5, 3));
  assert.notDeepEqual(makeQuestTargets(40, 70, 12, 1), makeQuestTargets(40, 70, 12, 2));
  assert.equal(makeQuestTargets(60, 70, 0).length, 1);
  assert.equal(makeQuestTargets(60, 70, 1000).length, 40);
});

test('on-target tolerance is ±50 cents and silence never matches', () => {
  assert.ok(isOnTarget(60.49, 60));
  assert.ok(isOnTarget(59.51, 60));
  assert.ok(!isOnTarget(60.6, 60));
  assert.ok(!isOnTarget(null, 60));
  assert.ok(isOnTarget(60.8, 60, 100));
});

test('hold fills after about one second on target and drains rather than resets', () => {
  let hold = 0;
  let ticks = 0;
  while (!holdComplete(hold)) {
    hold = advanceHold(hold, 60.1, 60, 0.07);
    ticks++;
  }
  assert.ok(Math.abs(ticks * 0.07 - HOLD_SECONDS) < 0.1);
  const drained = advanceHold(0.6, null, 60, 0.07);
  assert.ok(drained < 0.6 && drained > 0.4);
  assert.equal(advanceHold(0.05, 65, 60, 0.07), 0);
  assert.equal(advanceHold(HOLD_SECONDS, 60, 60, 5), HOLD_SECONDS);
  // Oversized or negative frame times cannot jump the meter.
  assert.ok(advanceHold(0, 60, 60, 3) <= 0.25);
  assert.equal(advanceHold(0.5, 60, 60, -1), 0.5);
});

test('a quest run advances on sustained matches, records times and supports skipping', () => {
  let run = startQuestRun([60, 62, 64]);
  assert.equal(currentTarget(run), 60);
  let advanced = false;
  let elapsed = 0;
  while (!advanced) {
    elapsed += 0.07;
    ({ run, advanced } = questSample(run, 60, 0.07, elapsed));
  }
  assert.equal(run.index, 1);
  assert.deepEqual(run.matched, [60]);
  assert.equal(run.times.length, 1);
  assert.ok(run.times[0] >= HOLD_SECONDS);
  // Wrong note does not advance.
  ({ run, advanced } = questSample(run, 70, 0.07, 0.07));
  assert.equal(advanced, false);
  assert.equal(run.index, 1);
  run = skipTarget(run);
  assert.equal(run.index, 2);
  assert.equal(run.skipped, 1);
  assert.equal(currentTarget(run), 64);
  for (let i = 0; i < 20; i++) ({ run } = questSample(run, 64, 0.07, i * 0.07));
  assert.ok(questFinished(run));
  assert.deepEqual(run.outcomes, ['hit', 'skip', 'hit']);
  assert.equal(currentTarget(run), null);
  assert.deepEqual(questSample(run, 64, 0.07, 1).run, run);
  assert.equal(skipTarget(run), run);
  const summary = summarizeQuest(run);
  assert.equal(summary.matched, 2);
  assert.equal(summary.total, 3);
  assert.equal(summary.skipped, 1);
  assert.equal(summary.low, 60);
  assert.equal(summary.high, 64);
  assert.ok(summary.averageSeconds >= HOLD_SECONDS);
  assert.equal(questVerdict(summary), '2 of 3 targets matched.');
  assert.equal(questVerdict({ ...summary, matched: 3 }), 'Every target matched.');
  assert.equal(
    questVerdict(summarizeQuest(startQuestRun([]))),
    'Nothing to report yet.',
  );
  const none = summarizeQuest(skipTarget(startQuestRun([60])));
  assert.equal(none.low, null);
  assert.equal(none.averageSeconds, null);
  assert.match(questVerdict(none), /No targets matched/);
});
