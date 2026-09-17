'use client';
import { useEffect, useRef, useState, type CSSProperties } from 'react';
import {
  Mic,
  Square,
  Circle,
  Play,
  Download,
  AudioLines,
  ArrowLeft,
  Target,
  Music,
  ListMusic,
  Ruler,
  Sparkles,
  RotateCcw,
  SkipForward,
  Volume2,
  Code,
  X,
  Trash2,
  Flame,
  Pause,
  Check,
  Wind,
  CalendarDays,
  ChevronLeft,
  ChevronRight,
  CloudCheck,
  LogOut,
  Loader,
} from 'lucide-react';
import {
  detectPitch,
  frequencyToMidi,
  midiToFrequency,
  noteName,
} from '@/lib/pitch';
import {
  makeWarmup,
  formatTime,
  scoreSample,
  scoreLabel,
  type NoteScore,
  type Beat,
  type Drill,
} from '@/lib/warmup';
import {
  QUEST_LOWEST,
  QUEST_HIGHEST,
  QUEST_COUNTS,
  normalizeQuestRange,
  makeQuestTargets,
  isOnTarget,
  startQuestRun,
  questSample,
  skipTarget,
  questFinished,
  currentTarget,
  summarizeQuest,
  questVerdict,
  type QuestRun,
  type QuestSummary,
} from '@/lib/quest';
import {
  HISTORY_KEY,
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
  type History,
  type SustainState,
} from '@/lib/history';
import {
  ROUTINES,
  DAILY_KEY,
  routineById,
  routineLength,
  stepKey,
  emptyDaily,
  parseDaily,
  serializeDaily,
  dayKey,
  logStep,
  logComplete,
  streak,
  bestStreak,
  totalDays,
  totalSeconds,
  recentDays,
  type Daily,
  type Routine,
  type RoutineId,
  type Step,
} from '@/lib/daily';
import {
  rowsToDaily,
  dailyToRows,
  mergeDaily,
  needsPush,
  looksLikeEmail,
  authMessage,
} from '@/lib/sync';
import {
  supabase,
  syncConfigured,
  hasStoredSession,
  hasAuthCallback,
  clearAuthCallback,
  PRACTICE_TABLE,
  PROFILE_TABLE,
} from '@/lib/supabase';
import {
  PANELS,
  ONBOARDING_KEY,
  shouldOnboard,
  markOnboarded,
} from '@/lib/onboarding';
import {
  emptyProfile,
  profileIsEmpty,
  rowToProfile,
  profileToRow,
  personalizeSteps,
  type Profile,
} from '@/lib/profile';
import { syntheticVoice, demoFreeSample } from '@/lib/demo';
import './free-sing.css';

type Frame = { t: number; midi: number | null; target: number | null };
type Take = {
  id: number;
  url: string;
  extension: string;
  duration: number;
  frames: Frame[];
};
type Recording = {
  recorder: MediaRecorder;
  chunks: Blob[];
  start: number;
  frames: Frame[];
};
type Mode = 'daily' | 'sing' | 'warmups' | 'quest' | 'history';
type DailyRun = {
  routine: Routine;
  index: number;
  /** Seconds left on the current step. */
  left: number;
  playing: boolean;
  /** Seconds of this routine already logged, so a replay cannot double-count. */
  logged: number;
};
type QuestLive = {
  run: QuestRun;
  startedAt: number;
  targetSince: number;
  lastSample: number;
  synthetic: boolean;
};
type QuestView = {
  run: QuestRun;
  status: 'running' | 'done';
  synthetic: boolean;
  summary: QuestSummary | null;
  saved: boolean;
};
type DemoDriver = {
  start: number;
  lastTarget: number | null;
  targetSince: number;
};
const MODES: { id: Mode; label: string; icon: typeof Music }[] = [
  { id: 'daily', label: 'Daily practice', icon: Flame },
  { id: 'sing', label: 'Free sing', icon: Music },
  { id: 'warmups', label: 'Warm-ups', icon: ListMusic },
  { id: 'quest', label: 'Pitch Quest', icon: Target },
  { id: 'history', label: 'Range & history', icon: Ruler },
];
const INTRO: Record<Mode, [string, string]> = {
  daily: [
    'Ten minutes. Every day.',
    'A guided routine, one step at a time, on a clock. Short beats occasional.',
  ],
  sing: [
    'Meet your voice.',
    'Sing freely. See the notes. Record a take and listen back.',
  ],
  warmups: [
    'Warm up, gently.',
    'Listen to the piano, then sing it back. Optional, adjustable, at your tempo.',
  ],
  quest: [
    'Pitch Quest.',
    'One target at a time. Match it, hold it for a second, move on.',
  ],
  history: [
    'Your range and practice.',
    'Only sustained notes count. Everything stays on this device.',
  ],
};
const QUEST_SETTINGS_KEY = 'free-sing-quest-v1';
/** Bars in the input meter; at one sample per 70ms this is about a second of sound. */
const METER_BARS = 14;
/** The notes a singer can pick from in their profile: E2 up to C6. */
const NOTE_CHOICES = Array.from({ length: 45 }, (_, i) => i + 40);
/** Circumference of the hold ring (r = 52) used for the stroke-dash progress. */
const HOLD_RING = 2 * Math.PI * 52;
const RANGE_MAP_LOW = QUEST_LOWEST - 0.5,
  RANGE_MAP_SPAN = QUEST_HIGHEST - QUEST_LOWEST + 1;
const mapPercent = (midi: number) =>
  ((Math.min(QUEST_HIGHEST, Math.max(QUEST_LOWEST, midi)) - RANGE_MAP_LOW) /
    RANGE_MAP_SPAN) *
  100;
