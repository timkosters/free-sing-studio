# From zero to the App Store

Written for Timour (non-engineer). Do the steps in order. Anything marked **YOU** needs your Apple ID,
password or payment card, so it has to be you at the keyboard. Anything marked **R2** I can do once the
step before it is done.

## 0. The Mac needs Xcode (one click from you)

Update Sep 16 evening: macOS is now upgraded (reports 27.0), so the App Store's Xcode 27 installs fine.
The command-line route (`mas install`) needs your admin password, which I cannot type, so:

1. **YOU** The App Store is already open on the Xcode page (or run `open "macappstore://apps.apple.com/app/id497799835"`).
   Click **Get**, then **Install**. About 3 GB download, ~15 GB installed, 15–30 minutes.
2. **YOU** Open Xcode once, accept the license, and let it install the iOS platform when it asks (another ~8 GB).
3. **R2** Everything after that: `xcode-select`, simulators, build, fix compile errors, screenshots, TestFlight.

Note: the Command Line Tools on this Mac were in a broken state (Swift compiler did not match its SDK).
Installing full Xcode replaces them.

## 1. Apple Developer Program ($99/year)

Needed to run on your own iPhone for more than a week, use TestFlight, sell subscriptions, and publish.

1. **YOU** Go to https://developer.apple.com/programs/enroll/ on your Mac or in the Apple Developer app
   on your iPhone (the iPhone app is the fastest path; it verifies your ID with a driver's license or
   passport scan).
2. Enroll as an **Individual** (your name is the seller name) unless you want "Edge City" as the seller,
   in which case enroll as an **Organization**, which needs a D-U-N-S number and a legal entity; that adds
   1–2 weeks. For a personal side project, Individual is right. You can transfer the app to a company
   later.
3. Pay $99. Approval is usually within 48 hours; you get an email.
4. **YOU** Once approved, open App Store Connect → https://appstoreconnect.apple.com and accept the
   agreements. Then go to **Business → Agreements, Tax, and Banking**: accept the **Paid Apps** agreement,
   add bank account and tax forms (W-9 for US). Without this, subscriptions cannot be created.
5. Find your **Team ID**: https://developer.apple.com/account → Membership details. Send it to me. I put it
   into `project.yml` and Xcode signs everything automatically.

## 2. Xcode sign-in (one time)

1. **YOU** Open Xcode → Settings → Accounts → + → Apple ID → sign in with the developer Apple ID.
2. That is all. Xcode creates certificates and provisioning profiles by itself when I build.

## 3. Your iPhone for testing

1. **YOU** Plug the iPhone into the Mac with a cable, unlock it, tap Trust.
2. **YOU** On the iPhone: Settings → Privacy & Security → Developer Mode → on (it restarts).
3. **R2** Build and run to the device. First run asks you to trust the developer certificate:
   Settings → General → VPN & Device Management → your Apple ID → Trust.

## 4. App Store Connect record (R2 walks, YOU click)

Once enrolled, in https://appstoreconnect.apple.com:

1. **Apps → + → New App.** Platform iOS, Name **Singwell**, Primary language English (U.S.),
   Bundle ID `live.singwell.app` (create it at https://developer.apple.com/account/resources/identifiers
   first with capabilities **Sign in with Apple** and **In-App Purchase**), SKU `singwell-ios`.
2. **In-App Purchases and Subscriptions.** Create subscription group "Singwell Pro", then:
   - `live.singwell.pro.monthly` — auto-renewable, 1 month, price tier around $5.99, introductory offer
     1 week free.
   - `live.singwell.pro.yearly` — auto-renewable, 1 year, around $34.99, 1 week free.
   - `live.singwell.pro.lifetime` — non-consumable, around $39.99.
   Each needs a display name, description and a review screenshot (I generate those from the simulator).
3. **App Privacy.** Data not collected. Audio and recordings stay on device. Sign in with Apple gives a
   user identifier, name and email that are stored on device only → declare "Name, Email Address, User ID:
   used for App Functionality, not linked to identity for tracking, not used for tracking".
4. **Age rating:** 4+. **Category:** Music (secondary: Education).
5. **Privacy policy URL** (required). Domain `singwell.io` is available as of Sep 16, 2026 (`singwell.com`
   and `singwell.app` are taken). I can register it via Vercel and publish a one-page privacy policy and
   support page; you approve the purchase (~$40/yr for .io).

## 5. TestFlight

1. **R2** Archive in Xcode, upload to App Store Connect (Xcode → Product → Archive → Distribute → App Store
   Connect). Processing takes 10–30 minutes.
2. **YOU** Install the TestFlight app on your iPhone; I add your Apple ID as an internal tester; you get an
   email. Internal testing needs no review. Up to 100 internal testers; external testers (up to 10,000)
   need one quick beta review.
3. Test on real singing for a week. Mic latency, headphone routing, background behaviour.

## 6. Submit for review

1. Screenshots: 6.9" (iPhone 17 Pro Max class) and 6.5" sets are required. I generate them from the
   simulator with the demo voice so the piano roll shows a trail.
2. App Review notes: mention "Tap 'Try demo voice' in the Sing tab menu to see the pitch display without
   singing", the test Apple ID is not needed (guest mode works), and that all audio stays on device.
3. Common rejection traps I have already handled: privacy manifest present, restore-purchases button,
   subscription terms text on the paywall, Sign in with Apple offered because a third-party login exists
   (only Apple, so compliant), microphone purpose string, no web-view wrapper.
4. Review typically takes 24–48 hours. First submissions get slightly more scrutiny.

## 7. Costs summary

| Item | Cost |
|------|------|
| Apple Developer Program | $99/year |
| Domain singwell.io | ~$40/year |
| Everything else (StoreKit, TestFlight, Sign in with Apple) | included |
| Apple's cut | 30% year one, 15% after a subscriber's first year; 15% from day one if you enroll in the Small Business Program (revenue under $1M), which you should do right after enrolling: https://developer.apple.com/app-store/small-business-program/ |

## 8. What I need from you, in order

1. Click Get on Xcode in the App Store (already open), then open Xcode once and accept the license.
2. Enroll in the Developer Program (Individual), accept agreements, add banking and tax.
3. Send me the Team ID.
4. Sign in to Xcode with the Apple ID.
5. Plug in your iPhone and turn on Developer Mode.
6. Approve the singwell.io domain purchase (or tell me to skip and use a free page for the privacy policy).
