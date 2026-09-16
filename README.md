# Free Sing

A free, browser-only singing companion. Everything runs on your device: a guided daily practice routine with streak tracking, live pitch tracking on a chromatic piano roll, temporary recordings with synchronized pitch-trail replay, optional call-and-response warm-ups, a gentle Pitch Quest, a session range map with local practice history, and a labeled demo mode that needs no microphone.

Source: <https://github.com/timkosters/free-sing-studio>

Try it: <https://free-sing-studio.vercel.app>

## What it does

**Daily practice** (default view) runs a guided routine one step at a time on a clock. Three lengths: Quick (11 min), Full (20 min) and Bridge focus (15 min). Each step shows one instruction, a short list of cues, a countdown and the teacher note it came from. Breathing steps show an expand/hold/release pacer instead of a clock; steps that show your own pitch turn the microphone and piano roll on, and the others leave it off. Pause, step back, skip ahead or end early at any point; time already practised is banked either way. A streak counter, a 28-day calendar and lifetime totals are stored in this browser's `localStorage` under `free-sing-daily-v1`.

The routine content is specific rather than generic: cord closure ("goo"), the chest-to-head bridge, belly breath, forward low notes and breath-control ratios, in the order a teacher would run them.

**Free sing** shows your detected note, frequency and cents offset while a ten-second pitch trail scrolls across a C1–C7 piano roll. Click any key to hear a locally synthesized reference tone. Record a take, replay it with its pitch trail, and download it. Takes live in memory only; refreshing or closing the page discards them. Each take is limited to ten minutes, while listening has no timer.

**Warm-ups** are optional and live in their own tab. Each round runs: piano demonstration → four-click count-in → your full singing pass with the piano silent → four clicks to breathe → up a semitone. Choose an octave arpeggio or five-note scale, the starting note, how many semitones to climb, and the tempo. Each sung note is labeled Hit, Low, High, Keep steady, or No clear pitch.

**Pitch Quest** gives one piano target at a time inside a low/high range you choose. Sing it back within ±50 cents and hold it for about one second; a ring fills as you hold and drains (rather than resetting) if you wobble. Targets never leap more than five semitones, never leave your chosen range, and any note can be skipped. A summary shows how many targets matched, the average time per note and the notes covered.

**Range & history** shows a session range map built from notes detected for at least half a second. Brief detections are filtered; sustained tracking errors can still occur. It is an observation of what was detected, not a voice type or a limit. Practice history (time listened, sessions, quest bests, all-time observed range) is stored in this browser's `localStorage` and can be cleared with one button.

**Try demo** switches the whole app to a synthetic voice. No microphone permission is requested, the trace turns violet, panels are labeled as synthetic, and recording is disabled. Demo results are illustrative and never enter saved practice history or the observed range map. The synthetic singer follows quest targets (with an occasional deliberate correction) and wanders a short melody in free-sing view, which makes it suitable for recording a public walkthrough.

**Sync** is optional and off unless the deployment is configured for it. Signing in with an emailed six-digit code mirrors the practice calendar so one streak follows you between devices. Only the calendar is stored server-side: the day, seconds practised, steps finished and whether the routine was completed. No audio, no recordings and no range data ever leave the device. Signing out leaves everything in this browser untouched.

## Optional sync setup

Skip this entirely to run the app with no accounts and no backend. To enable it:

1. Create a free project at <https://supabase.com>.
2. In the SQL Editor, run `supabase/schema.sql`. It creates `practice_days` and the row-level-security policies that keep each singer to their own rows.
3. **Edit the email template.** Under Authentication → Emails → Magic Link, make sure the body contains `{{ .Token }}`. Supabase ships a template that only sends a clickable link; this app asks for a six-digit code, so without the token the email arrives with nothing to type.
4. Copy the Project URL and the `anon` public key from Project Settings → API.
5. Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` (see `.env.example`) locally, and as environment variables on the host. They are build-time values, so redeploy after adding them.

Supabase's built-in email sender is rate limited to a handful of messages an hour, which is fine for personal use. For anything wider, set custom SMTP under Authentication → Emails.

The auth client is code-split and fetched only when the sync panel is opened or a stored session already exists, so visitors who never sign in do not download it.

## Privacy and browser limitations

- Audio never leaves the device. There are no uploads, accounts, analytics or third-party requests. Reference tones are synthesized locally.
- Recordings are temporary until you download them. Practice history, the daily streak calendar, quest settings and theme preference persist in this browser's `localStorage`; clearing site data removes them. There is no account, so progress does not follow you to another browser or device.
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
- `lib/daily.ts` — the practice routines, plus day keys, streaks and the local practice calendar.
- `lib/sync.ts` — row mapping, the calendar merge rule and the auth message translations.

`lib/supabase.ts` holds the lazily-imported client and is deliberately thin, so everything worth testing stays in `lib/sync.ts`.
