# Bond-touch-beyond

An open-source SwiftUI reimplementation of Bond Touch for iOS: paired bracelets, touches relayed through iCloud/CloudKit, no telemetry, no paywalls.

## Repo layout

- `Sources/` — the iOS app (SwiftUI, CoreBluetooth, CloudKit).
- `docs/` — reference documentation of the original app and the BLE protocol.
- `.github/workflows/` — CI: `ios-build-check.yml` compiles for the simulator on every push; `ios-testflight.yml` and `download-xapk.yml` (below).

TestFlight: commit with `*u` in the subject to upload, `*b` to archive only. See `.github/workflows/ios-testflight.yml`.

Android XAPK: Actions → Download Bond Touch XAPK → Run workflow fetches `com.impossible.bondtouch` from APKPure (default versionCode 490, armeabi-v7a, SDK 29; clear the version code for the latest) as an artifact, optionally a release. See `.github/workflows/download-xapk.yml`.

## Docs

- [docs/FEATURES.md](docs/FEATURES.md) — feature inventory of the original app, organized by feature area, with data models and sync behavior.
- [docs/BLE_PROTOCOL.md](docs/BLE_PROTOCOL.md) — the Bond Touch bracelet and Bond Heart BLE protocol: UUIDs, opcodes, frame layouts, state machine, and DFU.
- [docs/DATA_MODEL.md](docs/DATA_MODEL.md) — backend and data layer: Room schema, REST API, Firebase usage, crypto, and the hosts/telemetry the port avoids.
