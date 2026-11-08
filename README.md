# Bond-touch-beyond

An open-source SwiftUI reimplementation of Bond Touch for iOS: paired bracelets, touches relayed through iCloud/CloudKit, no telemetry, no paywalls.

The app does not talk to Bond Touch's own servers. Partners sync through your own iCloud (CloudKit) and, for Android pairing, your own Firebase project; the bracelet and the Bond Heart pendant are driven directly over Bluetooth. Partners on the original Bond Touch app are no longer supported. The bridge to Bond's servers that earlier versions had is documented in [docs/BOND_TOUCH_CLOUD.md](docs/BOND_TOUCH_CLOUD.md) and archived (not compiled) in `archive/bond-touch-cloud/`.

## Repo layout

- `Sources/` — the iOS app (SwiftUI, CoreBluetooth, CloudKit).
- `docs/` — reference documentation of the original app and the BLE protocol.
- `archive/bond-touch-cloud/` — the removed Bond Touch server code, kept for reference only (outside every target).
- `.github/workflows/` — CI: `ios-build-check.yml` compiles for the simulator on every push; `ios-testflight.yml` and `download-xapk.yml` (below).

TestFlight: commit with `*u` in the subject to upload, `*b` to archive only. See `.github/workflows/ios-testflight.yml`.

Android XAPK: Actions → Download Bond Touch XAPK → Run workflow fetches `com.impossible.bondtouch` from APKPure (default versionCode 490, armeabi-v7a, SDK 29; clear the version code for the latest) as an artifact, optionally a release. See `.github/workflows/download-xapk.yml`.

## Docs

- [docs/FEATURES.md](docs/FEATURES.md) — feature inventory of the original app, organized by feature area, with data models and sync behavior.
- [docs/BLE_PROTOCOL.md](docs/BLE_PROTOCOL.md) — the Bond Touch bracelet and Bond Heart BLE protocol: UUIDs, opcodes, frame layouts, state machine, and DFU.
- [docs/DATA_MODEL.md](docs/DATA_MODEL.md) — backend and data layer: Room schema, REST API, Firebase usage, crypto, and the hosts/telemetry the port avoids.
- [docs/BOND_TOUCH_CLOUD.md](docs/BOND_TOUCH_CLOUD.md) — the removed integration with Bond Touch's servers (Bond API, Heart API, Firebase sign-in and Storage, Signal chat): what it did, and how to restore it.
