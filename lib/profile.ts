// What the routine knows about one particular voice.
//
// The shipped routine is deliberately generic: everybody's register break sits
// somewhere different, and pinning the bridge exercise to one singer's notes
// makes it wrong for every other singer, especially higher voices. A profile
// lives in that singer's own account and is folded into the step text at
// render time, so the app stays general and the practice gets specific.
//
// Everything here is pure, so the personalisation can be unit-tested without a
// network, and an empty profile always falls back to the generic wording.

import { noteName } from './pitch.ts';
import type { Step } from './daily.ts';

export type Profile = {
  /** Comfortable range, as MIDI note numbers. */
  low: number | null;
  high: number | null;
  /** The passaggio: where chest voice starts handing over to head voice. */
  breakLow: number | null;
  breakHigh: number | null;
  /** Songs being worked on, and the one phrase worth looping. */
  songs: string[];
  hardLine: string | null;
};

export const emptyProfile = (): Profile => ({
  low: null,
  high: null,
  breakLow: null,
  breakHigh: null,
  songs: [],
  hardLine: null,
});

/** True when the profile has nothing to say and the generic routine applies. */
export const profileIsEmpty = (p: Profile) =>
  p.low === null &&
  p.high === null &&
  p.breakLow === null &&
  p.breakHigh === null &&
  p.songs.length === 0 &&
  p.hardLine === null;

const NOTE_MIN = 24,
  NOTE_MAX = 96;

const note = (v: unknown): number | null => {
  if (typeof v !== 'number' || !Number.isFinite(v)) return null;
  const n = Math.round(v);
  return n >= NOTE_MIN && n <= NOTE_MAX ? n : null;
};

const text = (v: unknown, max: number): string | null => {
  if (typeof v !== 'string') return null;
  const t = v.trim().slice(0, max);
  return t.length ? t : null;
};

/** Order a pair, tolerating either arrangement or a half-filled one. */
const ordered = (a: number | null, b: number | null): [number | null, number | null] =>
  a !== null && b !== null ? [Math.min(a, b), Math.max(a, b)] : [a, b];

/**
 * Build a profile from a server row. The row is remote data, so every field is
 * range-checked and anything unusable becomes null rather than reaching the UI.
 */
export function rowToProfile(row: unknown): Profile {
  if (!row || typeof row !== 'object') return emptyProfile();
  const r = row as Record<string, unknown>;
  const [low, high] = ordered(note(r.low_note), note(r.high_note));
  const [breakLow, breakHigh] = ordered(note(r.break_low), note(r.break_high));
  const songs = Array.isArray(r.songs)
    ? r.songs
        .map((s) => text(s, 80))
        .filter((s): s is string => s !== null)
        .slice(0, 12)
    : [];
  return { low, high, breakLow, breakHigh, songs, hardLine: text(r.hard_line, 200) };
}

/** The row to write back, using the column names the table declares. */
export const profileToRow = (p: Profile) => ({
  low_note: p.low,
  high_note: p.high,
  break_low: p.breakLow,
  break_high: p.breakHigh,
  songs: p.songs,
  hard_line: p.hardLine,
});

/** Join a list the way a sentence would: "a, b or c". */
const orList = (items: string[]) =>
  items.length <= 1
    ? (items[0] ?? '')
    : `${items.slice(0, -1).join(', ')} or ${items[items.length - 1]}`;

/**
 * Fold what we know about this voice into one step's wording.
 *
 * Only the lines that a profile can genuinely improve are replaced, and only
 * when the relevant field is filled: a half-filled profile personalises the
 * half it can and leaves the rest exactly as shipped.
 */
export function personalizeStep(step: Step, profile: Profile): Step {
  switch (step.id) {
    case 'bridge': {
      if (profile.breakLow === null || profile.breakHigh === null) return step;
      const from = noteName(profile.breakLow),
        to = noteName(profile.breakHigh);
      const below = noteName(Math.max(NOTE_MIN, profile.breakLow - 3));
      return {
        ...step,
        cue: `Slide from ${below} up through ${from}–${to} and into head voice. Glide. Never jump.`,
        detail: [
          `Your break sits around ${from} to ${to}. Start below it, in chest.`,
          'Slide up through it without stopping, and keep going into head voice.',
          'Mouth stays open. Do not brace or anticipate the note before it arrives.',
          'If it cracks, go slower and quieter, not louder. Then slide back down.',
        ],
      };
    }
    case 'hard-line': {
      if (profile.hardLine === null) return step;
      return {
        ...step,
        cue: `"${profile.hardLine}" On loop.`,
        detail: [
          'This is the line you marked as the one that keeps going wrong.',
          'Take it quieter and slower than feels right. Louder never fixes a break.',
          'Head neutral. Do not crane upward for the high note; move side to side.',
          'Lead the sound forward. Do not land heavily on each syllable.',
        ],
      };
    }
    case 'noi': {
      if (profile.low === null) return step;
      const lowest = noteName(profile.low);
      const reach = noteName(Math.max(NOTE_MIN, profile.low - 1));
      return {
        ...step,
        detail: [
          'Sing "noi" on a descending run into your low range.',
          'Keep the sound at the front of the face, not in the throat.',
          'A gentle yawn shape before you start opens the space.',
          `Your lowest tracked note is ${lowest}. Go for ${reach} today.`,
        ],
      };
    }
    case 'song': {
      if (profile.songs.length === 0) return step;
      return {
        ...step,
        detail: [
          `${orList(profile.songs)}. Pick one.`,
          'Take one or two lines. Belly breath before each phrase.',
          'Repeat the section rather than running the whole thing.',
          'Record a take. In a few weeks you get to compare honestly.',
        ],
      };
    }
    default:
      return step;
  }
}

/** Apply a profile across a whole routine. */
export const personalizeSteps = (steps: Step[], profile: Profile): Step[] =>
  profileIsEmpty(profile) ? steps : steps.map((s) => personalizeStep(s, profile));