export default function FreeSing({ onBack }: { onBack?: () => void }) {
  const [playedNote, setPlayedNote] = useState<number | null>(null);
  const keyTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [listening, setListening] = useState(false),
    [busy, setBusy] = useState(false),
    [error, setError] = useState('');
  const [pitch, setPitch] = useState<number | null>(null),
    [frames, setFrames] = useState<Frame[]>([]),
    [levels, setLevels] = useState<number[]>(() =>
      Array.from({ length: METER_BARS }, () => 0),
    );
  const [recording, setRecording] = useState(false),
    [recordSeconds, setRecordSeconds] = useState(0),
    [takes, setTakes] = useState<Take[]>([]);
  const [selectedTake, setSelectedTake] = useState<Take | null>(null),
    [playhead, setPlayhead] = useState(0),
    [playing, setPlaying] = useState(false);
  const [follow, setFollow] = useState(true),
    [theme, setTheme] = useState('system');
  const [drill, setDrill] = useState<Drill>('arpeggio'),
    [root, setRoot] = useState(48),
    [steps, setSteps] = useState(4),
    [bpm, setBpm] = useState(60),
    [metronome, setMetronome] = useState(true);
  const [warming, setWarming] = useState(false),
    [warmLabel, setWarmLabel] = useState('Ready'),
    [target, setTarget] = useState<number | null>(null);
  const [mode, setMode] = useState<Mode>('daily');
  const [daily, setDaily] = useState<Daily>(emptyDaily),
    [routineId, setRoutineId] = useState<RoutineId>('quick'),
    [run, setRun] = useState<DailyRun | null>(null),
    [dayDone, setDayDone] = useState(false);
  const dailyRef = useRef<Daily>(emptyDaily()),
    runRef = useRef<DailyRun | null>(null),
    dailyPanel = useRef<HTMLElement | null>(null);
  const [breathSound, setBreathSound] = useState(true);
  const [onboarding, setOnboarding] = useState(false),
    [panel, setPanel] = useState(0);
  const [profile, setProfile] = useState<Profile>(emptyProfile),
    [profileOpen, setProfileOpen] = useState(false),
    [profileSaving, setProfileSaving] = useState(false),
    [profileNote, setProfileNote] = useState('');
  const profileRef = useRef<Profile>(emptyProfile());
  const profileLatest = useRef<() => Promise<void>>(() => Promise.resolve());
  const [account, setAccount] = useState<string | null>(null),
    [syncOpen, setSyncOpen] = useState(false),
    [syncStage, setSyncStage] = useState<'email' | 'sent'>('email'),
    [syncEmail, setSyncEmail] = useState(''),
    [syncBusy, setSyncBusy] = useState(false),
    [syncNote, setSyncNote] = useState(''),
    [syncedAt, setSyncedAt] = useState<number | null>(null);
  const [demo, setDemo] = useState(false),
    [demoRunning, setDemoRunning] = useState(false);
  const [questLow, setQuestLow] = useState(55),
    [questHigh, setQuestHigh] = useState(67),
    [questCount, setQuestCount] = useState<number>(QUEST_COUNTS[1]),
    [questView, setQuestView] = useState<QuestView | null>(null);
  const [history, setHistory] = useState<History>(emptyHistory),
    [sessionRange, setSessionRange] = useState<{
      low: number | null;
      high: number | null;
    }>({ low: null, high: null });
  const ctx = useRef<AudioContext | null>(null),
    stream = useRef<MediaStream | null>(null),
    source = useRef<MediaStreamAudioSourceNode | null>(null),
    analyser = useRef<AnalyserNode | null>(null);
  const micTimer = useRef<ReturnType<typeof setInterval> | null>(null),
    generation = useRef(0),
    mounted = useRef(true),
    pending = useRef(false);
  const rec = useRef<Recording | null>(null),
    urls = useRef<string[]>([]),
    takeCounter = useRef(0);
  const audio = useRef<HTMLAudioElement | null>(null),
    roll = useRef<HTMLDivElement | null>(null);
  const warm = useRef<{
      beats: Beat[];
      start: number;
      scheduled: number;
      duration: number;
      last: number;
      click: boolean;
    } | null>(null),
    warmGeneration = useRef(0),
    nodes = useRef<Set<OscillatorNode>>(new Set());
  const liveTarget = useRef<number | null>(null);
  const referenceUntil = useRef(0);
  const warmPanel = useRef<HTMLElement | null>(null);
  const [warmPlan, setWarmPlan] = useState<Beat[]>([]);
  const [warmView, setWarmView] = useState<{
    beat: Beat;
    progress: number;
  } | null>(null);
  const [scores, setScores] = useState<Record<string, NoteScore>>({});
  const quest = useRef<QuestLive | null>(null),
    questGeneration = useRef(0),
    questPanel = useRef<HTMLElement | null>(null);
  const demoRef = useRef(false),
    demoTimer = useRef<ReturnType<typeof setInterval> | null>(null),
    demoDriver = useRef<DemoDriver | null>(null);
  const historyRef = useRef<History>(emptyHistory()),
    sustain = useRef<SustainState>(emptySustain()),
    practice = useRef<{ start: number; flushed: number } | null>(null),
    sessionCounted = useRef(false);
  async function audioContext() {
    if (!ctx.current || ctx.current.state === 'closed')
      ctx.current = new AudioContext();
    const c = ctx.current;
    await c.resume();
    return c;
  }
  // History is written synchronously so a page hide never loses the last update.
  function updateHistory(change: (h: History) => History) {
    const next = change(historyRef.current);
    if (next === historyRef.current) return;
    historyRef.current = next;
    setHistory(next);
    try {
      localStorage.setItem(HISTORY_KEY, serializeHistory(next));
    } catch {}
  }
  function flushPractice(now: number) {
    const p = practice.current;
    if (!p) return;
    const delta = now - p.flushed;
    p.flushed = now;
    if (delta > 0 && delta < 3600)
      // oxlint-disable-next-line react/react-compiler -- Event or lifecycle timestamp, never sampled during render.
      updateHistory((h) => addPracticeSeconds(h, delta, Date.now()));
  }
  function stopWarmup() {
    if (keyTimer.current) clearTimeout(keyTimer.current);
    setPlayedNote(null);
    warmGeneration.current++;
    warm.current = null;
    for (const n of nodes.current) {
      try {
        n.stop();
      } catch {}
    }
    nodes.current.clear();
    if (!quest.current) {
      liveTarget.current = null;
      setTarget(null);
    }
    setWarming(false);
    setWarmLabel('Ready');
  }
  function endQuest() {
    const q = quest.current;
    if (!q) return;
    quest.current = null;
    questGeneration.current++;
    liveTarget.current = null;
    setTarget(null);
    const summary = summarizeQuest(q.run);
    const saved = !q.synthetic && (questFinished(q.run) || summary.matched > 0);
    // oxlint-disable-next-line react/react-compiler -- Event or lifecycle timestamp, never sampled during render.
    if (saved) updateHistory((h) => recordQuest(h, summary, Date.now()));
    setQuestView({
      run: q.run,
      status: 'done',
      synthetic: q.synthetic,
      summary,
      saved,
    });
  }
  function finishRecording() {
    const r = rec.current;
    if (r && r.recorder.state !== 'inactive') r.recorder.stop();
    setRecording(false);
  }
  function stopListening() {
    questGeneration.current++;
    warmGeneration.current++;
    if (warm.current) stopWarmup();
    if (quest.current) endQuest();
    generation.current++;
    pending.current = false;
    finishRecording();
    stream.current?.getTracks().forEach((t) => t.stop());
    stream.current = null;
    source.current?.disconnect();
    source.current = null;
    analyser.current?.disconnect();
    analyser.current = null;
    if (micTimer.current) clearInterval(micTimer.current);
    micTimer.current = null;
    // oxlint-disable-next-line react/react-compiler -- Event or lifecycle timestamp, never sampled during render.
    flushPractice(performance.now() / 1000);
    practice.current = null;
    setListening(false);
    setBusy(false);
    setPitch(null);
    setLevels(Array.from({ length: METER_BARS }, () => 0));
  }
  // Shared by the microphone and the synthetic demo voice. Only real input
  // feeds the range map and history; the synthetic flag keeps demo data out.
  function processSample(
    m: number | null,
    now: number,
    lvl: number,
    synthetic: boolean,
  ) {
    // Ignore the audible reference and a short tail; demo input is independent.
    if (!synthetic && now < referenceUntil.current) m = null;
    setLevels((old) => [...old.slice(1), lvl]);
    const w = warm.current,
      c = ctx.current;
    if (w && c) {
      const elapsed = c.currentTime - w.start;
      const beat = w.beats[Math.floor(elapsed / w.duration)];
      if (beat?.phase === 'sing' && beat.midi !== null) {
        const withinNote = elapsed - beat.time + (beat.onset ? 0 : w.duration);
        if (withinNote >= 0.25) {
          const key = `${beat.round}-${beat.noteIndex}`;
          setScores((old) => ({
            ...old,
            [key]: scoreSample(old[key], m, beat.midi!),
          }));
        }
      }
    }
    const q = quest.current;
    if (q) {
      const dt = Math.min(0.25, Math.max(0, now - q.lastSample));
      q.lastSample = now;
      const { run, advanced } = questSample(q.run, m, dt, now - q.targetSince);
      q.run = run;
      if (advanced) {
        if (questFinished(run)) {
          const last = run.matched.at(-1);
          if (c && last !== undefined) {
            synth(last, c.currentTime, 0.5);
            synth(last + 7, c.currentTime + 0.18, 0.9);
          }
          endQuest();
        } else {
          q.targetSince = now;
          const next = currentTarget(run);
          liveTarget.current = next;
          setTarget(next);
          if (c && next !== null) synth(next, c.currentTime, 1.2);
        }
      }
      if (quest.current)
        setQuestView({
          run,
          status: 'running',
          synthetic: q.synthetic,
          summary: null,
          saved: false,
        });
    }
    if (!synthetic) {
      const previous = sustain.current,
        next = trackSustained(previous, m, now);
      if (next !== previous) {
        sustain.current = next;
        if (next.low !== previous.low || next.high !== previous.high) {
          setSessionRange({ low: next.low, high: next.high });
          // oxlint-disable-next-line react/react-compiler -- Event or lifecycle timestamp, never sampled during render.
          updateHistory((h) => recordRange(h, next.low, next.high, Date.now()));
        }
      }
    }
    setPitch(m);
    const frame = { t: now, midi: m, target: liveTarget.current };
    setFrames((old) => [...old.filter((f) => now - f.t <= 10), frame]);
    return frame;
  }
  async function startListening(): Promise<MediaStream | null> {
    if (stream.current?.active) return stream.current;
    if (pending.current) return null;
    pending.current = true;
    setBusy(true);
    setError('');
    audio.current?.pause();
    setSelectedTake(null);
    setFrames([]);
    setPlayhead(0);
    const token = ++generation.current;
    try {
      if (!navigator.mediaDevices?.getUserMedia)
        throw new Error(
          'Open this site over HTTPS in Chrome, Safari, Firefox or Edge to use the microphone.',
        );
      const c = await audioContext();
      if (token !== generation.current || !mounted.current) return null;
      const s = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: false,
          noiseSuppression: false,
          autoGainControl: false,
        },
        video: false,
      });
      if (token !== generation.current || !mounted.current) {
        s.getTracks().forEach((t) => t.stop());
        return null;
      }
      stream.current = s;
      source.current = c.createMediaStreamSource(s);
      analyser.current = c.createAnalyser();
      analyser.current.fftSize = c.sampleRate > 48000 ? 8192 : 4096;
      source.current.connect(analyser.current);
      const buffer = new Float32Array(analyser.current.fftSize);
      setListening(true);
      // oxlint-disable-next-line react/react-compiler -- Event or lifecycle timestamp, never sampled during render.
      const started = performance.now() / 1000;
      practice.current = { start: started, flushed: started };
      if (!sessionCounted.current) {
        sessionCounted.current = true;
        // oxlint-disable-next-line react/react-compiler -- Event or lifecycle timestamp, never sampled during render.
        updateHistory((h) => recordSession(h, Date.now()));
      }
      micTimer.current = setInterval(() => {
        if (token !== generation.current || !analyser.current) return;
        analyser.current.getFloatTimeDomainData(buffer);
        let sum = 0;
        for (const v of buffer) sum += v * v;
        const result = detectPitch(buffer, c.sampleRate),
          m = result ? frequencyToMidi(result.frequency) : null,
          // oxlint-disable-next-line react/react-compiler -- Event or lifecycle timestamp, never sampled during render.
          now = performance.now() / 1000;
        const frame = processSample(
          m,
          now,
          Math.min(1, Math.sqrt(sum / buffer.length) * 8),
          false,
        );
        if (practice.current && now - practice.current.flushed >= 30)
          flushPractice(now);
        const r = rec.current;
        if (r && r.recorder.state === 'recording') {
          r.frames.push({ ...frame, t: now - r.start });
          setRecordSeconds(now - r.start);
          if (now - r.start >= 600) {
            finishRecording();
            setError(
              'Your 10-minute take is ready. Listening continues; start another take whenever you like.',
            );
          }
        }
      }, 70);
      s.getAudioTracks()[0].onended = () => {
        if (mounted.current) {
          stopListening();
          setError(
            'The microphone disconnected. Reconnect it, then press Start listening.',
          );
        }
      };
      return s;
    } catch (e) {
      if (token === generation.current && mounted.current) {
        stopListening();
        setError(
          e instanceof Error
            ? e.name === 'NotAllowedError'
              ? 'Microphone access was blocked. Allow it in your browser’s site settings, then try again.'
              : e.message
            : 'Could not access microphone.',
        );
      }
      return null;
    } finally {
      if (token === generation.current && mounted.current) {
        pending.current = false;
        setBusy(false);
      }
    }
  }
  // Demo voice: a synthetic singer that follows whatever target is live.
  // It never opens the microphone, never records and never writes history.
  function startDemoVoice(): boolean {
    if (demoTimer.current) return true;
    audio.current?.pause();
    setSelectedTake(null);
    setFrames([]);
    setPlayhead(0);
    setError('');
    // oxlint-disable-next-line react/react-compiler -- Event or lifecycle timestamp, never sampled during render.
    const start = performance.now() / 1000;
    demoDriver.current = { start, lastTarget: null, targetSince: start };
    setDemoRunning(true);
    void audioContext().catch(() => {});
    demoTimer.current = setInterval(() => {
      const d = demoDriver.current;
      if (!d) return;
      // oxlint-disable-next-line react/react-compiler -- Event or lifecycle timestamp, never sampled during render.
      const now = performance.now() / 1000;
      const live = liveTarget.current;
      let sample;
      if (live !== null) {
        if (live !== d.lastTarget) {
          d.lastTarget = live;
          d.targetSince = now;
        }
        sample = syntheticVoice(now - d.targetSince, live, now - d.start);
      } else {
        d.lastTarget = null;
        sample =
          warm.current || quest.current
            ? { midi: null, level: 0.05 }
            : demoFreeSample(now - d.start);
      }
      processSample(sample.midi, now, sample.level, true);
    }, 70);
    return true;
  }
  function stopDemoVoice() {
    questGeneration.current++;
    warmGeneration.current++;
    if (warm.current) stopWarmup();
    if (quest.current) endQuest();
    if (demoTimer.current) clearInterval(demoTimer.current);
    demoTimer.current = null;
    demoDriver.current = null;
    setDemoRunning(false);
    setPitch(null);
    setLevels(Array.from({ length: METER_BARS }, () => 0));
  }
  async function ensureInput(): Promise<boolean> {
    if (demoRef.current) return startDemoVoice();
    return !!(await startListening());
  }
  function stopInput() {
    if (demoRef.current) stopDemoVoice();
    else stopListening();
  }
  function enterDemo() {
    finishRecording();
    stopListening();
    audio.current?.pause();
    setSelectedTake(null);
    setPlayhead(0);
    setFrames([]);
    setError('');
    setQuestView(null);
    setWarmView(null);
    setScores({});
    demoRef.current = true;
    setDemo(true);
    startDemoVoice();
  }
  function exitDemo() {
    stopDemoVoice();
    demoRef.current = false;
    setDemo(false);
    setFrames([]);
    setQuestView(null);
    setWarmView(null);
    setScores({});
    setError('');
  }
  function switchMode(next: Mode) {
    if (next === mode) return;
    questGeneration.current++;
    warmGeneration.current++;
    if (warm.current) stopWarmup();
    if (quest.current) endQuest();
    if (runRef.current) stopRoutine();
    setMode(next);
  }
  async function startRecording() {
    if (rec.current || demoRef.current) return;
    if (typeof MediaRecorder === 'undefined') {
      setError(
        'Recording is unavailable in this browser. You can still use the pitch display.',
      );
      return;
    }
    const s = await startListening();
    if (!s || !s.active || !mounted.current || rec.current) return;
    try {
      const mime = [
        'audio/webm;codecs=opus',
        'audio/mp4',
        'audio/webm',
        'audio/ogg;codecs=opus',
      ].find((type) => MediaRecorder.isTypeSupported(type));
      const recorder = new MediaRecorder(
          s,
          mime ? { mimeType: mime } : undefined,
        ),
        r: Recording = {
          recorder,
          chunks: [],
          // oxlint-disable-next-line react/react-compiler -- Timestamp is sampled only inside the Record click handler, never during render.
          start: performance.now() / 1000,
          frames: [],
        };
      rec.current = r;
      recorder.ondataavailable = (e) => {
        if (e.data.size) r.chunks.push(e.data);
      };
      recorder.onstop = () => {
        if (rec.current === r) rec.current = null;
        if (!mounted.current) return;
        setRecording(false);
        // oxlint-disable-next-line react/react-compiler -- Event or lifecycle timestamp, never sampled during render.
        const duration = performance.now() / 1000 - r.start;
        if (!r.chunks.length) {
          setError('No audio was captured. Please try recording again.');
          return;
        }
        const blob = new Blob(r.chunks, {
            type: recorder.mimeType || mime || 'audio/webm',
          }),
          url = URL.createObjectURL(blob);
        urls.current.push(url);
        const extension = blob.type.includes('mp4')
          ? 'm4a'
          : blob.type.includes('ogg')
            ? 'ogg'
            : 'webm';
        const take = {
          id: ++takeCounter.current,
          url,
          extension,
          duration,
          frames: r.frames,
        };
        setTakes((old) => [take, ...old]);
      };
      recorder.onerror = () => {
        setError(
          'Recording was interrupted. Any captured audio will appear below.',
        );
        finishRecording();
      };
      recorder.start(1000);
      setRecording(true);
      setRecordSeconds(0);
    } catch (e) {
      rec.current = null;
      setError(e instanceof Error ? e.message : 'Recording could not start.');
    }
  }
  function synth(midi: number, time: number, duration: number, click = false) {
    const c = ctx.current;
    if (!c) return;
    if (!click)
      referenceUntil.current = Math.max(
        referenceUntil.current,
        // oxlint-disable-next-line react/react-compiler -- Event or lifecycle timestamp, never sampled during render.
        performance.now() / 1000 +
          Math.max(0, time - c.currentTime) +
          duration +
          0.15,
      );
    // A struck, decaying additive tone: piano-like reference, generated locally.
    const partials = click ? [1] : [1, 2, 3];
    partials.forEach((harmonic, i) => {
      const o = c.createOscillator(),
        g = c.createGain();
      o.frequency.value = click
        ? midi
          ? 1500
          : 1000
        : midiToFrequency(midi) * harmonic;
      o.type = 'sine';
      o.connect(g);
      g.connect(c.destination);
      const peak = click ? 0.045 : [0.13, 0.035, 0.012][i];
      g.gain.setValueAtTime(0, time);
      g.gain.linearRampToValueAtTime(peak, time + 0.005);
      g.gain.exponentialRampToValueAtTime(0.0001, time + duration);
      o.start(time);
      o.stop(time + duration + 0.01);
      nodes.current.add(o);
      o.onended = () => {
        nodes.current.delete(o);
        o.disconnect();
        g.disconnect();
      };
    });
  }
  /**
   * A breath cue: one slow swell that rises for an inhale and falls for an
   * exhale. Quiet and low on purpose, so it guides the count without becoming
   * something to listen to.
   */
  function breathTone(rising: boolean) {
    const c = ctx.current;
    if (!c || c.state !== 'running') return;
    const start = c.currentTime + 0.01,
      length = 0.9;
    const o = c.createOscillator(),
      g = c.createGain();
    o.type = 'sine';
    o.frequency.setValueAtTime(rising ? 196 : 262, start);
    o.frequency.linearRampToValueAtTime(rising ? 262 : 196, start + length);
    o.connect(g);
    g.connect(c.destination);
    g.gain.setValueAtTime(0, start);
    g.gain.linearRampToValueAtTime(0.028, start + length * 0.35);
    g.gain.exponentialRampToValueAtTime(0.0001, start + length);
    o.start(start);
    o.stop(start + length + 0.02);
    nodes.current.add(o);
    o.onended = () => {
      nodes.current.delete(o);
      o.disconnect();
      g.disconnect();
    };
  }
  async function playKey(midi: number) {
    stopWarmup();
    audio.current?.pause();
    const token = warmGeneration.current;
    if (keyTimer.current) clearTimeout(keyTimer.current);
    setPlayedNote(null);
    try {
      const c = await audioContext();
      if (!mounted.current || token !== warmGeneration.current) return;
      synth(midi, c.currentTime, 1);
      setPlayedNote(midi);
      keyTimer.current = setTimeout(() => setPlayedNote(null), 1000);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not play this note.');
    }
  }
  async function cueTarget(midi: number) {
    try {
      const c = await audioContext();
      if (!mounted.current) return;
      synth(midi, c.currentTime, 1.2);
      if (keyTimer.current) clearTimeout(keyTimer.current);
      setPlayedNote(midi);
      keyTimer.current = setTimeout(() => setPlayedNote(null), 1000);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not play this note.');
    }
  }
  async function startWarmup() {
    stopWarmup();
    if (quest.current) endQuest();
    const token = warmGeneration.current;
    setError('');
    audio.current?.pause();
    setSelectedTake(null);
    try {
      const ready = await ensureInput();
      if (!ready || token !== warmGeneration.current || !mounted.current)
        return;
      const c = await audioContext();
      if (token !== warmGeneration.current || !mounted.current) return;
      const beats = makeWarmup(drill, root, steps, bpm);
      setWarmPlan(beats);
      setWarmView(null);
      setScores({});
      warm.current = {
        beats,
        start: c.currentTime + 0.2,
        scheduled: 0,
        duration: 60 / bpm,
        last: -1,
        click: metronome,
      };
      setWarming(true);
      setWarmLabel('Get ready');
      warmPanel.current?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Warm-up could not start.');
    }
  }
  function saveQuestSettings(next: {
    low?: number;
    high?: number;
    count?: number;
  }) {
    const low = next.low ?? questLow,
      high = next.high ?? questHigh,
      count = next.count ?? questCount;
    setQuestLow(low);
    setQuestHigh(high);
    setQuestCount(count);
    try {
      localStorage.setItem(
        QUEST_SETTINGS_KEY,
        JSON.stringify({ low, high, count }),
      );
    } catch {}
  }
  async function startQuest() {
    if (warm.current) stopWarmup();
    if (quest.current) endQuest();
    setError('');
    audio.current?.pause();
    setSelectedTake(null);
    const token = ++questGeneration.current;
    const synthetic = demoRef.current;
    try {
      const ready = await ensureInput();
      if (!ready || token !== questGeneration.current || !mounted.current)
        return;
      const c = await audioContext();
      if (token !== questGeneration.current || !mounted.current) return;
      const [low, high] = normalizeQuestRange(questLow, questHigh);
      // oxlint-disable-next-line react/react-compiler -- Event or lifecycle timestamp, never sampled during render.
      const targets = makeQuestTargets(low, high, questCount, Date.now());
      // oxlint-disable-next-line react/react-compiler -- Event or lifecycle timestamp, never sampled during render.
      const now = performance.now() / 1000;
      const run = startQuestRun(targets);
      quest.current = {
        run,
        startedAt: now,
        targetSince: now,
        lastSample: now,
        synthetic,
      };
      liveTarget.current = targets[0];
      setTarget(targets[0]);
      synth(targets[0], c.currentTime + 0.05, 1.2);
      setQuestView({
        run,
        status: 'running',
        synthetic,
        summary: null,
        saved: false,
      });
      questPanel.current?.scrollIntoView({
        behavior: 'smooth',
        block: 'start',
      });
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Pitch Quest could not start.');
    }
  }
  function skipQuestTarget() {
    const q = quest.current;
    if (!q) return;
    q.run = skipTarget(q.run);
    if (questFinished(q.run)) {
      endQuest();
      return;
    }
    // oxlint-disable-next-line react/react-compiler -- Event or lifecycle timestamp, never sampled during render.
    const now = performance.now() / 1000;
    q.targetSince = now;
    q.lastSample = now;
    const next = currentTarget(q.run);
    liveTarget.current = next;
    setTarget(next);
    const c = ctx.current;
    if (c && next !== null) synth(next, c.currentTime, 1.2);
    setQuestView({
      run: q.run,
      status: 'running',
      synthetic: q.synthetic,
      summary: null,
      saved: false,
    });
  }
  function resetSessionRange() {
    sustain.current = emptySustain();
    setSessionRange({ low: null, high: null });
  }
  function clearHistory() {
    if (
      !window.confirm(
        'Clear all saved practice history on this device? This removes practice time, observed range and quest bests. It cannot be undone.',
      )
    )
      return;
    historyRef.current = emptyHistory();
    // oxlint-disable-next-line react/react-compiler -- Event or lifecycle timestamp, never sampled during render.
    if (practice.current) practice.current.flushed = performance.now() / 1000;
    setHistory(historyRef.current);
    try {
      localStorage.removeItem(HISTORY_KEY);
    } catch {}
    resetSessionRange();
    sessionCounted.current = false;
  }
  // Written synchronously, like history, so closing the tab never loses a step.
  function updateDaily(change: (d: Daily) => Daily) {
    const next = change(dailyRef.current);
    if (next === dailyRef.current) return;
    dailyRef.current = next;
    setDaily(next);
    try {
      localStorage.setItem(DAILY_KEY, serializeDaily(next));
    } catch {}
  }
  /** A step needs the microphone only when it shows you your own pitch. */
  const needsMic = (step: Step | null) =>
    step !== null && (step.engine === 'mic' || step.engine === 'hold');
  function setRunState(next: DailyRun | null) {
    runRef.current = next;
    setRun(next);
  }
  /** Ending early still banks the part of the current step that was practised. */
  function stopRoutine() {
    const r = runRef.current;
    if (r) {
      const spent = Math.max(0, r.routine.steps[r.index].seconds - r.left);
      if (spent > 0) updateDaily((d) => logStep(d, spent, dayKey(), Date.now()));
    }
    setRunState(null);
    setDayDone(false);
    liveTarget.current = null;
    setTarget(null);
  }
  function startRoutine(id: RoutineId) {
    const base = routineById(id);
    // Fold in what we know about this voice; an empty profile changes nothing.
    const routine = {
      ...base,
      steps: personalizeSteps(base.steps, profileRef.current),
    };
    setRoutineId(id);
    setDayDone(false);
    const first = routine.steps[0];
    setRunState({
      routine,
      index: 0,
      left: first.seconds,
      playing: true,
      logged: 0,
    });
    if (needsMic(first)) void startListening();
    else void audioContext();
    requestAnimationFrame(() =>
      dailyPanel.current?.scrollIntoView({ block: 'start', behavior: 'smooth' }),
    );
  }
  /**
   * Move to another step. Whatever time was spent on the step we are leaving is
   * banked first, so skipping forward never credits time that was not practised.
   */
  function goToStep(target: number, credit: boolean) {
    const r = runRef.current;
    if (!r) return;
    const step = r.routine.steps[r.index];
    const spent = credit ? Math.max(0, step.seconds - r.left) : 0;
    if (spent > 0) updateDaily((d) => logStep(d, spent, dayKey(), Date.now()));
    if (target >= r.routine.steps.length) {
      updateDaily((d) => logComplete(d, dayKey(), Date.now()));
      setRunState(null);
      setDayDone(true);
      stopListening();
      return;
    }
    const index = Math.max(0, target);
    const next = r.routine.steps[index];
    setRunState({ ...r, index, left: next.seconds, logged: r.logged + spent });
    if (needsMic(next)) void startListening();
  }
  /**
   * Pull the server's calendar, merge it into the local one, then write the
   * merge back to both. The merge takes the larger value per day, so running
   * this at any moment, in any order, can only ever add practice.
   */
  async function syncPractice() {
    const client = await supabase();
    if (!client) return;
    const { data: userData } = await client.auth.getUser();
    const user = userData.user;
    if (!user) return;
    const { data, error } = await client
      .from(PRACTICE_TABLE)
      .select('day,seconds,steps,completed');
    if (error) {
      setSyncNote(authMessage(error));
      return;
    }
    const remote = rowsToDaily(data);
    const merged = mergeDaily(dailyRef.current, remote);
    updateDaily(() => merged);
    if (needsPush(remote, merged)) {
      const rows = dailyToRows(merged).map((row) => ({
        ...row,
        user_id: user.id,
      }));
      if (rows.length) {
        const { error: writeError } = await client
          .from(PRACTICE_TABLE)
          .upsert(rows, { onConflict: 'user_id,day' });
        if (writeError) {
          setSyncNote(authMessage(writeError));
          return;
        }
      }
    }
    if (!mounted.current) return;
    // oxlint-disable-next-line react/react-compiler -- Event or lifecycle timestamp, never sampled during render.
    setSyncedAt(Date.now());
  }
  async function sendSignInLink() {
    const client = await supabase();
    if (!client) return;
    const email = syncEmail.trim();
    if (!looksLikeEmail(email)) {
      setSyncNote('That does not look like an email address.');
      return;
    }
    setSyncBusy(true);
    setSyncNote('');
    const { error } = await client.auth.signInWithOtp({
      email,
      options: {
        shouldCreateUser: true,
        // Come back to whichever origin asked, so local and live both work.
        emailRedirectTo: window.location.origin,
      },
    });
    if (!mounted.current) return;
    setSyncBusy(false);
    if (error) {
      setSyncNote(authMessage(error));
      return;
    }
    setSyncStage('sent');
  }
  /** Signing out leaves every day of practice in this browser untouched. */
  async function signOutSync() {
    const client = await supabase();
    if (!client) return;
    await client.auth.signOut();
    if (!mounted.current) return;
    setAccount(null);
    setSyncedAt(null);
    setSyncStage('email');
    setSyncNote('');
    // The routine returns to its generic wording when nobody is signed in.
    profileRef.current = emptyProfile();
    setProfile(emptyProfile());
    setProfileOpen(false);
  }
  const syncLatest = useRef(syncPractice);
  useEffect(() => {
    syncLatest.current = syncPractice;
  });
  // Pick up a session on load: either one this browser already held, or one
  // arriving in the URL from a sign-in link. Visitors with neither never reach
  // the import, so they never download the auth client at all.
  useEffect(() => {
    const fromLink = hasAuthCallback();
    if (!hasStoredSession() && !fromLink) return;
    void (async () => {
      const client = await supabase();
      if (!client || !mounted.current) return;
      // Creating the client consumes the tokens in the URL; clear them either
      // way so they are not left in history or a shared link.
      const { data, error } = await client.auth.getSession();
      clearAuthCallback();
      if (!mounted.current) return;
      if (error || !data.session) {
        if (fromLink) {
          setSyncOpen(true);
          setSyncNote(
            'That sign-in link did not work. It may have expired or already been used. Send a fresh one.',
          );
        }
        return;
      }
      setAccount(data.session.user.email ?? 'signed in');
      if (fromLink) setSyncOpen(true);
      void syncLatest.current();
      void profileLatest.current();
    })();
  }, []);
  // Practice keeps being logged while a routine runs, so pushes are debounced
  // rather than fired per step.
  useEffect(() => {
    if (!account || !daily.updated) return;
    const timer = setTimeout(() => void syncLatest.current(), 4000);
    return () => clearTimeout(timer);
  }, [account, daily.updated]);
  const playingStep =
    run && run.playing ? `${run.routine.id}:${run.index}` : null;
  const breathCue = useRef(breathTone);
  useEffect(() => {
    breathCue.current = breathTone;
  });
  /**
   * Sound the breath cue on the step's own cadence. The pacer ring restarts its
   * animation whenever the step or the paused state changes, and so does this,
   * which is what keeps the swell and the ring in step with each other.
   */
  useEffect(() => {
    const active = runRef.current;
    const step = active ? active.routine.steps[active.index] : null;
    if (!playingStep || !breathSound || step?.engine !== 'breath' || !step.breath)
      return;
    const [inhale, hold, exhale] = step.breath;
    const pending: ReturnType<typeof setTimeout>[] = [];
    const cycle = () => {
      breathCue.current(true);
      pending.push(
        setTimeout(() => breathCue.current(false), (inhale + hold) * 1000),
      );
    };
    cycle();
    const timer = setInterval(cycle, (inhale + hold + exhale) * 1000);
    return () => {
      clearInterval(timer);
      pending.forEach(clearTimeout);
    };
  }, [playingStep, breathSound]);
  function dismissOnboarding() {
    setOnboarding(false);
    try {
      localStorage.setItem(ONBOARDING_KEY, markOnboarded());
    } catch {}
  }
  // Introduce the app only to somebody who has never practised here.
  useEffect(() => {
    let stored: string | null = 'seen';
    try {
      stored = localStorage.getItem(ONBOARDING_KEY);
    } catch {}
    const practised = Object.keys(dailyRef.current.days).length > 0;
    if (shouldOnboard(stored, practised)) setOnboarding(true);
  }, []);
  /** Load the signed-in singer's profile, so the routine can speak to them. */
  async function loadProfile() {
    const client = await supabase();
    if (!client) return;
    const { data: userData } = await client.auth.getUser();
    if (!userData.user) return;
    const { data, error } = await client
      .from(PROFILE_TABLE)
      .select('low_note,high_note,break_low,break_high,songs,hard_line')
      .maybeSingle();
    if (error || !mounted.current) return;
    const next = rowToProfile(data);
    profileRef.current = next;
    setProfile(next);
  }
  async function saveProfile(next: Profile) {
    const client = await supabase();
    if (!client) return;
    const { data: userData } = await client.auth.getUser();
    const user = userData.user;
    if (!user) return;
    setProfileSaving(true);
    setProfileNote('');
    const { error } = await client
      .from(PROFILE_TABLE)
      .upsert({ ...profileToRow(next), user_id: user.id }, { onConflict: 'user_id' });
    if (!mounted.current) return;
    setProfileSaving(false);
    if (error) {
      setProfileNote(authMessage(error));
      return;
    }
    profileRef.current = next;
    setProfile(next);
    setProfileNote('Saved.');
  }
  function editProfile(change: Partial<Profile>) {
    setProfile((old) => ({ ...old, ...change }));
    setProfileNote('');
  }
  useEffect(() => {
    profileLatest.current = loadProfile;
  });
  // The tick below is created once, so it reaches goToStep through a ref that
  // every render refreshes rather than closing over the first one.
  const advance = useRef(goToStep);
  useEffect(() => {
    advance.current = goToStep;
  });
  // One tick a second drives the step clock and rolls into the next step.
  useEffect(() => {
    const timer = setInterval(() => {
      const r = runRef.current;
      if (!r || !r.playing) return;
      if (r.left > 1) {
        setRunState({ ...r, left: r.left - 1 });
        return;
      }
      advance.current(r.index + 1, true);
    }, 1000);
    return () => clearInterval(timer);
  }, []);
  useEffect(() => {
    try {
      const stored = parseDaily(localStorage.getItem(DAILY_KEY));
      dailyRef.current = stored;
      requestAnimationFrame(() => setDaily(stored));
    } catch {}
  }, []);
  useEffect(() => {
    const timer = setInterval(() => {
      const w = warm.current,
        c = ctx.current;
      if (!w || !c) return;
      const elapsed = c.currentTime - w.start;
      if (
        w.scheduled < w.beats.length &&
        elapsed - w.beats[w.scheduled].time > 0.25
      ) {
        stopWarmup();
        setWarmLabel(
          'Warm-up stopped because audio timing was interrupted. Press Start warm-up to restart.',
        );
        return;
      }
      while (
        w.scheduled < w.beats.length &&
        w.beats[w.scheduled].time <= elapsed + 0.12
      ) {
        const b = w.beats[w.scheduled];
        const when = Math.max(c.currentTime, w.start + b.time);
        if (b.phase === 'listen' && b.onset && b.midi !== null)
          synth(b.midi, when, w.duration * 1.7);
        if (w.click) synth(b.accent ? 1 : 0, when, 0.035, true);
        w.scheduled++;
      }
      const idx = Math.min(
        w.beats.length - 1,
        Math.floor(elapsed / w.duration),
      );
      if (idx >= 0) {
        const beat = w.beats[idx];
        setWarmView({
          beat,
          progress: Math.min(
            1,
            ((elapsed - beat.time) / w.duration + (beat.onset ? 0 : 1)) / 2,
          ),
        });
      }
      if (idx >= 0 && idx !== w.last) {
        w.last = idx;
        const b = w.beats[idx];
        liveTarget.current = b.midi;
        setTarget(b.midi);
        setWarmLabel(`${b.label} · ${noteName(b.root)} · round ${b.round}`);
      }
      if (elapsed >= w.beats.length * w.duration) {
        stopWarmup();
        setWarmLabel('Warm-up complete. Listening can continue.');
      }
    }, 25);
    return () => clearInterval(timer);
  }, []);
  function dispose() {
    if (keyTimer.current) clearTimeout(keyTimer.current);
    // oxlint-disable-next-line react/react-compiler -- Event or lifecycle timestamp, never sampled during render.
    flushPractice(performance.now() / 1000);
    mounted.current = false;
    generation.current++;
    warmGeneration.current++;
    questGeneration.current++;
    pending.current = false;
    warm.current = null;
    quest.current = null;
    if (micTimer.current) clearInterval(micTimer.current);
    if (demoTimer.current) clearInterval(demoTimer.current);
    if (rec.current?.recorder.state === 'recording')
      rec.current.recorder.stop();
    stream.current?.getTracks().forEach((t) => t.stop());
    source.current?.disconnect();
    analyser.current?.disconnect();
    nodes.current.forEach((n) => {
      try {
        n.stop();
      } catch {}
    });
    void ctx.current?.close();
    urls.current.forEach((url) => URL.revokeObjectURL(url));
  }
  useEffect(() => {
    mounted.current = true;
    const pagehide = () => {
      finishRecording();
      stopListening();
      stopDemoVoice();
      stopWarmup();
    };
    window.addEventListener('pagehide', pagehide);
    return () => {
      dispose();
      window.removeEventListener('pagehide', pagehide);
    };
  }, []);
  useEffect(() => {
    try {
      const saved = localStorage.getItem('free-sing-theme') || 'system';
      requestAnimationFrame(() => setTheme(saved));
    } catch {}
  }, []);
  useEffect(() => {
    try {
      const stored = parseHistory(localStorage.getItem(HISTORY_KEY));
      historyRef.current = stored;
      let settings: { low?: unknown; high?: unknown; count?: unknown } | null =
        null;
      try {
        settings = JSON.parse(
          localStorage.getItem(QUEST_SETTINGS_KEY) || 'null',
        );
      } catch {}
      requestAnimationFrame(() => {
        setHistory(stored);
        if (settings && typeof settings === 'object') {
          const [low, high] = normalizeQuestRange(
            Number(settings.low),
            Number(settings.high),
          );
          setQuestLow(low);
          setQuestHigh(high);
          const count = Number(settings.count);
          if ((QUEST_COUNTS as readonly number[]).includes(count))
            setQuestCount(count);
        }
      });
    } catch {}
  }, []);
  useEffect(() => {
    const media = matchMedia('(prefers-color-scheme: dark)');
    const apply = () =>
      document.documentElement.classList.toggle(
        'dark',
        theme === 'dark' || (theme === 'system' && media.matches),
      );
    apply();
    media.addEventListener('change', apply);
    try {
      localStorage.setItem('free-sing-theme', theme);
    } catch {}
    return () => media.removeEventListener('change', apply);
  }, [theme]);
  useEffect(() => {
    if (!playing) return;
    let id = 0;
    const tick = () => {
      setPlayhead(audio.current?.currentTime || 0);
      id = requestAnimationFrame(tick);
    };
    id = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(id);
  }, [playing]);
  function selectTake(take: Take) {
    stopInput();
    stopWarmup();
    audio.current?.pause();
    setSelectedTake(take);
    setPlayhead(0);
    setPlaying(false);
  }
  const replay = selectedTake !== null;
  const shownFrames = replay
    ? selectedTake.frames.filter((f) => f.t <= playhead && f.t >= playhead - 10)
    : frames;
  const current = replay
    ? shownFrames.length
      ? shownFrames[shownFrames.length - 1].midi
      : null
    : pitch;
  const referenceNote = replay
    ? shownFrames.length
      ? shownFrames[shownFrames.length - 1].target
      : null
    : target;
  const nearest = current === null ? null : Math.round(current),
    cents =
      current === null
        ? null
        : Math.round((current - Math.round(current)) * 100);
  const now = replay ? playhead : frames.at(-1)?.t || 0;
  const inputActive = demo ? demoRunning : listening || busy;
  useEffect(() => {
    if (!follow || nearest === null) return;
    const pane = roll.current;
    if (!pane) return;
    const y = (96 - nearest + 0.5) * 28;
    if (y < pane.scrollTop + 56 || y > pane.scrollTop + pane.clientHeight - 56)
      pane.scrollTop = Math.max(0, y - pane.clientHeight / 2);
  }, [follow, nearest]);
  useEffect(() => {
    if (roll.current) roll.current.scrollTop = (96 - 60) * 28 - 200;
  }, [mode]);
  function path(kind: 'midi' | 'target') {
    let pen = false;
    return shownFrames
      .map((f) => {
        const m = f[kind];
        if (m === null || m < 23.5 || m > 96.5) {
          pen = false;
          return '';
        }
        const command = `${pen ? 'L' : 'M'}${(((f.t - now + 10) / 10) * 810).toFixed(1)},${((96 - m + 0.5) * 28).toFixed(1)}`;
        pen = true;
        return command;
      })
      .join(' ');
  }
  const [questRangeLow, questRangeHigh] = normalizeQuestRange(
    questLow,
    questHigh,
  );
  const questRunning = questView?.status === 'running';
  const questTargetNow =
    questView && questRunning ? currentTarget(questView.run) : null;
  const questOnTarget =
    questTargetNow !== null && isOnTarget(current, questTargetNow);
  const questHint =
    questTargetNow === null
      ? ''
      : questOnTarget
        ? 'Hold it steady…'
        : current === null
          ? demo
            ? 'Synthetic voice is breathing'
            : 'Sing the note when you are ready'
          : current < questTargetNow
            ? 'A little higher'
            : 'A little lower';
  const savedLow = history.low,
    savedHigh = history.high;
  const [introTitle, introText] = INTRO[mode];
  const runStep = run ? run.routine.steps[run.index] : null;
  const todayKey = dayKey();
  const dayStreak = streak(daily, todayKey);
  const today = daily.days[todayKey] ?? null;
  const strip = recentDays(daily, 28, todayKey);
  const stepProgress = runStep
    ? (runStep.seconds - run!.left) / runStep.seconds
    : 0;
  const plannedSteps = personalizeSteps(
    routineById(routineId).steps,
    profile,
  );
  const breath = runStep?.breath ?? [3, 2, 9];
  const breathCycle = breath[0] + breath[1] + breath[2];
  const breathIn = ((breath[0] / breathCycle) * 100).toFixed(1);
  const breathHold = (((breath[0] + breath[1]) / breathCycle) * 100).toFixed(1);
  // Daily only takes over the console while a step is actually showing your pitch.
  const showConsole =
    mode === 'daily'
      ? runStep !== null && needsMic(runStep)
      : mode !== 'history';
  const noteLabel = replay
    ? 'PLAYBACK NOTE'
    : demo
      ? 'SYNTHETIC NOTE'
      : 'YOUR NOTE';
  const statusLabel = replay
    ? 'REPLAY'
    : recording
      ? 'RECORDING'
      : demo
        ? demoRunning
          ? 'DEMO · SYNTHETIC'
          : 'DEMO · PAUSED'
        : listening
          ? 'LISTENING'
          : 'READY';
  return (
    <div className={`sing-app ${demo ? 'fs-demo' : ''}`}>
      {onboarding && (
        <dialog open className="fs-onboard" aria-label="Welcome to Singwell">
          <div className="fs-onboard-card">
            <span className="fs-brand fs-onboard-brand">
              <AudioLines />
              Singwell
            </span>
            <h1>Ten minutes a day beats an hour on Sunday.</h1>
            <p className="fs-onboard-lede">
              A guided vocal routine that runs on a clock, listens while you
              sing, and remembers that you turned up.
            </p>
            <div className="fs-onboard-panels">
              {PANELS.map((p, i) => (
                <article
                  key={p.id}
                  className={i === panel ? 'fs-panel-on' : ''}
                  aria-current={i === panel ? 'step' : undefined}
                >
                  <div className={`fs-art fs-art-${p.art}`} aria-hidden="true">
                    {p.art === 'steps' && (
                      <>
                        <i className="fs-art-row fs-art-done" />
                        <i className="fs-art-row" />
                        <i className="fs-art-row" />
                      </>
                    )}
                    {p.art === 'listen' && (
                      <>
                        <i className="fs-art-ring" />
                        <span className="fs-art-bars">
                          <i /><i /><i /><i />
                        </span>
                      </>
                    )}
                    {p.art === 'streak' && (
                      <span className="fs-art-grid">
                        {Array.from({ length: 14 }, (_, k) => (
                          <i key={k} className={k % 5 === 3 ? '' : 'fs-art-lit'} />
                        ))}
                      </span>
                    )}
                  </div>
                  <h2>{p.title}</h2>
                  <p>{p.body}</p>
                </article>
              ))}
            </div>
            <div className="fs-onboard-foot">
              <div className="fs-onboard-dots" aria-hidden="true">
                {PANELS.map((p, i) => (
                  <button
                    key={p.id}
                    type="button"
                    className={i === panel ? 'fs-dot-on' : ''}
                    onClick={() => setPanel(i)}
                    aria-label={`Show ${p.title}`}
                  />
                ))}
              </div>
              {panel < PANELS.length - 1 ? (
                <button
                  type="button"
                  className="fs-onboard-go"
                  onClick={() => setPanel((n) => n + 1)}
                >
                  Next <ChevronRight size={17} />
                </button>
              ) : (
                <button
                  type="button"
                  className="fs-onboard-go"
                  onClick={() => {
                    dismissOnboarding();
                    startRoutine(routineId);
                  }}
                >
                  Start your first session <ChevronRight size={17} />
                </button>
              )}
              <button
                type="button"
                className="fs-onboard-skip"
                onClick={dismissOnboarding}
              >
                Look around first
              </button>
            </div>
          </div>
        </dialog>
      )}
      <header className="fs-header">
        <div>
          <span className="fs-brand">
            <AudioLines />
            Singwell
          </span>
          <span className="fs-free">Ten minutes a day</span>
        </div>
        <div className="fs-header-actions">
          {onBack && (
            <button
              onClick={() => {
                if (rec.current) {
                  finishRecording();
                  setError(
                    'Your take is being saved below. Download it before leaving Free sing.',
                  );
                  return;
                }
                if (
                  takes.length &&
                  !window.confirm(
                    'Leaving Free sing discards these temporary takes. Download any you want to keep first. Leave anyway?',
                  )
                )
                  return;
                stopListening();
                stopDemoVoice();
                stopWarmup();
                onBack();
              }}
            >
              <ArrowLeft size={16} />
              Exercises
            </button>
          )}
          {syncConfigured && (
            <button
              className={syncOpen ? 'fs-sync-toggle fs-sync-on' : 'fs-sync-toggle'}
              aria-expanded={syncOpen}
              onClick={() => setSyncOpen((open) => !open)}
              title={
                account
                  ? 'Your practice syncs to this account'
                  : 'Optional: keep your streak across devices'
              }
            >
              <CloudCheck size={16} />
              {account ? 'Synced' : 'Sync'}
            </button>
          )}
          <button
            className={
              demo ? 'fs-demo-toggle fs-demo-toggle-on' : 'fs-demo-toggle'
            }
            aria-pressed={demo}
            onClick={() => (demo ? exitDemo() : enterDemo())}
            title={
              demo
                ? 'Return to your real microphone'
                : 'Watch the app with a synthetic voice. No microphone needed.'
            }
          >
            {demo ? <X size={16} /> : <Sparkles size={16} />}
            {demo ? 'Exit demo' : 'Try demo'}
          </button>
          <select
            aria-label="Appearance"
            value={theme}
            onChange={(e) => setTheme(e.target.value)}
          >
            <option value="system">System</option>
            <option value="light">Light</option>
            <option value="dark">Dark</option>
          </select>
        </div>
      </header>
      <nav className="fs-nav" aria-label="Modes">
        <div className="fs-nav-tabs">
          {MODES.map(({ id, label, icon: Icon }) => (
            <button
              key={id}
              type="button"
              className={mode === id ? 'fs-nav-active' : ''}
              aria-current={mode === id ? 'page' : undefined}
              onClick={() => switchMode(id)}
            >
              <Icon size={16} aria-hidden="true" />
              {label}
            </button>
          ))}
        </div>
        {inputActive && (
          <div className="fs-nav-live">
            <i aria-hidden="true" />
            <span>
              {demo
                ? 'Demo voice playing'
                : busy
                  ? 'Requesting microphone'
                  : recording
                    ? 'Recording'
                    : 'Listening'}
            </span>
            {mode === 'history' && (
              <button type="button" onClick={stopInput}>
                <Square size={14} /> Stop
              </button>
            )}
          </div>
        )}
      </nav>
      {demo && (
        <div className="fs-demo-banner" aria-live="polite">
          <Sparkles size={18} aria-hidden="true" />
          <p>
            <strong>Demo mode · synthetic voice.</strong> The pitch you see is
            generated by the app, not a microphone. Nothing here is recorded,
            scored for real or saved to your history.
          </p>
          <button type="button" onClick={exitDemo}>
            <X size={16} /> Exit demo
          </button>
        </div>
      )}
      {syncConfigured && syncOpen && (
        <section className="fs-sync" aria-label="Practice sync">
          {account ? (
            <>
              <div className="fs-sync-who">
                <p>
                  <strong>Signed in as {account}.</strong> Your practice
                  calendar merges across every device you sign in on.
                </p>
                <small>
                  {syncedAt
                    ? `Last synced at ${new Date(syncedAt).toLocaleTimeString()}.`
                    : 'Not synced yet this session.'}
                </small>
              </div>
              <div className="fs-sync-actions">
                <button
                  type="button"
                  disabled={syncBusy}
                  onClick={() => void syncPractice()}
                >
                  <CloudCheck size={15} /> Sync now
                </button>
                <button type="button" onClick={() => void signOutSync()}>
                  <LogOut size={15} /> Sign out
                </button>
              </div>
            </>
          ) : (
            <>
              <div className="fs-sync-who">
                <p>
                  <strong>Optional.</strong> Free Sing works with no account.
                  Sign in only if you want one streak across your laptop and
                  your phone. We email you a link; there is no password.
                </p>
                <small>
                  Only your practice calendar is stored: the day, how long and
                  whether you finished. No audio, no recordings, ever.
                </small>
              </div>
              {syncStage === 'sent' ? (
                <div className="fs-sync-actions fs-sync-sent">
                  <p>
                    <Check size={15} aria-hidden="true" /> Link sent to{' '}
                    <strong>{syncEmail.trim()}</strong>. Open it on this device
                    and you will land back here signed in.
                  </p>
                  <button
                    type="button"
                    className="fs-sync-back"
                    onClick={() => {
                      setSyncStage('email');
                      setSyncNote('');
                    }}
                  >
                    Send another link
                  </button>
                </div>
              ) : (
                <form
                  className="fs-sync-actions"
                  onSubmit={(e) => {
                    e.preventDefault();
                    void sendSignInLink();
                  }}
                >
                  <input
                    type="email"
                    autoComplete="email"
                    placeholder="you@example.com"
                    aria-label="Email address"
                    value={syncEmail}
                    onChange={(e) => setSyncEmail(e.target.value)}
                  />
                  <button type="submit" disabled={syncBusy}>
                    {syncBusy ? <Loader size={15} /> : <CloudCheck size={15} />}
                    {syncBusy ? 'Sending' : 'Email me a link'}
                  </button>
                </form>
              )}
            </>
          )}
          {syncNote && (
            <p className="fs-sync-note" aria-live="polite">
              {syncNote}
            </p>
          )}
        </section>
      )}
      <div className="fs-intro">
        <h1>{introTitle}</h1>
        <p>{introText}</p>
      </div>
      {mode === 'daily' && account && profileOpen && (
        <section className="fs-voice" aria-label="Your voice">
          <div className="fs-voice-head">
            <div>
              <h2>Your voice</h2>
              <p>
                What the routine knows about you. Saved to your account, used to
                tailor the exercises, never shown to anyone else.
              </p>
            </div>
            <button type="button" onClick={() => setProfileOpen(false)}>
              <X size={15} /> Close
            </button>
          </div>

          <div className="fs-voice-grid">
            <label>
              <span>Chest gives out at</span>
              <select
                value={profile.breakLow ?? ''}
                onChange={(e) =>
                  editProfile({
                    breakLow: e.target.value ? Number(e.target.value) : null,
                  })
                }
              >
                <option value="">Not sure yet</option>
                {NOTE_CHOICES.map((n) => (
                  <option key={n} value={n}>
                    {noteName(n)}
                  </option>
                ))}
              </select>
            </label>
            <label>
              <span>Head takes over at</span>
              <select
                value={profile.breakHigh ?? ''}
                onChange={(e) =>
                  editProfile({
                    breakHigh: e.target.value ? Number(e.target.value) : null,
                  })
                }
              >
                <option value="">Not sure yet</option>
                {NOTE_CHOICES.map((n) => (
                  <option key={n} value={n}>
                    {noteName(n)}
                  </option>
                ))}
              </select>
            </label>
            <label>
              <span>Lowest comfortable note</span>
              <select
                value={profile.low ?? ''}
                onChange={(e) =>
                  editProfile({
                    low: e.target.value ? Number(e.target.value) : null,
                  })
                }
              >
                <option value="">Not sure yet</option>
                {NOTE_CHOICES.map((n) => (
                  <option key={n} value={n}>
                    {noteName(n)}
                  </option>
                ))}
              </select>
            </label>
            <label>
              <span>Highest comfortable note</span>
              <select
                value={profile.high ?? ''}
                onChange={(e) =>
                  editProfile({
                    high: e.target.value ? Number(e.target.value) : null,
                  })
                }
              >
                <option value="">Not sure yet</option>
                {NOTE_CHOICES.map((n) => (
                  <option key={n} value={n}>
                    {noteName(n)}
                  </option>
                ))}
              </select>
            </label>
          </div>

          {savedLow !== null && savedHigh !== null && (
            <button
              type="button"
              className="fs-voice-adopt"
              onClick={() => editProfile({ low: savedLow, high: savedHigh })}
            >
              Use the range already tracked: {noteName(savedLow)} to{' '}
              {noteName(savedHigh)}
            </button>
          )}

          <label className="fs-voice-line">
            <span>The line you keep getting wrong</span>
            <input
              type="text"
              maxLength={200}
              placeholder="One phrase from a song you are working on"
              value={profile.hardLine ?? ''}
              onChange={(e) => editProfile({ hardLine: e.target.value || null })}
            />
          </label>

          <div className="fs-voice-songs">
            <span>Songs you are working on</span>
            <div className="fs-song-tags">
              {profile.songs.map((song) => (
                <span key={song}>
                  {song}
                  <button
                    type="button"
                    onClick={() =>
                      editProfile({
                        songs: profile.songs.filter((x) => x !== song),
                      })
                    }
                    aria-label={`Remove ${song}`}
                  >
                    <X size={13} />
                  </button>
                </span>
              ))}
            </div>
            <form
              onSubmit={(e) => {
                e.preventDefault();
                const field = new FormData(e.currentTarget).get('song');
                const next = typeof field === 'string' ? field.trim() : '';
                if (!next || profile.songs.includes(next) || profile.songs.length >= 12)
                  return;
                editProfile({ songs: [...profile.songs, next] });
                e.currentTarget.reset();
              }}
            >
              <input
                name="song"
                type="text"
                maxLength={80}
                placeholder="Add a song"
                aria-label="Add a song"
              />
              <button type="submit">Add</button>
            </form>
          </div>

          <div className="fs-voice-foot">
            <small>
              {profileIsEmpty(profile)
                ? 'With nothing filled in, every step keeps its general wording.'
                : 'The bridge and song steps will use these.'}
            </small>
            <div>
              {profileNote && <em aria-live="polite">{profileNote}</em>}
              <button
                type="button"
                className="fs-voice-save"
                disabled={profileSaving}
                onClick={() => void saveProfile(profile)}
              >
                {profileSaving ? <Loader size={15} /> : <Check size={15} />}
                {profileSaving ? 'Saving' : 'Save'}
              </button>
            </div>
          </div>
        </section>
      )}
      {mode === 'daily' && (
        <section
          ref={dailyPanel}
          className="fs-daily"
          aria-label="Daily practice"
        >
          {run && runStep ? (
            <>
              <div className="fs-step-top">
                <span className="fs-step-count">
                  Step {run.index + 1} of {run.routine.steps.length} ·{' '}
                  {run.routine.label}
                </span>
                <button type="button" onClick={stopRoutine}>
                  <X size={15} /> End session
                </button>
              </div>
              <div className="fs-step-bar" aria-hidden="true">
                {run.routine.steps.map((step, i) => (
                  <i
                    key={stepKey(step, i)}
                    className={
                      i < run.index
                        ? 'fs-bar-done'
                        : i === run.index
                          ? 'fs-bar-now'
                          : ''
                    }
                    style={
                      i === run.index
                        ? ({
                            '--fill': `${stepProgress * 100}%`,
                          } as CSSProperties)
                        : undefined
                    }
                  />
                ))}
              </div>
              <div className="fs-step-main">
                <div className="fs-step-copy">
                  <h2>{runStep.title}</h2>
                  <p className="fs-step-cue">{runStep.cue}</p>
                  <ul>
                    {runStep.detail.map((line) => (
                      <li key={line}>{line}</li>
                    ))}
                  </ul>
                  <p className="fs-step-source">{runStep.source}</p>
                </div>
                <div className="fs-step-side">
                  {runStep.engine === 'breath' && runStep.breath ? (
                    <div
                      className={
                        run.playing ? 'fs-breath fs-breath-on' : 'fs-breath'
                      }
                      style={
                        { '--cycle': `${breathCycle}s` } as CSSProperties
                      }
                    >
                      {/* Keyframe stops follow the step's own in/hold/out split,
                          so changing the tuple cannot silently desync the ring. */}
                      <style>{`@keyframes fs-breathe-live{0%{transform:scale(.45)}${breathIn}%{transform:scale(1)}${breathHold}%{transform:scale(1)}100%{transform:scale(.45)}}@keyframes fs-halo{0%{opacity:.08;transform:scale(.45) translateY(-18px)}${breathIn}%{opacity:.22;transform:scale(1.18) translateY(-18px)}${breathHold}%{opacity:.22;transform:scale(1.18) translateY(-18px)}100%{opacity:.08;transform:scale(.45) translateY(-18px)}}`}</style>
                      <i aria-hidden="true" />
                      <span>
                        <Wind size={16} aria-hidden="true" /> in{' '}
                        {runStep.breath[0]} · hold {runStep.breath[1]} · out{' '}
                        {runStep.breath[2]}
                      </span>
                      <small>{formatTime(run.left)} left</small>
                      <button
                        type="button"
                        className="fs-breath-mute"
                        aria-pressed={breathSound}
                        onClick={() => setBreathSound((on) => !on)}
                      >
                        {breathSound ? <Volume2 size={14} /> : <X size={14} />}
                        {breathSound ? 'Sound on' : 'Silent'}
                      </button>
                    </div>
                  ) : (
                    <div className="fs-step-clock" aria-live="off">
                      <strong>{formatTime(run.left)}</strong>
                      <span>left on this step</span>
                    </div>
                  )}
                  {runStep.engine === 'hold' && (
                    <p className="fs-step-hold">
                      Sit around {noteName(runStep.hold ?? 60)}. The trail below
                      should be a flat line.
                    </p>
                  )}
                  <div className="fs-step-controls">
                    <button
                      type="button"
                      onClick={() => goToStep(run.index - 1, false)}
                      disabled={run.index === 0}
                    >
                      <ChevronLeft size={16} /> Back
                    </button>
                    <button
                      type="button"
                      className="fs-step-play"
                      onClick={() =>
                        setRunState({ ...run, playing: !run.playing })
                      }
                    >
                      {run.playing ? <Pause size={16} /> : <Play size={16} />}
                      {run.playing ? 'Pause' : 'Resume'}
                    </button>
                    <button
                      type="button"
                      onClick={() => goToStep(run.index + 1, true)}
                    >
                      Next <SkipForward size={16} />
                    </button>
                  </div>
                </div>
              </div>
            </>
          ) : (
            <>
              {dayDone && (
                <div className="fs-day-done" aria-live="polite">
                  <Check size={20} aria-hidden="true" />
                  <p>
                    <strong>Done for today.</strong> That is{' '}
                    {dayStreak === 1 ? 'day one' : `${dayStreak} days in a row`}.
                    Come back tomorrow.
                  </p>
                </div>
              )}
              <div className="fs-streak">
                <div className="fs-streak-now">
                  <Flame size={22} aria-hidden="true" />
                  <strong>{dayStreak}</strong>
                  <span>
                    day{dayStreak === 1 ? '' : 's'} in a row
                    {today ? '' : dayStreak ? ' · today still open' : ''}
                  </span>
                </div>
                <dl className="fs-streak-stats">
                  <div>
                    <dt>Best run</dt>
                    <dd>{bestStreak(daily)}</dd>
                  </div>
                  <div>
                    <dt>Days practised</dt>
                    <dd>{totalDays(daily)}</dd>
                  </div>
                  <div>
                    <dt>Total time</dt>
                    <dd>{formatMinutes(totalSeconds(daily))}</dd>
                  </div>
                </dl>
              </div>
              <div className="fs-cal" aria-label="Last 28 days">
                <span className="fs-cal-head">
                  <CalendarDays size={14} aria-hidden="true" /> Last 28 days
                </span>
                <div className="fs-cal-grid">
                  {strip.map(({ key, day }) => (
                    <i
                      key={key}
                      title={`${key}${day ? ` · ${formatMinutes(day.seconds)}${day.completed ? ' · finished' : ''}` : ' · nothing yet'}`}
                      className={
                        day?.completed
                          ? 'fs-cal-full'
                          : day && day.seconds > 0
                            ? 'fs-cal-part'
                            : ''
                      }
                    />
                  ))}
                </div>
              </div>
              <div className="fs-routines">
                {ROUTINES.map((routine) => (
                  <article
                    key={routine.id}
                    className={
                      routine.id === routineId
                        ? 'fs-routine fs-routine-on'
                        : 'fs-routine'
                    }
                  >
                    <button
                      type="button"
                      className="fs-routine-pick"
                      aria-pressed={routine.id === routineId}
                      onClick={() => setRoutineId(routine.id)}
                    >
                      <h3>
                        {routine.label}
                        <em>{routineLength(routine)}</em>
                      </h3>
                      <p>{routine.blurb}</p>
                    </button>
                  </article>
                ))}
              </div>
              <div className="fs-plan">
                <ol>
                  {plannedSteps.map((step, i) => (
                    <li key={stepKey(step, i)}>
                      <span className="fs-plan-title">{step.title}</span>
                      <span className="fs-plan-cue">{step.cue}</span>
                      <span className="fs-plan-time">
                        {Math.round(step.seconds / 60) || 1} min
                      </span>
                    </li>
                  ))}
                </ol>
                <button
                  type="button"
                  className="fs-start-daily"
                  onClick={() => startRoutine(routineId)}
                >
                  <Play size={18} />
                  {today?.completed ? 'Practise again' : 'Start today'} ·{' '}
                  {routineLength(routineById(routineId))}
                </button>
                <p className="fs-plan-note">
                  The microphone turns on only for the steps that show your
                  pitch.
                </p>
                {account && !profileOpen && (
                  <button
                    type="button"
                    className="fs-voice-open"
                    onClick={() => setProfileOpen(true)}
                  >
                    <Sparkles size={14} />
                    {profileIsEmpty(profile)
                      ? 'Tell it about your voice'
                      : 'Your voice'}
                  </button>
                )}
              </div>
            </>
          )}
        </section>
      )}
      {showConsole && (
        <section className="fs-console" aria-label="Singing controls">
          <div className="fs-stats">
            <div>
              <span>{noteLabel}</span>
              <strong>{nearest === null ? '—' : noteName(nearest)}</strong>
            </div>
            <div>
              <span>FREQUENCY</span>
              <strong>
                {current === null ? '—' : midiToFrequency(current).toFixed(1)}
                <small> Hz</small>
              </strong>
            </div>
            <div>
              <span>NEAREST NOTE</span>
              <strong
                className={
                  cents !== null && Math.abs(cents) <= 35 ? 'fs-green' : ''
                }
              >
                {cents === null ? '—' : `${cents > 0 ? '+' : ''}${cents}`}
                <small> cents</small>
              </strong>
            </div>
            <div className="fs-session">
              <span>{statusLabel}</span>
              <p>
                {recording
                  ? formatTime(recordSeconds)
                  : replay
                    ? formatTime(playhead)
                    : demo
                      ? 'Simulated input'
                      : 'At your own pace'}
              </p>
              <div
                className={inputActive ? 'fs-meter fs-meter-on' : 'fs-meter'}
                aria-hidden="true"
              >
                {levels.map((v, i) => (
                  <i
                    // eslint-disable-next-line react/no-array-index-key
                    key={i}
                    style={{ transform: `scaleY(${0.08 + v * 0.92})` }}
                  />
                ))}
              </div>
            </div>
          </div>
          <div className="fs-controls">
            <button
              className="fs-primary"
              onClick={() => (inputActive ? stopInput() : void ensureInput())}
            >
              {inputActive ? (
                <Square size={18} />
              ) : demo ? (
                <Play size={18} />
              ) : (
                <Mic size={18} />
              )}{' '}
              {demo
                ? demoRunning
                  ? 'Stop demo voice'
                  : 'Play demo voice'
                : busy
                  ? 'Cancel microphone request'
                  : listening
                    ? 'Stop listening'
                    : 'Start listening'}
            </button>
            <button
              className={recording ? 'fs-record-active' : ''}
              disabled={busy || demo}
              title={demo ? 'Recording is off in demo mode' : undefined}
              onClick={() =>
                recording ? finishRecording() : void startRecording()
              }
            >
              {recording ? <Square size={16} /> : <Circle size={16} />}{' '}
              {recording ? 'Finish recording' : 'Record a take'}
            </button>
            <span className="fs-control-note">
              {demo
                ? 'Recording is off in demo mode. Exit demo to use your microphone.'
                : listening
                  ? 'Listening keeps going until you stop.'
                  : 'Microphone permission is requested when you start.'}
            </span>
          </div>
          {error && (
            <p className="fs-error" role="alert">
              {error}
            </p>
          )}
        </section>
      )}
      {mode === 'warmups' && (
        <section
          ref={warmPanel}
          className="fs-call-response"
          aria-label="Listen and repeat warm-up"
        >
          <div className="fs-panel-heading">
            <h2>
              {warming
                ? warmLabel
                : warmView
                  ? 'Your warm-up results'
                  : 'Listen, then sing it back'}
              {demo && <span className="fs-badge">Demo · synthetic</span>}
            </h2>
            {warming && (
              <button onClick={stopWarmup}>
                <Square size={16} /> Stop warm-up
              </button>
            )}
          </div>
          <p>
            Blue = the piano’s turn. Green = your turn. Hold each note for two
            clicks.
          </p>
          {(['listen', 'sing'] as const).map((phase) => (
            <div className={`fs-sequence fs-sequence-${phase}`} key={phase}>
              <strong>
                {phase === 'listen' ? '1 · Listen' : '2 · Sing it back'}
              </strong>
              <div className="fs-note-lane">
                {(warmPlan.length
                  ? warmPlan
                  : makeWarmup(drill, root, steps, bpm)
                )
                  .filter(
                    (b) =>
                      b.round === (warmView?.beat.round || 1) &&
                      b.phase === phase &&
                      b.onset,
                  )
                  .map((b) => {
                    const active =
                      warming &&
                      warmView?.beat.phase === phase &&
                      warmView.beat.noteIndex === b.noteIndex;
                    const result = scores[`${b.round}-${b.noteIndex}`];
                    const passed =
                      (!warming && warmView !== null) ||
                      (warmView?.beat.round === b.round &&
                        (warmView.beat.phase === 'rest' ||
                          (warmView.beat.phase === 'sing' &&
                            warmView.beat.noteIndex > b.noteIndex)));
                    const label =
                      phase === 'listen'
                        ? 'Piano'
                        : result || passed
                          ? scoreLabel(result)
                          : demo
                            ? 'Synthetic'
                            : 'Your voice';
                    return (
                      <div
                        key={b.noteIndex}
                        className={`fs-note-card ${active ? 'fs-note-now' : ''} ${label === 'Hit' ? 'fs-note-hit' : ''}`}
                      >
                        <span>{noteName(b.midi!)}</span>
                        <small>{label}</small>
                        {active && (
                          <i
                            style={{
                              width: `${(warmView?.progress || 0) * 100}%`,
                            }}
                          />
                        )}
                      </div>
                    );
                  })}
              </div>
            </div>
          ))}
          <p className="fs-score-help">
            {
              Object.values(scores).filter((s) => scoreLabel(s) === 'Hit')
                .length
            }{' '}
            notes matched this session. “Hit” means at least half the sampled
            time was within ±50 cents, after a short settling-in period. No
            clear pitch is unscored, not a judgment of your voice.
            {demo &&
              ' In demo mode these results come from the synthetic voice.'}
          </p>
        </section>
      )}
      {mode === 'quest' && (
        <section ref={questPanel} className="fs-quest" aria-label="Pitch Quest">
          <div className="fs-panel-heading">
            <h2>
              <Target size={20} aria-hidden="true" />
              {questRunning
                ? `Target ${questView!.run.index + 1} of ${questView!.run.targets.length}`
                : questView?.status === 'done'
                  ? 'Quest finished'
                  : 'Set your comfortable range'}
              {demo && <span className="fs-badge">Demo · synthetic</span>}
            </h2>
            {questRunning && (
              <button onClick={endQuest}>
                <Square size={16} /> Stop quest
              </button>
            )}
          </div>
          {questRunning && questView && questTargetNow !== null ? (
            <div className="fs-quest-live">
              <div className="fs-quest-target">
                <span>SING THIS NOTE</span>
                <strong aria-live="polite">{noteName(questTargetNow)}</strong>
                <small>{midiToFrequency(questTargetNow).toFixed(1)} Hz</small>
                <button
                  type="button"
                  onClick={() => void cueTarget(questTargetNow)}
                >
                  <Volume2 size={16} /> Hear it again
                </button>
              </div>
              <div
                className={`fs-hold ${questOnTarget ? 'fs-hold-on' : ''}`}
                aria-label="Hold progress"
              >
                <progress
                  className="sr-only"
                  aria-label="Hold progress"
                  max={100}
                  value={Math.round(questView.run.hold * 100)}
                />
                <svg viewBox="0 0 120 120" aria-hidden="true">
                  <circle className="fs-hold-track" cx="60" cy="60" r="52" />
                  <circle
                    className="fs-hold-fill"
                    cx="60"
                    cy="60"
                    r="52"
                    strokeDasharray={HOLD_RING}
                    strokeDashoffset={(
                      HOLD_RING *
                      (1 - Math.min(1, Math.max(0, questView.run.hold)))
                    ).toFixed(1)}
                  />
                </svg>
                <div className="fs-hold-text">
                  <strong>{Math.round(questView.run.hold * 100)}%</strong>
                  <span>{questHint}</span>
                </div>
              </div>
              <div className="fs-quest-progress">
                <div className="fs-quest-dots" aria-hidden="true">
                  {questView.run.targets.map((t, i) => (
                    <i
                      key={i}
                      className={
                        i < questView.run.index
                          ? questView.run.outcomes[i] === 'hit'
                            ? 'fs-dot-hit'
                            : 'fs-dot-skip'
                          : i === questView.run.index
                            ? 'fs-dot-now'
                            : ''
                      }
                      title={noteName(t)}
                    />
                  ))}
                </div>
                <p>
                  {questView.run.matched.length} matched
                  {questView.run.skipped
                    ? ` · ${questView.run.skipped} skipped`
                    : ''}{' '}
                  · hold within ±50 cents for one second to advance.
                </p>
                <button type="button" onClick={skipQuestTarget}>
                  <SkipForward size={16} /> Skip this note
                </button>
              </div>
            </div>
          ) : (
            <>
              {questView?.status === 'done' && questView.summary && (
                <div className="fs-quest-summary" aria-live="polite">
                  <strong>{questVerdict(questView.summary)}</strong>
                  <dl>
                    <div>
                      <dt>Matched</dt>
                      <dd>
                        {questView.summary.matched} / {questView.summary.total}
                      </dd>
                    </div>
                    <div>
                      <dt>Average per note</dt>
                      <dd>
                        {questView.summary.averageSeconds === null
                          ? '—'
                          : `${questView.summary.averageSeconds.toFixed(1)} s`}
                      </dd>
                    </div>
                    <div>
                      <dt>Notes matched from</dt>
                      <dd>
                        {questView.summary.low === null
                          ? '—'
                          : `${noteName(questView.summary.low)} to ${noteName(questView.summary.high!)}`}
                      </dd>
                    </div>
                  </dl>
                  <small>
                    {questView.synthetic
                      ? 'Demo results come from the synthetic voice and are not saved.'
                      : questView.saved
                        ? 'Saved to your local practice history.'
                        : 'Nothing matched, so nothing was saved.'}
                  </small>
                </div>
              )}
              <p>
                Pick a low and high note that already feel easy. The quest stays
                inside that range, moves in small steps and never asks for more.
                Each target is played once on the piano; sing it back and hold
                it for about a second to move on.
              </p>
              <div className="fs-settings fs-quest-settings">
                <label>
                  Comfortable low note
                  <select
                    value={questLow}
                    onChange={(e) =>
                      saveQuestSettings({ low: Number(e.target.value) })
                    }
                  >
                    {Array.from(
                      { length: QUEST_HIGHEST - QUEST_LOWEST + 1 },
                      (_, i) => QUEST_LOWEST + i,
                    ).map((n) => (
                      <option key={n} value={n}>
                        {noteName(n)}
                      </option>
                    ))}
                  </select>
                </label>
                <label>
                  Comfortable high note
                  <select
                    value={questHigh}
                    onChange={(e) =>
                      saveQuestSettings({ high: Number(e.target.value) })
                    }
                  >
                    {Array.from(
                      { length: QUEST_HIGHEST - QUEST_LOWEST + 1 },
                      (_, i) => QUEST_LOWEST + i,
                    ).map((n) => (
                      <option key={n} value={n}>
                        {noteName(n)}
                      </option>
                    ))}
                  </select>
                </label>
                <label>
                  Number of targets
                  <select
                    value={questCount}
                    onChange={(e) =>
                      saveQuestSettings({ count: Number(e.target.value) })
                    }
                  >
                    {QUEST_COUNTS.map((n) => (
                      <option key={n} value={n}>
                        {n} notes
                      </option>
                    ))}
                  </select>
                </label>
              </div>
              <div className="fs-warm-actions">
                <small>
                  Targets land between {noteName(questRangeLow)} and{' '}
                  {noteName(questRangeHigh)}. Skip any note that does not feel
                  easy today.
                  {demo &&
                    ' In demo mode a synthetic voice sings the targets for you.'}
                </small>
                <button
                  className="fs-primary"
                  onClick={() => void startQuest()}
                >
                  <Target size={16} />{' '}
                  {questView?.status === 'done'
                    ? 'Start another quest'
                    : demo
                      ? 'Start demo quest'
                      : 'Start quest'}
                </button>
              </div>
            </>
          )}
        </section>
      )}
      {showConsole && (
        <section className="fs-roll-section" aria-label="Live piano roll">
          <div className="fs-roll-toolbar">
            <span>
              <i />{' '}
              {replay
                ? 'Recorded pitch'
                : demo
                  ? 'Synthetic pitch · demo'
                  : 'Your pitch'}{' '}
              {referenceNote !== null && (
                <span className="fs-target-label">
                  · reference {noteName(referenceNote)}
                </span>
              )}
            </span>
            <select
              aria-label="Piano scrolling"
              value={follow ? 'follow' : 'browse'}
              onChange={(e) => setFollow(e.target.value === 'follow')}
            >
              <option value="follow">
                {demo ? 'Follow the demo voice' : 'Follow my voice'}
              </option>
              <option value="browse">Browse all notes</option>
            </select>
          </div>
          {/* eslint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- Scroll viewport supports native keyboard scrolling. */}
          <div
            ref={roll}
            className="fs-roll"
            aria-label="Piano roll from C7 to C1. Scroll to see every semitone."
          >
            <div className="fs-roll-inner">
              {Array.from({ length: 73 }, (_, i) => 96 - i).map((n) => (
                <div
                  key={n}
                  className={`fs-row ${[1, 3, 6, 8, 10].includes(n % 12) ? 'fs-black' : ''} ${nearest === n ? 'fs-active' : ''} ${referenceNote !== null && Math.round(referenceNote) === n ? 'fs-target-row' : ''}`}
                >
                  <button
                    type="button"
                    className={`fs-key ${playedNote === n ? 'fs-key-playing' : ''}`}
                    aria-label={`Play ${noteName(n)}`}
                    onClick={() => void playKey(n)}
                    title={`Play ${noteName(n)}`}
                  >
                    {noteName(n)}
                  </button>
                  <span className="fs-row-line" />
                  {nearest === n && (
                    <span className="fs-row-label">{noteName(n)}</span>
                  )}
                </div>
              ))}
              <svg
                className="fs-trace"
                viewBox="0 0 810 2044"
                preserveAspectRatio="none"
                aria-label={
                  demo
                    ? 'Ten-second synthetic pitch trail (demo)'
                    : 'Ten-second pitch trail'
                }
              >
                <path d={path('target')} className="fs-reference-path" />
                <path d={path('midi')} className="fs-voice-path" />
              </svg>
            </div>
          </div>
          <div className="fs-time">
            <span>
              {replay
                ? formatTime(Math.max(0, playhead - 10))
                : '10 seconds ago'}
            </span>
            <span>{replay ? formatTime(playhead) : 'Now'}</span>
          </div>
        </section>
      )}
      {mode === 'sing' && !demo && (
        <div className="fs-bottom fs-bottom-single">
          <section className="fs-panel">
            <div className="fs-panel-heading">
              <h2>Your takes</h2>
              <span>{takes.length} this session</span>
            </div>
            <p>
              Replay with the pitch trail. Download anything you want to keep
              before closing or refreshing this page.
            </p>
            {selectedTake && (
              <div className="fs-player">
                <strong>Take {selectedTake.id}</strong>
                {/* User-created audio has no transcript; its synchronized pitch trace is provided above. */}
                {/* oxlint-disable-next-line jsx-a11y/media-has-caption */}
                <audio
                  ref={audio}
                  key={selectedTake.url}
                  src={selectedTake.url}
                  controls
                  onPlay={() => {
                    stopInput();
                    stopWarmup();
                    setPlaying(true);
                  }}
                  onPause={() => setPlaying(false)}
                  onEnded={() => setPlaying(false)}
                  onTimeUpdate={(e) => setPlayhead(e.currentTarget.currentTime)}
                  onSeeked={(e) => setPlayhead(e.currentTarget.currentTime)}
                />
                <small>
                  The trail shows the notes detected during recording, including
                  any reference targets.
                </small>
              </div>
            )}
            {!takes.length && (
              <div className="fs-empty">
                Your first take starts with the red circle above.
              </div>
            )}
            <div className="fs-takes">
              {takes.map((t) => (
                <div key={t.id}>
                  <button onClick={() => selectTake(t)}>
                    <Play size={15} />
                    Take {t.id}
                    <span>{formatTime(t.duration)}</span>
                  </button>
                  <a
                    href={t.url}
                    download={`free-sing-take-${t.id}.${t.extension}`}
                    aria-label={`Download take ${t.id}`}
                  >
                    <Download size={17} />
                  </a>
                </div>
              ))}
            </div>
          </section>
        </div>
      )}
      {mode === 'sing' && demo && (
        <div className="fs-bottom fs-bottom-single">
          <section className="fs-panel">
            <div className="fs-panel-heading">
              <h2>Your takes</h2>
              <span>Hidden in demo</span>
            </div>
            <p>
              Recording and playback are switched off while the demo voice is
              running, so synthetic pitch never mixes with your real takes.
              {takes.length
                ? ` Your ${takes.length} recorded take${takes.length === 1 ? '' : 's'} from this session will be here when you exit demo.`
                : ''}
            </p>
            <button type="button" onClick={exitDemo}>
              <X size={16} /> Exit demo
            </button>
          </section>
        </div>
      )}
      {mode === 'warmups' && (
        <div className="fs-bottom fs-bottom-single">
          <section className="fs-panel">
            <div className="fs-panel-heading">
              <h2>Warm-up settings</h2>
              <span>Piano + pulse</span>
            </div>
            <p>
              Listen first, then repeat the same notes with no piano playing.
              Starting a warm-up turns on your microphone for pitch feedback.
              Use headphones for the metronome. Keep every note comfortable.
              {demo &&
                ' In demo mode the synthetic voice sings the repeat instead.'}
            </p>
            <div className="fs-settings">
              <label>
                Pattern
                <select
                  disabled={warming}
                  value={drill}
                  onChange={(e) => setDrill(e.target.value as Drill)}
                >
                  <option value="arpeggio">Octave arpeggio · 1–3–5–8</option>
                  <option value="five-note">Five-note scale · 1–2–3–4–5</option>
                </select>
              </label>
              <label>
                Starting note
                <select
                  disabled={warming}
                  value={root}
                  onChange={(e) => setRoot(Number(e.target.value))}
                >
                  {Array.from({ length: 37 }, (_, i) => 36 + i).map((n) => (
                    <option key={n} value={n}>
                      {noteName(n)}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                Upward semitone steps
                <select
                  disabled={warming}
                  value={steps}
                  onChange={(e) => setSteps(Number(e.target.value))}
                >
                  {[0, 2, 4, 6, 8, 12].map((n) => (
                    <option key={n} value={n}>
                      {n} {n === 0 ? '· stay in one key' : ''}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                Tempo
                <select
                  disabled={warming}
                  value={bpm}
                  onChange={(e) => setBpm(Number(e.target.value))}
                >
                  {[50, 60, 70, 80, 90, 100, 120, 140].map((n) => (
                    <option key={n} value={n}>
                      {n} BPM
                    </option>
                  ))}
                </select>
              </label>
            </div>
            <div className="fs-warm-actions">
              <label className="fs-check">
                <input
                  type="checkbox"
                  disabled={warming}
                  checked={metronome}
                  onChange={(e) => setMetronome(e.target.checked)}
                />
                Metronome
              </label>
              <button
                onClick={() => (warming ? stopWarmup() : void startWarmup())}
              >
                {warming ? <Square size={16} /> : <Play size={16} />}{' '}
                {warming ? 'Stop warm-up' : 'Start warm-up'}
              </button>
            </div>
            <output className="fs-warm-status">{warmLabel}</output>
            <small>
              Piano demonstration → four-click count-in → your full singing turn
              → four clicks to breathe → up a semitone. Each note lasts two
              beats. Change tempo between runs. Highest note:{' '}
              {noteName(root + steps + (drill === 'arpeggio' ? 12 : 7))}.
              Piano-like tones are synthesized on your device.
            </small>
          </section>
        </div>
      )}
      {mode === 'history' && (
        <div className="fs-bottom">
          <section className="fs-panel fs-range-panel" aria-label="Range map">
            <div className="fs-panel-heading">
              <h2>Session range map</h2>
              <span>Sustained notes only</span>
            </div>
            <p>
              Notes you held for at least half a second since this page loaded.
              Brief detections are filtered, but sustained tracking errors can
              still occur. This is an observation, not a voice type or a limit.
            </p>
            {demo && (
              <p className="fs-demo-note" aria-live="polite">
                Demo mode is on. The synthetic voice never changes this map.
              </p>
            )}
            <div
              className="fs-range-map"
              aria-label={
                sessionRange.low === null
                  ? 'No sustained notes observed yet this session.'
                  : `This session: ${noteName(sessionRange.low)} to ${noteName(sessionRange.high!)}.${
                      savedLow !== null
                        ? ` All time: ${noteName(savedLow)} to ${noteName(savedHigh!)}.`
                        : ''
                    }`
              }
            >
              <div className="fs-range-track">
                {savedLow !== null && savedHigh !== null && (
                  <i
                    className="fs-range-saved"
                    style={{
                      left: `${mapPercent(savedLow)}%`,
                      width: `${mapPercent(savedHigh) + 100 / RANGE_MAP_SPAN - mapPercent(savedLow)}%`,
                    }}
                  />
                )}
                {sessionRange.low !== null && sessionRange.high !== null && (
                  <i
                    className="fs-range-session"
                    style={{
                      left: `${mapPercent(sessionRange.low)}%`,
                      width: `${mapPercent(sessionRange.high) + 100 / RANGE_MAP_SPAN - mapPercent(sessionRange.low)}%`,
                    }}
                  />
                )}
                {nearest !== null && !demo && (
                  <b
                    className="fs-range-now"
                    style={{
                      left: `${mapPercent(nearest) + 50 / RANGE_MAP_SPAN}%`,
                    }}
                  />
                )}
              </div>
              <div className="fs-range-labels">
                {[36, 48, 60, 72, 84].map((c) => (
                  <span
                    key={c}
                    style={{ left: `${mapPercent(c) + 50 / RANGE_MAP_SPAN}%` }}
                  >
                    {noteName(c)}
                  </span>
                ))}
              </div>
            </div>
            <dl className="fs-facts">
              <div>
                <dt>This session</dt>
                <dd>
                  {sessionRange.low === null
                    ? 'Nothing sustained yet'
                    : `${noteName(sessionRange.low)} – ${noteName(sessionRange.high!)}`}
                </dd>
              </div>
              <div>
                <dt>Span</dt>
                <dd>
                  {rangeSpan(sessionRange.low, sessionRange.high) === null
                    ? '—'
                    : `${rangeSpan(sessionRange.low, sessionRange.high)} semitones`}
                </dd>
              </div>
              <div>
                <dt>All time on this device</dt>
                <dd>
                  {savedLow === null
                    ? '—'
                    : `${noteName(savedLow)} – ${noteName(savedHigh!)}`}
                </dd>
              </div>
            </dl>
            <div className="fs-warm-actions">
              <small>
                <span className="fs-swatch fs-swatch-session" /> This session{' '}
                <span className="fs-swatch fs-swatch-saved" /> All time
              </small>
              <button type="button" onClick={resetSessionRange}>
                <RotateCcw size={16} /> Reset session range
              </button>
            </div>
          </section>
          <section className="fs-panel" aria-label="Practice history">
            <div className="fs-panel-heading">
              <h2>Practice history</h2>
              <span>Saved on this device</span>
            </div>
            <p>
              Time counts while the microphone is listening. Quest bests come
              from real quests only. Demo mode never writes here.
            </p>
            <dl className="fs-facts">
              <div>
                <dt>Time practiced</dt>
                <dd>{formatMinutes(history.seconds)}</dd>
              </div>
              <div>
                <dt>Sessions</dt>
                <dd>{history.sessions}</dd>
              </div>
              <div>
                <dt>Quests</dt>
                <dd>{history.quest.runs}</dd>
              </div>
              <div>
                <dt>Most targets matched</dt>
                <dd>{history.quest.mostMatched || '—'}</dd>
              </div>
              <div>
                <dt>Quickest average per note</dt>
                <dd>
                  {history.quest.quickestAverage === null
                    ? '—'
                    : `${history.quest.quickestAverage.toFixed(1)} s`}
                </dd>
              </div>
              <div>
                <dt>Widest quest</dt>
                <dd>
                  {history.quest.widestLow === null ||
                  history.quest.widestHigh === null
                    ? '—'
                    : `${noteName(history.quest.widestLow)} – ${noteName(history.quest.widestHigh)}`}
                </dd>
              </div>
            </dl>
            <div className="fs-warm-actions">
              <small>
                Stored in this browser’s local storage only. Clearing site data
                also removes it.
              </small>
              <button type="button" onClick={clearHistory}>
                <Trash2 size={16} /> Clear saved history
              </button>
            </div>
          </section>
        </div>
      )}
      <footer className="fs-footer">
        <p>
          <strong>Your voice stays on your device.</strong> Audio is analysed
          in the browser and never uploaded. Recordings are temporary until you
          download them; each take can run for up to 10 minutes, and live
          listening has no timer. No ads, and no account is required. Signing
          in is optional and syncs only your practice calendar, never audio.
        </p>
        <p>
          Pitch estimates can jump with noise, breathiness or multiple sounds.
          This tool cannot identify vocal registers or judge strain. Stop for
          pain or hoarseness. Keep the page open and your device awake;
          background audio depends on your browser.
        </p>
        <div className="fs-footer-links">
          <a
            href="https://www.cuh.nhs.uk/patient-information/semi-occluded-vocal-tract-exercises/"
            target="_blank"
            rel="noreferrer"
          >
            Gentle voice exercise guidance ↗
          </a>
          <a
            href="https://github.com/timkosters/free-sing-studio"
            target="_blank"
            rel="noreferrer"
          >
            <Code size={14} aria-hidden="true" /> Source code ↗
          </a>
        </div>
      </footer>
    </div>
  );
}
