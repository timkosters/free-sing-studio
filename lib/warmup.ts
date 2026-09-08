export type Drill = 'arpeggio' | 'five-note';
export type Beat = {
  time: number;
  midi: number | null;
  root: number;
  round: number;
  label: string;
  accent: boolean;
  phase: 'listen' | 'count' | 'sing' | 'rest';
  noteIndex: number;
  onset: boolean;
};
export function makeWarmup(
  drill: Drill,
  root: number,
  steps: number,
  bpm: number,
): Beat[] {
  if (
    !['arpeggio', 'five-note'].includes(drill) ||
    !Number.isInteger(root) ||
    root < 36 ||
    root > 72 ||
    !Number.isInteger(steps) ||
    steps < 0 ||
    steps > 12 ||
    bpm < 50 ||
    bpm > 140 ||
    !Number.isFinite(bpm)
  )
    throw new Error('Invalid warm-up settings');
  const pattern =
    drill === 'arpeggio' ? [0, 4, 7, 12, 7, 4, 0] : [0, 2, 4, 5, 7, 5, 4, 2, 0];
  const beats: Beat[] = [];
  const duration = 60 / bpm;
  const add = (
    midi: number | null,
    r: number,
    round: number,
    label: string,
    accent: boolean,
    phase: Beat['phase'],
    noteIndex = -1,
    onset = true,
  ) =>
    beats.push({
      time: beats.length * duration,
      midi,
      root: r,
      round,
      label,
      accent,
      phase,
      noteIndex,
      onset,
    });
  for (let n = 0; n < 4; n++)
    add(null, root, 1, `Listen in ${4 - n}`, n === 0, 'count');
  for (let s = 0; s <= steps; s++) {
    for (const phase of ['listen', 'sing'] as const) {
      if (phase === 'sing')
        for (let n = 0; n < 4; n++)
          add(null, root + s, s + 1, `Your turn in ${4 - n}`, n === 0, 'count');
      pattern.forEach((offset, i) => {
        for (let hold = 0; hold < 2; hold++)
          add(
            root + s + offset,
            root + s,
            s + 1,
            phase === 'listen' ? 'Listen to the piano' : 'Your turn · sing',
            hold === 0,
            phase,
            i,
            hold === 0,
          );
      });
    }
    for (let n = 0; n < 4; n++)
      add(null, root + s, s + 1, `Breathe · ${4 - n}`, n === 0, 'rest');
  }
  return beats;
}
export type NoteScore = {
  total: number;
  voiced: number;
  hits: number;
  cents: number[];
};
export function scoreSample(
  previous: NoteScore | undefined,
  midi: number | null,
  target: number,
): NoteScore {
  const s = previous || { total: 0, voiced: 0, hits: 0, cents: [] };
  const diff = midi === null ? null : (midi - target) * 100;
  return {
    total: s.total + 1,
    voiced: s.voiced + (diff === null ? 0 : 1),
    hits: s.hits + (diff !== null && Math.abs(diff) <= 50 ? 1 : 0),
    cents: diff === null ? s.cents : [...s.cents, diff],
  };
}
export function scoreLabel(s: NoteScore | undefined): string {
  if (!s || s.voiced < 3) return 'No clear pitch';
  if (s.hits >= 3 && s.hits / s.total >= 0.5) return 'Hit';
  const sorted = [...s.cents].sort((a, b) => a - b);
  const median = sorted[Math.floor(sorted.length / 2)];
  return median < -50 ? 'Low' : median > 50 ? 'High' : 'Keep steady';
}
export const formatTime = (seconds: number) =>
  `${Math.floor(seconds / 60)}:${String(Math.floor(seconds % 60)).padStart(2, '0')}`;
