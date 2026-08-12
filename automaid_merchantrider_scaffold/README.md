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

## Google Maps setup — REQUIRED, and very likely why the pin-map screen crashes

`google_maps_flutter` is used on the address-pinning step in both rider
and merchant registration (`MapPickerScreen`). It needs an API key wired
into each platform's native config — this can't be done from inside
`lib/`, so it wasn't included when I built the registration screens, and
this project's setup steps were never written down anywhere. **A
missing/invalid key here doesn't fail gracefully — it crashes the native
Android map view**, which is exactly what "blank screen then the app
restarts" looks like. This is the first thing to check.

Do this after scaffolding:

**Android** — in `android/app/src/main/AndroidManifest.xml`, inside the
`<application>` tag:
```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="YOUR_GOOGLE_MAPS_API_KEY"/>
```
Also add the location permission (needed for the "use current location"
button):
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
```

**iOS** — in `ios/Runner/AppDelegate.swift`, add before `return super...`:
```swift
GMSServices.provideAPIKey("YOUR_GOOGLE_MAPS_API_KEY")
```
And in `ios/Runner/Info.plist`, add a location-usage description:
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Automaid Partner needs your location to pin your address accurately.</string>
```

Get an API key from the [Google Cloud Console](https://console.cloud.google.com/google/maps-apis)
with "Maps SDK for Android" and "Maps SDK for iOS" enabled, and billing
active on that project — this is separate from any key you may already
have for the customer app (a key can be reused across projects, but
billing/quota is shared, so keep that in mind if usage is high).

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

## Merchant home module (new)

Built out following the exact same pattern as the rider module — repository
wrapping the confirmed-working `/merchant/*` routes, Riverpod providers,
then screens:

- **Home** — duty toggle, Today/Incoming job tabs, one contextual action
  button per job matching its exact status code (see `MerchantStatusCode`
  in `lib/core/models/assign_job_model.dart` for the full code → action
  mapping, traced from `OrderStatus.php` and the three merchant
  controllers). Codes 21/22/23 are actionable (accept → receive bag →
  mark wash complete); 24/25/26 are informational.
- **Scan** — camera QR scan of a bag to see the customer's bookings for
  today, same pattern as the rider scan screen.
- **Order detail** — simpler than the rider version since there's no
  delivery-proof-photo step on the merchant side.
- **Profile** — read-only wallet balance + recent activity.

### A real bug found and fixed while building this

Tracing the merchant endpoints, I found the exact same silent-failure bug
that was fixed in the customer app a while back was **also present in
both this app's rider and merchant repositories** — `ApiClient` never
checked the backend's `status: false` flag, so any method that indexed
straight into `json['data']['x']` on a business-logic failure (e.g. the
backend's own "Rider not pickup yet." message when bag-receiving too
early) would throw an uncatchable Dart type error instead of a visible
message. Added the same `unwrapData()` fix
(`lib/core/api/api_data_helper.dart`) to **both** repositories — this
wasn't just a merchant-specific fix, it makes the whole app more honest
about backend errors going forward.

### Known gap: city selection

`POST /merchant/home/city` is routed to `HomeController::selectCity`,
but that method doesn't actually exist in the controller as shipped on
the server — calling it would 500. Not wired up in the app until the
backend implements it (documented in `merchant_repository.dart`).

## Profile editing (new) — rider & merchant

Both read-only profile screens now have a working edit icon in the app
bar, opening `RiderProfileEditScreen` / `MerchantProfileEditScreen` —
matches `RiderProfileController::profileUpdate` /
`Api/Merchant/ProfileController::profileUpdate` exactly (name, mobile,
IC, address with the same map-pin picker used everywhere else, bank
info, avatar upload, plus emergency contact for riders / equipment +
company info for merchants). Pre-fills from the data already loaded on
the profile screen, so opening Edit doesn't need a second network call.

## Photo + remark capture at handoff steps (new)

Matches the booking flow spec's requirement to photograph/annotate each
handoff, replacing reliance on QR alone. Both apps share one bottom
sheet (`lib/core/widgets/photo_remark_capture.dart`) — camera capture +
optional note — shown before confirming:

- **Rider**: pickup from customer / delivered to outlet (one combined
  action, matching how this backend already structures that step),
  and pickup from outlet.
- **Merchant**: bag received (wash starting), and wash complete.

Both are optional — dismissing the sheet cancels the action entirely
(no accidental "confirm with no photo"), but tapping "Confirm without
photo" explicitly skips it if there's nothing worth capturing. Final
delivery-to-customer already had its own dedicated multi-photo flow
before this patch (`RiderOrderDetailScreen`) — untouched.

Needs the matching backend patch (`automaid_backend_step_photos.zip`)
deployed first — these calls send `image`/`remark` as optional
multipart fields the backend now accepts on all 4 endpoints.

## Known gaps (carried over from the single-app version)

- The rejected-rider and rejected-merchant re-apply flows still need
  their own multipart forms — documented with exact field lists in
  `lib/features/rider/data/rider_repository.dart` and
  `lib/features/merchant/data/merchant_repository.dart`.
- No push notification listener yet (FCM/OneSignal) — job lists refresh
  on pull-to-refresh or after an action only.
- App icon generation needs `dart run flutter_launcher_icons` locally
  (can't run Flutter tooling from here) — see the Branding section above
  in the customer app's README for the exact steps; same command applies
  here with this project's own `assets/icon/app_icon.png`.
- `google_fonts` downloads Baloo 2 at runtime rather than bundling it —
  needs internet the first time a themed screen loads.
