import test from 'node:test';
import assert from 'node:assert/strict';
import {
  ROUTINES,
  routineById,
  routineSeconds,
  routineLength,
  stepKey,
  emptyDaily,
  parseDaily,
  serializeDaily,
  dayKey,
  shiftDay,
  logStep,
  logComplete,
  streak,
  bestStreak,
  totalDays,
  totalSeconds,
  recentDays,
} from '../lib/daily.ts';

test('every routine is playable and honestly labelled', () => {
  for (const routine of ROUTINES) {
    assert.ok(routine.steps.length >= 4, `${routine.id} is too short`);
    for (const step of routine.steps) {
      assert.ok(step.seconds >= 30 && step.seconds <= 600, step.id);
      assert.ok(step.cue.length > 0 && step.detail.length > 0, step.id);
      assert.ok(step.source.length > 0, `${step.id} must cite a teacher`);
      if (step.engine === 'hold') assert.equal(typeof step.hold, 'number');
      if (step.engine === 'breath') assert.equal(step.breath?.length, 3);
    }
  }
  const quick = routineById('quick');
  assert.ok(routineSeconds(quick) <= 12 * 60, 'Quick must stay near ten minutes');
  assert.ok(routineSeconds(routineById('full')) <= 20 * 60, 'Full must stay inside twenty minutes');
  assert.equal(routineLength(quick), `${Math.round(routineSeconds(quick) / 60)} min`);
  assert.equal(routineById('nonsense').id, 'quick');
});

test('a repeated step still gets a unique key', () => {
  const bridge = routineById('bridge');
  const keys = bridge.steps.map((s, i) => stepKey(s, i));
  assert.equal(new Set(keys).size, keys.length);
});

test('corrupt or foreign stored days cannot fabricate practice', () => {
  assert.deepEqual(parseDaily(null), emptyDaily());
  assert.deepEqual(parseDaily('not json'), emptyDaily());
  assert.deepEqual(parseDaily('{"version":7,"days":{}}'), emptyDaily());
  const d = parseDaily(
    '{"version":1,"days":{"nope":{"seconds":9},"2026-09-15":{"seconds":-4,"steps":2.7,"completed":"yes"}}}',
  );
  assert.equal(d.days.nope, undefined);
  assert.deepEqual(d.days['2026-09-15'], {
    seconds: 0,
    steps: 2,
    completed: false,
  });
  assert.deepEqual(parseDaily(serializeDaily(d)), d);
});

test('day keys stay local and survive month, year and DST boundaries', () => {
  assert.equal(dayKey(new Date(2026, 8, 16)), '2026-09-16');
  assert.equal(shiftDay('2026-03-01', -1), '2026-02-28');
  assert.equal(shiftDay('2027-01-01', -1), '2026-12-31');
  assert.equal(shiftDay('2026-12-31', 1), '2027-01-01');
  // A spring-forward day is still exactly one calendar day wide.
  assert.equal(shiftDay('2026-03-08', -1), '2026-03-07');
});

test('a missed day does not break the streak until it is fully past', () => {
  let d = emptyDaily();
  for (const key of ['2026-09-13', '2026-09-14', '2026-09-15'])
    d = logStep(d, 120, key, 0);
  // Today untouched: yesterday's streak still stands.
  assert.equal(streak(d, '2026-09-16'), 3);
  // A whole day missed: the streak is gone.
  assert.equal(streak(d, '2026-09-17'), 0);
  d = logStep(d, 60, '2026-09-16', 0);
  assert.equal(streak(d, '2026-09-16'), 4);
  assert.equal(streak(emptyDaily(), '2026-09-16'), 0);
});

test('best streak ignores gaps and counts the longest run only', () => {
  let d = emptyDaily();
  for (const key of [
    '2026-09-01',
    '2026-09-02',
    '2026-09-03',
    '2026-09-04',
    '2026-09-09',
    '2026-09-10',
  ])
    d = logStep(d, 60, key, 0);
  assert.equal(bestStreak(d), 4);
  assert.equal(totalDays(d), 6);
  assert.equal(totalSeconds(d), 360);
  assert.equal(bestStreak(emptyDaily()), 0);
});

test('completing a routine keeps the practice already logged that day', () => {
  let d = logStep(emptyDaily(), 90, '2026-09-16', 5);
  d = logComplete(d, '2026-09-16', 6);
  assert.deepEqual(d.days['2026-09-16'], {
    seconds: 90,
    steps: 1,
    completed: true,
  });
  assert.equal(d.updated, 6);
  // Completing a day never touched still records the day.
  const fresh = logComplete(emptyDaily(), '2026-09-16', 1);
  assert.equal(fresh.days['2026-09-16'].completed, true);
});

test('the calendar strip is oldest first and ends on today', () => {
  const d = logStep(emptyDaily(), 60, '2026-09-14', 0);
  const strip = recentDays(d, 3, '2026-09-16');
  assert.deepEqual(
    strip.map((s) => s.key),
    ['2026-09-14', '2026-09-15', '2026-09-16'],
  );
  assert.equal(strip[0].day?.seconds, 60);
  assert.equal(strip[2].day, null);
});
