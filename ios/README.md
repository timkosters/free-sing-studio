# Singwell (iOS)

Native SwiftUI port of the Free Sing web app, rebuilt as a paid-tier iPhone app.

**What it does:** live pitch on a chromatic piano roll, reference piano tones, recordings with the
pitch trail attached, a ten-minute guided daily routine with streaks, call-and-response warm-ups,
Pitch Quest, and a range map. Sign in with Apple (or guest), StoreKit 2 subscriptions, no backend.
Audio never leaves the device.

## Layout

| Path | What |
|------|------|
| `project.yml` | XcodeGen spec. Run `xcodegen generate` to (re)create `Singwell.xcodeproj`. |
| `Packages/SingwellCore` | Pure logic: YIN pitch detection, warm-up plans, quest, history, daily routines, demo voice. Platform-agnostic, fully unit-tested. |
| `Singwell/App` | App entry and root tab view. |
| `Singwell/Audio` | AVAudioEngine wrapper, additive tone synth, AAC take recorder, take player. |
| `Singwell/Features/Shared/PracticeSession.swift` | The state machine (port of the web app's session logic). |
| `Singwell/Features/*` | SwiftUI views per tab: Daily, Sing, Train (warm-ups + quest), Library, Progress, Account, Onboarding. |
| `Singwell/Services` | Settings, progress store, take library, Sign in with Apple, StoreKit, haptics, reminders. |
| `Singwell/Resources` | Assets, entitlements, privacy manifest, `Products.storekit` for local IAP testing. |
| `docs/APP_STORE_SETUP.md` | Step-by-step from zero to TestFlight and App Store. |

## Build

Requires Xcode 26 or newer (iOS 17 deployment target).

```bash
brew install xcodegen          # once
xcodegen generate              # after editing project.yml
open Singwell.xcodeproj
```

In Xcode: select the `Singwell` scheme and an iPhone simulator, press Run. The scheme uses
`Products.storekit`, so the paywall works offline with fake purchases.

Before first device build: set `DEVELOPMENT_TEAM` in `project.yml` (your Team ID from App Store Connect),
regenerate, and let Xcode manage signing automatically.

## Test

Core logic (works anywhere Swift runs, including Docker):

```bash
cd Packages/SingwellCore && swift test
# or without a local toolchain:
docker run --rm -v "$PWD":/pkg -w /pkg swift:6.0-noble swift test
```

App tests (needs Xcode): `xcodebuild test -scheme Singwell -destination 'platform=iOS Simulator,name=iPhone 16'`.

## Product IDs

| ID | Type | Price (StoreKit config) |
|----|------|------|
| `live.singwell.pro.monthly` | Auto-renewing, 1 week free | 5.99 |
| `live.singwell.pro.yearly` | Auto-renewing, 1 week free | 34.99 |
| `live.singwell.pro.lifetime` | Non-consumable | 39.99 |

Real prices are set in App Store Connect; the app reads `displayPrice` from StoreKit.

## Free vs Pro

Free: live pitch roll, reference piano, 3 saved takes, Quick routine, quests up to 5 targets,
arpeggio drill up to 4 semitones, range map and history. Pro removes every ceiling. Gates live in
`Services/StoreService.swift` (`Entitlements`).
