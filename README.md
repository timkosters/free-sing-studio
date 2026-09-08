# Free Sing

A free, browser-only singing companion. Everything runs on your device: live pitch tracking on a chromatic piano roll, temporary recordings with synchronized pitch-trail replay, optional call-and-response warm-ups, a gentle Pitch Quest, a session range map with local practice history, and a labeled demo mode that needs no microphone.

Source: <https://github.com/timkosters/free-sing-studio>

Try it: <https://free-sing-studio.vercel.app>

## What it does

**Free sing** (default view) shows your detected note, frequency and cents offset while a ten-second pitch trail scrolls across a C1–C7 piano roll. Click any key to hear a locally synthesized reference tone. Record a take, replay it with its pitch trail, and download it. Takes live in memory only; refreshing or closing the page discards them. Each take is limited to ten minutes, while listening has no timer.

**Warm-ups** are optional and live in their own tab. Each round runs: piano demonstration → four-click count-in → your full singing pass with the piano silent → four clicks to breathe → up a semitone. Choose an octave arpeggio or five-note scale, the starting note, how many semitones to climb, and the tempo. Each sung note is labeled Hit, Low, High, Keep steady, or No clear pitch.

**Pitch Quest** gives one piano target at a time inside a low/high range you choose. Sing it back within ±50 cents and hold it for about one second; a ring fills as you hold and drains (rather than resetting) if you wobble. Targets never leap more than five semitones, never leave your chosen range, and any note can be skipped. A summary shows how many targets matched, the average time per note and the notes covered.

**Range & history** shows a session range map built from notes detected for at least half a second. Brief detections are filtered; sustained tracking errors can still occur. It is an observation of what was detected, not a voice type or a limit. Practice history (time listened, sessions, quest bests, all-time observed range) is stored in this browser's `localStorage` and can be cleared with one button.

**Try demo** switches the whole app to a synthetic voice. No microphone permission is requested, the trace turns violet, panels are labeled as synthetic, and recording is disabled. Demo results are illustrative and never enter saved practice history or the observed range map. The synthetic singer follows quest targets (with an occasional deliberate correction) and wanders a short melody in free-sing view, which makes it suitable for recording a public walkthrough.

## Privacy and browser limitations

- Audio never leaves the device. There are no uploads, accounts, analytics or third-party requests. Reference tones are synthesized locally.
- Recordings are temporary until you download them. Practice history, quest settings and theme preference persist in this browser's `localStorage`; clearing site data removes them.
- Microphone access requires HTTPS or `localhost` and a browser with `getUserMedia` (current Chrome, Safari, Firefox, Edge). Recording additionally requires `MediaRecorder`; without it the pitch display still works.
- The detector estimates a single (monophonic) pitch from about C1 to C7. Estimates can jump with background noise, breathiness or several sounds at once, and sustained octave errors are possible. It cannot identify vocal registers, judge strain or measure a "true" range.
- Mobile browsers may suspend audio when the page is in the background or the screen locks. Keep the page open and the device awake.
- Use headphones during warm-ups and quests so the microphone does not pick up the reference tones.

## Development

Run `npm ci`, then `npm run dev`.

Run `npm run lint`, `npx tsc --noEmit`, `npm test`, and `npm run build:vercel` before deployment. Vercel serves `dist-vercel` as a static app.

Pure logic lives in `lib/` and is covered by Node tests in `tests/`:

- `lib/pitch.ts` — YIN pitch detection, note naming and chart bounds.
- `lib/warmup.ts` — warm-up beat plans and per-note scoring.
- `lib/quest.ts` — quest range normalization, gentle target sequences, hold accumulation and run summaries.
- `lib/history.ts` — sustained-note range tracking, history parsing/merging and time formatting.
- `lib/demo.ts` — the deterministic synthetic voice used by demo mode.
