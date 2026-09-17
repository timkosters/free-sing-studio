// The daily practice routine: a fixed, ordered set of steps with a clock.
// The order is how a lesson actually runs: free the body, settle the breath,
// close the cords, cross the register break, then apply it to a song. Every
// step carries the reason it exists, so the routine explains itself rather
// than asking to be trusted.
// Everything here is pure so the routine and streak maths can be unit-tested.

/** How a step uses the audio engine. */
export type StepEngine =
  /** Instruction and timer only. No microphone requested. */
  | 'none'
  /** Live pitch display with the piano roll. */
  | 'mic'
  /** Live pitch plus a steadiness meter over one held note. */
  | 'hold'
  /** A breathing pacer with an expand/hold/release ring. */
  | 'breath';

export type Step = {
  id: string;
  title: string;
  /** One line telling you what to do right now. */
  cue: string;
  /** Short, concrete lines shown while the step runs. */
  detail: string[];
  /** Why this step is in the routine, shown small. */
  source: string;
  seconds: number;
  engine: StepEngine;
  /** For 'hold' steps: the suggested note to sit on, as a MIDI number. */
  hold?: number;
  /** For 'breath' steps: inhale / hold / exhale seconds per cycle. */
  breath?: [number, number, number];
};

export type RoutineId = 'quick' | 'full' | 'bridge';

export type Routine = {
  id: RoutineId;
  label: string;
  /** What this routine is for, in one line. */
  blurb: string;
  steps: Step[];
};

// ---------------------------------------------------------------------------
// Step library
// ---------------------------------------------------------------------------

const WAKE: Step = {
  id: 'wake',
  title: 'Wake the body up',
  cue: 'Loosen the jaw, face and shoulders before any sound.',
  detail: [
    'Massage the jaw hinge with your fingertips, then let the jaw hang open.',
    'Roll the shoulders back and drop them. Knees loose, not locked.',
    'Smile wide, then pucker. Repeat. Tongue side to side.',
    'Chin level. Feet apart, weight even, chest high.',
  ],
  source: 'Tension in the jaw and shoulders shows up in the sound',
  seconds: 90,
  engine: 'none',
};

const BELLY: Step = {
  id: 'belly',
  title: 'Belly breath',
  cue: 'Sharp inhale into the stomach. Chest stays still.',
  detail: [
    'Hand on the belly, hand on the chest. Only the lower hand moves.',
    'Sharp inhale, hold the expansion, then count out loud to 15.',
    'Take a small top-up breath between each number.',
    'Neck and throat stay free the whole time.',
  ],
  source: 'Breathing into the chest is what tightens the throat',
  seconds: 150,
  engine: 'breath',
  breath: [3, 2, 9],
};

const LADDER: Step = {
  id: 'ladder',
  title: 'Breath control ladder',
  cue: 'Thin, even stream. Imagine breathing out through a straw.',
  detail: [
    'Hiss on "sss" for a slow count of 10. Then "fff". Then voiced "zzz".',
    'Then the ratios: in 3 out 9, in 4 out 12, in 5 out 15, in 6 out 18.',
    'The stream stays even. No collapse at the end.',
    'Finish on a humming glide, low to high and back.',
  ],
  source: 'Steady air is what keeps a long phrase supported',
  seconds: 150,
  engine: 'none',
};

const TWISTERS: Step = {
  id: 'twisters',
  title: 'Diction',
  cue: 'Straw between the teeth. Over-articulate, then drop the straw.',
  detail: [
    'Peter Piper picked a peck of pickled peppers.',
    'Betty Botter bought some butter, but she said the butter’s bitter.',
    'How much wood would a woodchuck chuck.',
    'Last round with nothing in your mouth: fast and clear.',
  ],
  source: 'Consonants are the first thing a microphone loses',
  seconds: 90,
  engine: 'none',
};

const SIREN: Step = {
  id: 'siren',
  title: 'Lip trill siren',
  cue: 'Trill low to high to low. Let the break pass through untouched.',
  detail: [
    'Lips loose and buzzing. If they stall, press the cheeks in lightly.',
    'Slide up through your whole range and back down. Four passes.',
    'Do not stop or push where it wants to change gear. Glide through it.',
    'Watch the trail: you want one smooth line, not a step.',
  ],
  source: 'Warms the voice and crosses the break without strain',
  seconds: 90,
  engine: 'mic',
};

const GOO: Step = {
  id: 'goo',
  title: '"Goo" — close the cords',
  cue: 'The main event. "Goo" on a descending five-note run, up a semitone each time.',
  detail: [
    'The hard "g" snaps the cords together. That is the point.',
    'Sing goo-oo-oo-oo-oo down 5-4-3-2-1, then start a semitone higher.',
    'Aim for a clean, buzzy tone. No air leaking around the note.',
    'If it turns breathy, come back down and restart lower.',
  ],
  source: 'A breathy tone usually means the cords are not quite meeting',
  seconds: 180,
  engine: 'mic',
};

