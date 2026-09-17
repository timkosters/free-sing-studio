// What a first-time singer is told, and when to stop telling them.
//
// Three claims and nothing else: the routine decides for you, the app hears the
// note, and turning up is the thing being measured. The privacy line lives in
// the third panel rather than in a banner, because that is the only moment
// somebody is actually asking the question.

export const ONBOARDING_KEY = 'free-sing-onboarded-v1';

export type Panel = {
  id: string;
  title: string;
  body: string;
  /** Which illustration the panel shows. */
  art: 'steps' | 'listen' | 'streak';
};

export const PANELS: Panel[] = [
  {
    id: 'steps',
    title: 'One step at a time',
    body: 'Pick ten, fifteen or twenty minutes. The routine tells you what to do and counts it down, so you never have to decide mid-session. Pause or skip whenever you like.',
    art: 'steps',
  },
  {
    id: 'listen',
    title: 'It hears the note',
    body: 'On the steps that need it, your microphone turns on and the note you are singing appears as you sing it. Breathing steps get a pacer instead, and no microphone at all.',
    art: 'listen',
  },
  {
    id: 'streak',
    title: 'Showing up is the metric',
    body: 'Every session fills a square and extends your streak. Your voice is analysed on this device and never uploaded. An account is optional, and only keeps one streak across your devices.',
    art: 'streak',
  },
];

/**
 * Whether to introduce the app.
 *
 * Someone who has already practised does not need explaining to, even if the
 * flag was lost with their site data, so a non-empty history counts as having
 * seen it. Storage that throws is treated as "already seen": repeating the
 * introduction on every load would be worse than skipping it once.
 */
export function shouldOnboard(
  stored: string | null | undefined,
  hasPractised: boolean,
): boolean {
  if (hasPractised) return false;
  return stored !== 'seen';
}

export const markOnboarded = () => 'seen';
