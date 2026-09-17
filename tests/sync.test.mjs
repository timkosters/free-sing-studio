import test from 'node:test';
import assert from 'node:assert/strict';
import { emptyDaily, logStep, logComplete } from '../lib/daily.ts';
import {
  rowsToDaily,
  dailyToRows,
  mergeDaily,
  needsPush,
  looksLikeEmail,
  authMessage,
} from '../lib/sync.ts';

test('server rows are treated as untrusted input', () => {
  assert.deepEqual(rowsToDaily(null), emptyDaily());
  assert.deepEqual(rowsToDaily('rows'), emptyDaily());
  const d = rowsToDaily([
    { day: 'garbage', seconds: 10 },
    null,
    { day: '2026-09-15T00:00:00+00:00', seconds: -5, steps: 3.9, completed: 1 },
    { day: '2026-09-16', seconds: 120, steps: 6, completed: true },
  ]);
  assert.equal(Object.keys(d.days).length, 2);
  // A timestamp column still resolves to its calendar day.
  assert.deepEqual(d.days['2026-09-15'], {
    seconds: 0,
    steps: 3,
    completed: false,
  });
  assert.deepEqual(d.days['2026-09-16'], {
    seconds: 120,
    steps: 6,
    completed: true,
  });
});

test('a calendar survives a round trip through rows', () => {
  let d = logComplete(logStep(emptyDaily(), 90, '2026-09-16', 1), '2026-09-16', 2);
  d = logStep(d, 45, '2026-09-15', 3);
  const back = rowsToDaily(dailyToRows(d));
  assert.deepEqual(back.days, d.days);
});

test('merging never loses practice and never double-counts it', () => {
  const laptop = logComplete(
    logStep(emptyDaily(), 600, '2026-09-16', 1),
    '2026-09-16',
    1,
  );
  const phone = logStep(logStep(emptyDaily(), 200, '2026-09-16', 2), 300, '2026-09-15', 2);
  const merged = mergeDaily(laptop, phone);
  // The fuller record of a shared day wins; it is not summed.
  assert.equal(merged.days['2026-09-16'].seconds, 600);
  assert.equal(merged.days['2026-09-16'].completed, true);
  // A day only one device knows about is carried over.
  assert.equal(merged.days['2026-09-15'].seconds, 300);
  // Commutative, and idempotent however many times it runs.
  assert.deepEqual(mergeDaily(phone, laptop).days, merged.days);
  assert.deepEqual(mergeDaily(merged, merged).days, merged.days);
  assert.deepEqual(mergeDaily(merged, laptop).days, merged.days);
});

test('a finished day stays finished after a merge from a device that missed it', () => {
  const done = logComplete(emptyDaily(), '2026-09-16', 1);
  const partial = logStep(emptyDaily(), 30, '2026-09-16', 1);
  assert.equal(mergeDaily(partial, done).days['2026-09-16'].completed, true);
  assert.equal(mergeDaily(done, partial).days['2026-09-16'].completed, true);
});

test('a push is skipped only when the server already matches', () => {
  const local = logStep(emptyDaily(), 60, '2026-09-16', 1);
  assert.equal(needsPush(emptyDaily(), local), true);
  assert.equal(needsPush(local, local), false);
  assert.equal(needsPush(local, logStep(local, 5, '2026-09-16', 2)), true);
  // Same day count, different contents.
  const other = logStep(emptyDaily(), 60, '2026-09-15', 1);
  assert.equal(needsPush(other, local), true);
});

test('addresses are checked before a send is spent', () => {
  assert.equal(looksLikeEmail('timour@edgecity.live'), true);
  assert.equal(looksLikeEmail('timour@edgecity'), false);
  assert.equal(looksLikeEmail('not an email'), false);
});

test('auth failures are translated into something a singer can act on', () => {
  const m = (message) => authMessage({ message });
  assert.match(m('Failed to fetch'), /Could not reach the server/);
  assert.match(m('TypeError: NetworkError when attempting to fetch'), /connection/);
  assert.match(m('email rate limit exceeded'), /Wait a minute/);
  assert.match(m('For security purposes, too many requests'), /Wait a minute/);
  assert.match(m('Token has expired or is invalid'), /expired/);
  assert.match(m('Invalid token'), /did not match/);
  assert.equal(m(null), 'Something went wrong. Please try again.');
  assert.equal(m('   '), 'Something went wrong. Please try again.');
  // Anything unrecognised is passed through rather than hidden.
  assert.equal(m('Signups not allowed for otp'), 'Signups not allowed for otp');
});