const OO: Step = {
  id: 'oo',
  title: 'Sustained "oo"',
  cue: 'One note. Hold it dead steady for as long as the breath lasts.',
  detail: [
    'Pick a comfortable note in the middle. Sing "oo" and hold.',
    'No wobble, no fade, no breath escaping. Straight line.',
    'Rest, then repeat a tone higher.',
    'The meter shows how steady you actually are.',
  ],
  source: 'A held note is where wobble and escaping air become obvious',
  seconds: 120,
  engine: 'hold',
  hold: 60,
};

const BRIDGE: Step = {
  id: 'bridge',
  title: 'The bridge — chest into head',
  cue: 'Slide up through the place your voice wants to flip. Glide. Never jump.',
  detail: [
    'Find your break first: siren slowly until the tone wants to change gear.',
    'Start below it in chest, slide up through it, keep going into head voice.',
    'Mouth stays open. Do not brace or anticipate the note before it arrives.',
    'If it cracks, go slower and quieter, not louder. Then slide back down.',
  ],
  source: 'The gap between chest and head voice is the slowest thing to build',
  seconds: 180,
  engine: 'mic',
};

const HARD_LINE: Step = {
  id: 'hard-line',
  title: 'Your hardest line',
  cue: 'One phrase. The one that keeps going wrong. On loop.',
  detail: [
    'Pick the bar that defeats you, usually the one sitting on your break.',
    'Take it quieter and slower than feels right. Louder never fixes a break.',
    'Head neutral. Do not crane upward for the high note; move side to side.',
    'Lead the sound forward. Do not land heavily on each syllable.',
  ],
  source: 'One hard bar, repeated, beats another run at the whole song',
  seconds: 180,
  engine: 'mic',
};

const NOI: Step = {
  id: 'noi',
  title: 'Low notes forward — "noi"',
  cue: 'Down to the bottom of your range. Bring it forward, do not swallow it.',
  detail: [
    'Sing "noi" on a descending run into your low range.',
    'Keep the sound at the front of the face, not in the throat.',
    'A gentle yawn shape before you start opens the space.',
    'Go one semitone lower than you think you have. It is usually there.',
  ],
  source: 'Low notes get swallowed long before they actually run out',
  seconds: 90,
  engine: 'mic',
};

const SONG: Step = {
  id: 'song',
  title: 'Song of the day',
  cue: 'One section. Not the whole song.',
  detail: [
    'Whatever you are working on. One song, not a playlist.',
    'Take one or two lines. Belly breath before each phrase.',
    'Repeat the section rather than running the whole thing.',
    'Record a take. In a few weeks you get to compare honestly.',
  ],
  source: 'Sections build a song; run-throughs rehearse the mistakes',
  seconds: 240,
  engine: 'mic',
};

// ---------------------------------------------------------------------------
// Routines
// ---------------------------------------------------------------------------

/** Same drill, shorter or longer, so one step can serve a 10-minute and a 20-minute day. */
const at = (step: Step, seconds: number): Step => ({ ...step, seconds });

export const ROUTINES: Routine[] = [
  {
    id: 'quick',
    label: 'Quick',
    blurb: 'The irreducible ten minutes. Breath, cords, bridge.',
    steps: [
      at(WAKE, 60),
      at(BELLY, 120),
      at(SIREN, 60),
      at(GOO, 150),
      at(BRIDGE, 120),
      at(SONG, 120),
    ],
  },
  {
    id: 'full',
    label: 'Full',
    blurb: 'Everything, in the order a lesson runs it.',
    steps: [
      at(WAKE, 60),
      at(BELLY, 120),
      at(LADDER, 120),
      at(TWISTERS, 60),
      at(SIREN, 60),
      at(GOO, 150),
      at(OO, 90),
      at(BRIDGE, 150),
      at(HARD_LINE, 120),
      at(NOI, 90),
      at(SONG, 150),
    ],
  },
  {
    id: 'bridge',
    label: 'Bridge focus',
    blurb: 'All in on the chest-to-head transition.',
    steps: [
      at(WAKE, 60),
      at(BELLY, 90),
      at(SIREN, 60),
      at(GOO, 120),
      at(BRIDGE, 180),
      at(HARD_LINE, 150),
      at(OO, 90),
      at(BRIDGE, 120),
    ],
  },
];

export const routineById = (id: string): Routine =>
  ROUTINES.find((r) => r.id === id) ?? ROUTINES[0];

/** Total length of a routine in seconds. */
export const routineSeconds = (r: Routine) =>
  r.steps.reduce((total, s) => total + s.seconds, 0);

/** "18 min" style label for a routine. */
export const routineLength = (r: Routine) =>
  `${Math.round(routineSeconds(r) / 60)} min`;

/**
 * Steps can repeat inside a routine (Bridge focus runs the bridge twice), so
 * the React key and the completion record need the position, not just the id.
 */
export const stepKey = (step: Step, index: number) => `${index}:${step.id}`;

