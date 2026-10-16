# Bond-touch-beyond

TestFlight: commit with `*u` in the subject to upload, `*b` to archive only. See `.github/workflows/ios-testflight.yml`.

Android XAPK: Actions → Download Bond Touch XAPK → Run workflow fetches `com.impossible.bondtouch` from APKPure (default versionCode 490, armeabi-v7a, SDK 29; clear the version code for the latest) as an artifact, optionally a release. See `.github/workflows/download-xapk.yml`.

## iOS app (Bond Touch Beyond)

A clean-room SwiftUI port: paired bracelets, touches relayed through **iCloud/CloudKit** (no Firebase, no server), and **no telemetry**. CoreBluetooth drives the bracelet using the reverse-engineered v3 protocol (`docs/BLE_PROTOCOL.md`). See `docs/PORT_NOTES.md` for status and how to capture the protocol. `ios-build-check.yml` compiles it for the simulator on every push.
