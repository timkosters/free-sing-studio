// Session range map and local-only practice history.
// Only sustained detected notes count towards the range, so a cough, a slide
// or brief detector glitch is filtered. Sustained octave errors remain possible.
// Nothing here touches the network.

export const HISTORY_KEY = 'free-sing-history-v1';
/** A note must be held this long (seconds) before it counts as observed. */
export const SUSTAIN_SECONDS = 0.5;

export type SustainState = {
  candidate: number | null;
  since: number;
  lastSample: number;
  low: number | null;
  high: number | null;
};

export const emptySustain = (): SustainState => ({
  candidate: null,
  since: 0,
  lastSample: 0,
  low: null,
  high: null,
});

/**
 * Feed one detected pitch sample. The nearest semitone becomes a candidate;
 * once the same semitone has been present for SUSTAIN_SECONDS it widens the
 * observed low/high. Silence or a different note restarts the candidate clock.
 */
export function trackSustained(
  state: SustainState,
  midi: number | null,
  now: number,
): SustainState {
  if (midi === null || !Number.isFinite(midi))
    return state.candidate === null ? state : { ...state, candidate: null };
  const note = Math.round(midi);
  if (
    note !== state.candidate ||
    now - state.lastSample > 1 ||
    now < state.lastSample
  )
    return { ...state, candidate: note, since: now, lastSample: now };
  if (now - state.since < SUSTAIN_SECONDS) return { ...state, lastSample: now };
  const low = state.low === null ? note : Math.min(state.low, note),
    high = state.high === null ? note : Math.max(state.high, note);
  return { ...state, low, high, lastSample: now };
}

export type QuestBests = {
  runs: number;
  /** Most targets matched in a single quest. */
  mostMatched: number;
  /** Quickest average seconds per matched target across a fully matched run. */
  quickestAverage: number | null;
  /** Widest low/high pair of matched targets in a single quest. */
  widestLow: number | null;
  widestHigh: number | null;
};

export type History = {
  version: 1;
  seconds: number;
  sessions: number;
  low: number | null;
  high: number | null;
  quest: QuestBests;
  updated: number;
};

export const emptyHistory = (): History => ({
  version: 1,
  seconds: 0,
  sessions: 0,
  low: null,
  high: null,
  quest: {
    runs: 0,
    mostMatched: 0,
    quickestAverage: null,
    widestLow: null,
    widestHigh: null,
  },
  updated: 0,
});

const finiteOrNull = (v: unknown) =>
  typeof v === 'number' && Number.isFinite(v) ? v : null;
const nonNegative = (v: unknown) => Math.max(0, finiteOrNull(v) ?? 0);
const validNote = (v: unknown) => {
  const n = finiteOrNull(v);
  return n !== null && n >= 24 && n <= 96 ? Math.round(n) : null;
};

/** Parse stored JSON defensively. Anything malformed falls back to a clean slate. */
export function parseHistory(raw: string | null | undefined): History {
  if (!raw) return emptyHistory();
  try {
    const data: unknown = JSON.parse(raw);
    if (!data || typeof data !== 'object') return emptyHistory();
    const d = data as Record<string, unknown>;
    if (d.version !== undefined && d.version !== 1) return emptyHistory();
    const q = (d.quest && typeof d.quest === 'object' ? d.quest : {}) as Record<
      string,
      unknown
    >;
    const low = validNote(d.low),
      high = validNote(d.high);
    const questLow = validNote(q.widestLow),
      questHigh = validNote(q.widestHigh);
    const quickest = finiteOrNull(q.quickestAverage);
    return {
      version: 1,
      seconds: nonNegative(d.seconds),
      sessions: Math.floor(nonNegative(d.sessions)),
      low: low !== null && high !== null ? Math.min(low, high) : (low ?? high),
      high: low !== null && high !== null ? Math.max(low, high) : (high ?? low),
      quest: {
        runs: Math.floor(nonNegative(q.runs)),
        mostMatched: Math.floor(nonNegative(q.mostMatched)),
        quickestAverage: quickest !== null && quickest >= 1 ? quickest : null,
        widestLow:
          questLow !== null && questHigh !== null
            ? Math.min(questLow, questHigh)
            : null,
        widestHigh:
          questLow !== null && questHigh !== null
            ? Math.max(questLow, questHigh)
            : null,
      },
      updated: nonNegative(d.updated),
    };
  } catch {
    return emptyHistory();
  }
}

export const serializeHistory = (h: History) => JSON.stringify(h);

export function addPracticeSeconds(
  h: History,
  seconds: number,
  now: number,
): History {
  const add = Number.isFinite(seconds) ? Math.max(0, seconds) : 0;
  return add === 0 ? h : { ...h, seconds: h.seconds + add, updated: now };
}

export function recordSession(h: History, now: number): History {
  return { ...h, sessions: h.sessions + 1, updated: now };
}

export function recordRange(
  h: History,
  low: number | null,
  high: number | null,
  now: number,
): History {
  if (low === null || high === null) return h;
  const nextLow = h.low === null ? low : Math.min(h.low, low),
    nextHigh = h.high === null ? high : Math.max(h.high, high);
  return nextLow === h.low && nextHigh === h.high
    ? h
    : { ...h, low: nextLow, high: nextHigh, updated: now };
}

export function recordQuest(
  h: History,
  result: {
    matched: number;
    total: number;
    averageSeconds: number | null;
    low: number | null;
    high: number | null;
  },
  now: number,
): History {
  const q = h.quest;
  const complete = result.total > 0 && result.matched === result.total;
  const quickest =
    complete && result.averageSeconds !== null
      ? q.quickestAverage === null
        ? result.averageSeconds
        : Math.min(q.quickestAverage, result.averageSeconds)
      : q.quickestAverage;
  const span = (lo: number | null, hi: number | null) =>
    lo === null || hi === null ? -1 : hi - lo;
  const wider = span(result.low, result.high) > span(q.widestLow, q.widestHigh);
  return {
    ...h,
    updated: now,
    quest: {
      runs: q.runs + 1,
      mostMatched: Math.max(q.mostMatched, result.matched),
      quickestAverage: quickest,
      widestLow: wider ? result.low : q.widestLow,
      widestHigh: wider ? result.high : q.widestHigh,
    },
  };
}

/** "12 min" style label; under a minute shows seconds so early practice is visible. */
export function formatMinutes(seconds: number) {
  const s = Math.max(0, Math.floor(seconds));
  if (s < 60) return `${s} sec`;
  const minutes = Math.round(s / 60);
  if (minutes < 60) return `${minutes} min`;
  const h = Math.floor(minutes / 60),
    m = minutes % 60;
  return m ? `${h} h ${m} min` : `${h} h`;
}

/** Semitone span between two notes, or null when the range is not yet known. */
export const rangeSpan = (low: number | null, high: number | null) =>
  low === null || high === null ? null : high - low;