// ---------------------------------------------------------------------------
// Daily log
// ---------------------------------------------------------------------------

export const DAILY_KEY = 'free-sing-daily-v1';

export type Day = {
  /** Seconds of routine actually practised that day. */
  seconds: number;
  /** Number of steps finished, across every session that day. */
  steps: number;
  /** True once any routine was played to the end. */
  completed: boolean;
};

export type Daily = {
  version: 1;
  days: Record<string, Day>;
  updated: number;
};

export const emptyDaily = (): Daily => ({ version: 1, days: {}, updated: 0 });

/** Local calendar day as YYYY-MM-DD. Local, not UTC, so "today" means today here. */
export function dayKey(date: Date = new Date()): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

/** Shift a YYYY-MM-DD key by whole days, staying in local time. */
export function shiftDay(key: string, days: number): string {
  const [y, m, d] = key.split('-').map(Number);
  return dayKey(new Date(y, (m ?? 1) - 1, (d ?? 1) + days));
}

const KEY_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const nonNegative = (v: unknown) =>
  typeof v === 'number' && Number.isFinite(v) && v > 0 ? v : 0;

/** Parse stored JSON defensively. Anything malformed falls back to a clean slate. */
export function parseDaily(raw: string | null | undefined): Daily {
  if (!raw) return emptyDaily();
  try {
    const data: unknown = JSON.parse(raw);
    if (!data || typeof data !== 'object') return emptyDaily();
    const d = data as Record<string, unknown>;
    if (d.version !== undefined && d.version !== 1) return emptyDaily();
    const source =
      d.days && typeof d.days === 'object'
        ? (d.days as Record<string, unknown>)
        : {};
    const days: Record<string, Day> = {};
    for (const [key, value] of Object.entries(source)) {
      if (!KEY_PATTERN.test(key) || !value || typeof value !== 'object')
        continue;
      const v = value as Record<string, unknown>;
      days[key] = {
        seconds: nonNegative(v.seconds),
        steps: Math.floor(nonNegative(v.steps)),
        completed: v.completed === true,
      };
    }
    return { version: 1, days, updated: nonNegative(d.updated) };
  } catch {
    return emptyDaily();
  }
}

export const serializeDaily = (d: Daily) => JSON.stringify(d);

/** Fold one finished step into today's record. */
export function logStep(
  daily: Daily,
  seconds: number,
  key: string,
  now: number,
): Daily {
  const add = nonNegative(seconds);
  const day = daily.days[key] ?? { seconds: 0, steps: 0, completed: false };
  return {
    ...daily,
    updated: now,
    days: {
      ...daily.days,
      [key]: { ...day, seconds: day.seconds + add, steps: day.steps + 1 },
    },
  };
}

/** Mark today as a finished routine. */
export function logComplete(daily: Daily, key: string, now: number): Daily {
  const day = daily.days[key] ?? { seconds: 0, steps: 0, completed: false };
  return {
    ...daily,
    updated: now,
    days: { ...daily.days, [key]: { ...day, completed: true } },
  };
}

/** A day counts towards a streak once anything at all was practised. */
const practised = (daily: Daily, key: string) => {
  const day = daily.days[key];
  return day !== undefined && (day.seconds > 0 || day.steps > 0);
};

/**
 * Consecutive practised days ending today, or ending yesterday if today is
 * still untouched. A streak is only broken once a whole day has been missed,
 * so an unpractised today shows yesterday's streak rather than zero.
 */
export function streak(daily: Daily, today: string = dayKey()): number {
  let cursor = practised(daily, today) ? today : shiftDay(today, -1);
  if (!practised(daily, cursor)) return 0;
  let count = 0;
  while (practised(daily, cursor) && count < 4000) {
    count++;
    cursor = shiftDay(cursor, -1);
  }
  return count;
}

/** Longest run of consecutive practised days ever recorded. */
export function bestStreak(daily: Daily): number {
  const keys = Object.keys(daily.days)
    .filter((k) => practised(daily, k))
    .sort();
  let best = 0,
    run = 0,
    previous = '';
  for (const key of keys) {
    run = previous && shiftDay(previous, 1) === key ? run + 1 : 1;
    previous = key;
    if (run > best) best = run;
  }
  return best;
}

/** Total days practised, ever. */
export const totalDays = (daily: Daily) =>
  Object.keys(daily.days).filter((k) => practised(daily, k)).length;

/** Total seconds practised, ever. */
export const totalSeconds = (daily: Daily) =>
  Object.values(daily.days).reduce((sum, d) => sum + d.seconds, 0);

/** The last `count` days, oldest first, for the calendar strip. */
export function recentDays(
  daily: Daily,
  count: number,
  today: string = dayKey(),
): { key: string; day: Day | null }[] {
  const out: { key: string; day: Day | null }[] = [];
  for (let i = count - 1; i >= 0; i--) {
    const key = shiftDay(today, -i);
    out.push({ key, day: daily.days[key] ?? null });
  }
  return out;
}
