# Automaid Partner — Rider + Merchant App

Combined app for both roles: riders (pickup/delivery) and merchants
(wash outlets) share this one install. After login, the role on the
account decides which home screen shows — see
`lib/core/router/app_router.dart`.

## Getting the exact package name you asked for

Target: `com.paynwash.automaid.merchantrider`. Same trick as the customer
app — put `automaid` in the org, and the last segment as the project name:

```bash
flutter create --org com.paynwash.automaid --project-name merchantrider automaid_merchantrider_scaffold
```

This gives applicationId / bundle ID = `com.paynwash.automaid.merchantrider`
directly, no manual `build.gradle`/`Info.plist` ID editing needed.

Then bring in this project's code:

```bash
cp -r automaid_merchantrider/pubspec.yaml automaid_merchantrider/lib automaid_merchantrider_scaffold/
cd automaid_merchantrider_scaffold
flutter pub get
flutter run
```

(Optional cosmetic step: rename the folder to `automaid_merchantrider` and
update `pubspec.yaml`'s `name:` field to match — this codebase uses
relative imports throughout, so the pubspec name doesn't affect whether
it compiles.)

## App display name

Currently set to "Automaid Partner" in `lib/main.dart`. After scaffolding,
also update the launcher label in `android/app/src/main/AndroidManifest.xml`
(`android:label`) and `ios/Runner/Info.plist` (`CFBundleDisplayName`).

## Backend URL

Set in `lib/core/auth/auth_providers.dart`:

```dart
const String kApiBaseUrl = 'http://56.69.76.60/api';
```

## Registration (new) — rider & merchant, full flow

Rebuilt from `AUTOMAID_MERCHANT_RIDER_flow_APP_TESTING_-_v3.docx` — I
read the screenshots directly (the doc's text only describes the rider
flow; merchant registration was images-only, including one screenshot
of a validation-error dialog that conveniently listed every required
merchant field in one shot).

**Flow**: `/register` → `RegisterRoleScreen` (rider vs merchant, then
Gig Worker/Staff or Outlet Partner/Auto Maid Outlet) → the matching
`RegisterRiderScreen` / `RegisterMerchantScreen` (all fields on one
scrollable step, matching the real app's Step 2/3 layout) → document
upload (Step 3/3) → OTP verification → `/pending` (a "waiting admin
approval" screen) until the admin approves the entity, at which point
the router sends them straight to the normal dashboard.

Both registration screens submit as a **single multipart request**
(text fields + documents together), matching exactly what
`RiderController::register` / `MerchantController::register` expect —
not two separate calls.

### The JPJ Grant gap — fixed

The flow doc explicitly flagged (item #49) that the previous app never
collected the JPJ Grant document even though the backend has always
accepted it (`jpj_grant` field, fully wired server-side). Rider
registration now collects all 5 documents (IC front/back, license
front/back, **and JPJ grant**) and won't let you continue until all 5
are attached — this was the one deliberate behavior change beyond
straight reconstruction of the existing flow.

### Field choices I had to infer

A few dropdown option sets weren't fully visible in the doc's
screenshots (only one selected value was shown per field), so I used
reasonable defaults — check these against the real admin panel /
backend seed data and adjust if they don't match exactly:
- ID Type: NRIC, Passport
- Vehicle type: Motorcycle, Car, Van, Bicycle
- Vehicle colour: Black, White, Red, Blue, Silver, Other (+ free-text "other" field, matches the doc)
- Business options (merchant): Corporate, Sole Proprietor, Partnership (the doc only showed "Corporate" selected)

State and bank are both fetched live from the backend (`/state/index`,
`/banks/index`) rather than hardcoded — same reasoning as the customer
app's state dropdown fix (free-text state entry broke there because the
seeded data uses non-obvious names).

### Address entry — adapted, not a pixel-perfect copy

The real app uses a Google Places-style landmark search that
auto-fills address fields. I used the same map-pin picker
(`MapPickerScreen`, copied from the customer app, already proven
working) plus manually-typed address fields instead — functionally
equivalent (collects the same data: address lines, postcode, city,
state, lat/lng), but not the same autocomplete UX. Wiring up real Places
Autocomplete is a reasonable next step if you want the exact same feel,
but needs a Places API key and a fair bit more code.

## What's included

- **Rider**: home with duty toggle + Today/Incoming job tabs, accept →
  pickup → outlet-pickup → deliver actions, QR scan, delivery-proof photo
  upload, read-only profile with wallet/activity.
- **Merchant**: home screen stub only — the merchant module (bag receive,
  wash-complete, city/duty selection) hasn't been built out yet. Same
  pattern as rider once you're ready: repository wrapping `/merchant/*`
  routes, Riverpod providers, then screens.

Login is shared — one screen, same as the customer app. A customer
account logging in here gets logged straight back out (see the router's
redirect logic) rather than shown a broken screen, since this app has no
customer-facing screens.

## Known gaps (carried over from the single-app version)

- Rider profile editing and the rejected-rider re-apply flow need large
  multipart forms — documented with exact field lists in
  `lib/features/rider/data/rider_repository.dart`.
- No push notification listener yet (FCM/OneSignal) — job lists refresh
  on pull-to-refresh or after an action only.
- **Merchant home module is still a stub** — `merchant_home_screen.dart`
  is a placeholder only. Registration now works end-to-end for merchants,
  but there's no bag-receive/wash-complete/scan flow yet — same pattern
  as the rider module (repository → providers → screens) whenever you're
  ready for it.
- App icon generation needs `dart run flutter_launcher_icons` locally
  (can't run Flutter tooling from here) — see the Branding section above
  in the customer app's README for the exact steps; same command applies
  here with this project's own `assets/icon/app_icon.png`.
- `google_fonts` downloads Baloo 2 at runtime rather than bundling it —
  needs internet the first time a themed screen loads.
