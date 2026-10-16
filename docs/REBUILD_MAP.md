# Bond Touch → iOS: 1:1 rebuild map

Faithful feature-for-feature rebuild of the official app (`com.impossible.bondtouch`
v11.2.0), reverse-engineered for an interoperable, **open-source**, **no-paywall** iOS
client. This tracks every feature area, its iOS mapping, and build status.

## Platform mapping (applies everywhere)

| Original (Android) | iOS rebuild |
|---|---|
| Jetpack Compose | SwiftUI |
| Firebase Auth / accounts | Sign in with Apple + CloudKit user record |
| Firebase Realtime DB / `api.bond-touch.com` relay | **CloudKit** shared zones (no app server) |
| FCM push | APNs + CloudKit silent push |
| SQLCipher local DB | SQLite with SQLCipher *or* CoreData + file protection |
| libsignal (E2E chat / Private Space) | Signal-protocol Swift, or CryptoKit-based E2E |
| Google Maps / Street View (`presence`/`map`) | MapKit |
| Segment + `track-prod.api.bond-touch.com` | **removed** (no telemetry) |
| Google Play Billing (`billing`, subscriptions) | **removed** (no paywalls — all features free) |
| Wear OS companion (`wear`) | Apple Watch app (later phase) |
| App Widgets (`widget`) | WidgetKit (later phase) |

## Feature areas (from decompiled `com.impossible.bondtouch`)

### Core — touch & pairing  ✅ protocol done, UI in progress
- BLE v3 protocol (service `d3c00003…`, FFB1/FFB2) — **done** (`BondGATT`, `BraceletManager`, `docs/BLE_PROTOCOL.md`).
- Pair bracelet (`connect/`: ConnectActivity, ConnectSearching/Setup) — scan, connect, firmware-update gate.
- Pair with a partner (`invitation/`, `people/`) — invite code / link → CloudKit share. **done (relay).**
- Send/receive touch (rhythm + colour) — **done (relay + BLE).**
- Touch meanings (`touchmeaning/`, `MeaningMessage`) — assign label/emoji/colour to a touch pattern.

### Messaging & history
- Partner chat (`ChatMessage`, `ChatMessageViewModel`) — text + touch, Signal-encrypted.
- History (`history/`, `HistoryMessage`) — log of sent/received touches & messages.
- Touch "test" / delivery status (`TestMessage`, `SentMessage`, `ReceivedMessage`).

### Heartbeat sharing (`heartble/`, `heartcommon/`, `ecg.dat`)  ✅ HealthKit-based
- Original derived BPM from camera PPG (`HeartBeatFrameAnalyzer`, RR intervals) + a heart BLE device.
- iOS rebuild reads BPM from **HealthKit** (Apple Watch), relays it over CloudKit, and the
  partner's device beats their bracelet at that BPM via the 0x26 motor command.
  `HeartRateService`, `CloudRelay.sendHeartbeat`, `BraceletManager.startHeartbeat`, `HeartView`.

### Presence (`presence/`, `ui/compose/presence/`, `encounters/`)
- Presence+ (was a subscription — now free): live online/near presence, "encounters" when partners are close, partner map.

### Private Space (`privatespace/`, Signal pre-keys in `models/`)
- Passcode-locked private photo gallery + chat, E2E-encrypted (X3DH + Kyber pre-keys).

### Profile & onboarding (`profile/`, `tutorials/`, `walkthrough/`, `entry/`)
- Profile setup: username, colour, vibration pattern, birthday.
- Tutorials (classic + v3 interactive), add-partner walkthrough.

### Settings (`settings/`, many `Settings*ViewModel`)
- Device (bracelet) settings: notifications, vibration strength, DnD, privacy.
- User: profile colour, vibration, username, passcode, language, temperature units.
- Partner settings, help/report a problem, data sharing, parental consent.

### Dropped
- `billing/`, `BtlBuySubscription*`, `PresencePlusSubscription*` — no paywalls.
- `analytics/`, Segment, `track-prod` — no telemetry.

## Build order (incremental, each verified by `ios-build-check.yml`)
1. ✅ BLE protocol + relay + send/receive touch.
2. Navigation shell + Dashboard + History + Touch meanings + Settings skeleton.  ← current
3. Partner chat (text + touch) over CloudKit.
4. Bracelet pairing/connect flow + firmware-update gate (Nordic DFU → iOS DFU lib).
5. Presence / encounters / map (MapKit).
6. ✅ Heartbeat sharing via HealthKit → partner's bracelet.
7. Private Space (E2E gallery/chat).
8. WidgetKit, then Apple Watch app.

Progress is tracked here; decompiled reference stays in scratch, never committed.
