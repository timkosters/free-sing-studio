// Optional cross-device sync for the daily practice calendar.
//
// The app is fully usable with no account; signing in only mirrors what is
// already in localStorage. Everything in this file is pure: the merge rules
// and the row mapping are unit-tested without a network or a Supabase client.

import type { Daily, Day } from './daily';

/** One row of the practice_days table. */
export type Row = {
  day: string;
  seconds: number;
  steps: number;
  completed: boolean;
};

const EMPTY = (): Daily => ({ version: 1, days: {}, updated: 0 });

const KEY_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const nonNegative = (v: unknown) =>
  typeof v === 'number' && Number.isFinite(v) && v > 0 ? Math.floor(v) : 0;

/**
 * Fold server rows into a Daily. Rows are remote data, so anything malformed
 * is dropped rather than trusted.
 */
export function rowsToDaily(rows: unknown): Daily {
  if (!Array.isArray(rows)) return EMPTY();
  const days: Record<string, Day> = {};
  for (const row of rows) {
    if (!row || typeof row !== 'object') continue;
    const r = row as Record<string, unknown>;
    const key = typeof r.day === 'string' ? r.day.slice(0, 10) : '';
    if (!KEY_PATTERN.test(key)) continue;
    days[key] = {
      seconds: nonNegative(r.seconds),
      steps: nonNegative(r.steps),
      completed: r.completed === true,
    };
  }
  return { version: 1, days, updated: 0 };
}

/** The rows to write back for a merged calendar. */
export const dailyToRows = (daily: Daily): Row[] =>
  Object.entries(daily.days).map(([day, d]) => ({
    day,
    seconds: Math.floor(d.seconds),
    steps: d.steps,
    completed: d.completed,
  }));

/**
 * Merge two calendars.
 *
 * Practice only ever accumulates, so taking the larger value per field can
 * never lose a session: whichever device saw more of a given day wins, and a
 * day finished anywhere counts as finished. The rule is commutative and
 * idempotent, so merging repeatedly, or in either direction, is safe — which
 * is what makes it usable without any conflict resolution or clock trust.
 */
export function mergeDaily(a: Daily, b: Daily): Daily {
  const days: Record<string, Day> = { ...a.days };
  for (const [key, right] of Object.entries(b.days)) {
    const left = days[key];
    days[key] = left
      ? {
          seconds: Math.max(left.seconds, right.seconds),
          steps: Math.max(left.steps, right.steps),
          completed: left.completed || right.completed,
        }
      : right;
  }
  return {
    version: 1,
    days,
    updated: Math.max(a.updated, b.updated),
  };
}

/** True when the merge would change what the server already holds. */
export function needsPush(remote: Daily, merged: Daily): boolean {
  const keys = Object.keys(merged.days);
  if (keys.length !== Object.keys(remote.days).length) return true;
  return keys.some((key) => {
    const r = remote.days[key],
      m = merged.days[key];
    return (
      !r ||
      r.seconds !== m.seconds ||
      r.steps !== m.steps ||
      r.completed !== m.completed
    );
  });
}

/** A six-digit email code, as Supabase sends it. */
export const isOtpCode = (value: string) => /^\d{6}$/.test(value.trim());

/** Good enough to catch a typo before spending a send on it. */
export const looksLikeEmail = (value: string) =>
  /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(value.trim());

/**
 * Supabase reports rate limits, expired codes and offline failures as plain
 * strings. Translate the ones worth acting on into something a singer can read
 * and act on, and pass anything unexpected through rather than swallowing it.
 */
export function authMessage(error: { message?: string } | null): string {
  const raw = error?.message?.trim();
  if (!raw) return 'Something went wrong. Please try again.';
  const text = raw.toLowerCase();
  if (text.includes('failed to fetch') || text.includes('networkerror'))
    return 'Could not reach the server. Check your connection and try again.';
  if (text.includes('rate limit') || text.includes('too many'))
    return 'Too many codes requested. Wait a minute, then try again.';
  if (text.includes('expired')) return 'That code has expired. Send a new one.';
  if (text.includes('invalid') && text.includes('token'))
    return 'That code did not match. Check it and try again.';
  return raw;
}
