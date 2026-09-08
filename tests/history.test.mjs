import test from 'node:test';
import assert from 'node:assert/strict';
import {
  SUSTAIN_SECONDS,
  emptySustain,
  trackSustained,
  emptyHistory,
  parseHistory,
  serializeHistory,
  addPracticeSeconds,
  recordSession,
  recordRange,
  recordQuest,
  formatMinutes,
  rangeSpan,
} from '../lib/history.ts';

test('suspension gaps and corrupt local history cannot fabricate range or bests', () => {
  let s = trackSustained(emptySustain(), 60, 0);
  s = trackSustained(s, 60, 300);
  assert.equal(s.low, null);
  assert.deepEqual(parseHistory('{"version":99}'), emptyHistory());
  const h = parseHistory(
    '{"low":-999,"high":999,"quest":{"quickestAverage":-3,"widestLow":80,"widestHigh":30}}',
  );
  assert.equal(h.low, null);
  assert.equal(h.high, null);
  assert.equal(h.quest.quickestAverage, null);
  assert.deepEqual([h.quest.widestLow, h.quest.widestHigh], [30, 80]);
});

test('only notes held for half a second widen the observed range', () => {
  let s = emptySustain();
  // A brief blip at C5 never counts.
  s = trackSustained(s, 72, 0);
  s = trackSustained(s, 72.1, 0.2);
  s = trackSustained(s, null, 0.3);
  assert.equal(s.low, null);
  assert.equal(s.high, null);
  // A held A3 counts once the sustain threshold passes.
  s = trackSustained(s, 57.05, 1);
  s = trackSustained(s, 56.95, 1.3);
  assert.equal(s.low, null);
  s = trackSustained(s, 57.02, 1 + SUSTAIN_SECONDS);
  assert.equal(s.low, 57);
  assert.equal(s.high, 57);
  // Sliding through E4 for a moment does not count; holding it does.
  s = trackSustained(s, 64, 2);
  s = trackSustained(s, 64, 2.2);
  assert.equal(s.high, 57);
  s = trackSustained(s, 64, 2.6);
  assert.equal(s.high, 64);
  assert.equal(s.low, 57);
  // Silence keeps the observed range; the same state object is returned when nothing changes.
  const quiet = trackSustained(s, null, 3);
  assert.equal(quiet.low, 57);
  assert.equal(trackSustained(quiet, null, 3.1), quiet);
  assert.equal(trackSustained(quiet, NaN, 3.2), quiet);
  // Sustained lower note lowers the floor.
  s = trackSustained(quiet, 48, 4);
  s = trackSustained(s, 48, 4.6);
  assert.equal(s.low, 48);
  assert.equal(s.high, 64);
  assert.equal(rangeSpan(s.low, s.high), 16);
  assert.equal(rangeSpan(null, 64), null);
});

test('history parses defensively and round-trips through JSON', () => {
  assert.deepEqual(parseHistory(null), emptyHistory());
  assert.deepEqual(parseHistory(''), emptyHistory());
  assert.deepEqual(parseHistory('not json'), emptyHistory());
  assert.deepEqual(parseHistory('42'), emptyHistory());
  assert.deepEqual(parseHistory('[]').quest, emptyHistory().quest);
  const messy = parseHistory(
    JSON.stringify({
      seconds: -5,
      sessions: 2.7,
      low: 70,
      high: 50,
      quest: { runs: 'x', mostMatched: 3, quickestAverage: Infinity },
    }),
  );
  assert.equal(messy.seconds, 0);
  assert.equal(messy.sessions, 2);
  assert.equal(messy.low, 50);
  assert.equal(messy.high, 70);
  assert.equal(messy.quest.runs, 0);
  assert.equal(messy.quest.mostMatched, 3);
  assert.equal(messy.quest.quickestAverage, null);
  assert.equal(parseHistory(JSON.stringify({ low: 55 })).high, 55);
  let h = emptyHistory();
  h = addPracticeSeconds(h, 90, 1000);
  h = recordSession(h, 1001);
  h = recordRange(h, 50, 62, 1002);
  assert.deepEqual(parseHistory(serializeHistory(h)), h);
});

test('practice time, range and quest bests accumulate without ever shrinking', () => {
  let h = emptyHistory();
  h = addPracticeSeconds(h, 30, 1);
  h = addPracticeSeconds(h, -10, 2);
  h = addPracticeSeconds(h, NaN, 3);
  assert.equal(h.seconds, 30);
  assert.equal(h.updated, 1);
  assert.equal(addPracticeSeconds(h, 0, 9), h);
  h = recordRange(h, 55, 60, 4);
  h = recordRange(h, 57, 58, 5);
  assert.deepEqual([h.low, h.high], [55, 60]);
  assert.equal(h.updated, 4);
  h = recordRange(h, 50, 65, 6);
  assert.deepEqual([h.low, h.high], [50, 65]);
  assert.equal(recordRange(h, null, 70, 7), h);
  h = recordQuest(
    h,
    { matched: 5, total: 8, averageSeconds: 1.8, low: 55, high: 60 },
    8,
  );
  assert.equal(h.quest.runs, 1);
  assert.equal(h.quest.mostMatched, 5);
  // Incomplete runs do not set a quickest-average best.
  assert.equal(h.quest.quickestAverage, null);
  assert.deepEqual([h.quest.widestLow, h.quest.widestHigh], [55, 60]);
  h = recordQuest(
    h,
    { matched: 8, total: 8, averageSeconds: 2.2, low: 57, high: 59 },
    9,
  );
  assert.equal(h.quest.mostMatched, 8);
  assert.equal(h.quest.quickestAverage, 2.2);
  assert.deepEqual([h.quest.widestLow, h.quest.widestHigh], [55, 60]);
  h = recordQuest(
    h,
    { matched: 8, total: 8, averageSeconds: 1.5, low: 50, high: 64 },
    10,
  );
  assert.equal(h.quest.quickestAverage, 1.5);
  assert.deepEqual([h.quest.widestLow, h.quest.widestHigh], [50, 64]);
  assert.equal(h.quest.runs, 3);
  h = recordQuest(
    h,
    { matched: 0, total: 5, averageSeconds: null, low: null, high: null },
    11,
  );
  assert.equal(h.quest.runs, 4);
  assert.equal(h.quest.mostMatched, 8);
  assert.equal(recordSession(h, 12).sessions, 1);
});

test('minutes label stays readable from seconds to hours', () => {
  assert.equal(formatMinutes(0), '0 sec');
  assert.equal(formatMinutes(45), '45 sec');
  assert.equal(formatMinutes(60), '1 min');
  assert.equal(formatMinutes(150), '3 min');
  assert.equal(formatMinutes(3600), '1 h');
  assert.equal(formatMinutes(3600 * 2 + 60 * 5), '2 h 5 min');
  assert.equal(formatMinutes(-20), '0 sec');
});
