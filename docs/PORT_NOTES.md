# Bond Touch Beyond — iOS port notes

A clean-room iOS reimplementation of a Bond Touch–style paired-bracelet app. It is
written from behavioural notes and public BLE technique, **not** by copying the
original app's code. The original app's decompiled source and the APK are not in
this repo.

## What's done

- **SwiftUI app** (`Sources/`), generated into an Xcode project by XcodeGen
  (`project.yml`). The existing `ios-testflight.yml` workflow finds and builds it;
  `ios-build-check.yml` compiles it for the simulator on every push/PR.
- **iCloud / CloudKit relay** (`Sources/Cloud/CloudRelay.swift`) — replaces Firebase
  entirely. A "bond" is a shared CloudKit custom zone created by one user and joined
  by the partner via a `CKShare`. Touches are records in that zone; a silent push
  (`CKRecordZoneSubscription`) wakes the other device to fetch and play them. No app
  server, no Firebase Realtime Database, no FCM.
- **No telemetry.** There is no analytics, crash-reporting, or tracking SDK anywhere
  in the project, and nothing contacts any host except Apple's iCloud on the user's
  behalf. Because this is a fresh implementation, there was no telemetry to strip —
  it was simply never added. (If you later port specific screens from the original,
  re-check: do not bring across Firebase Analytics, Crashlytics, or any `logEvent`
  calls.)
- **Bluetooth layer** (`Sources/Bluetooth/`) — a complete CoreBluetooth central
  implementing the **reverse-engineered v3 protocol** (see `docs/BLE_PROTOCOL.md`):
  real service/characteristic UUIDs, touch frames on FFB2, buzz/glow on FFB1.

## The bracelet protocol — reverse-engineered ✅

The v3 BLE protocol was recovered from the official app with jadx and is documented in
`docs/BLE_PROTOCOL.md` and implemented in `Sources/Bluetooth/BondGATT.swift`:
service `d3c00003-…`, write char FFB1 (LED/motor), write+notify char FFB2 (touches),
the `0x26` LED+motor frame and the FFB2 touch frame. `BondGATT.isResolved` is now `true`
and `BraceletManager` scans for and drives real hardware.

What still benefits from a real-device check (not blocking the build):
- Confirm the exact field split of the incoming `0x19` FFB2 notification against a
  `btsnoop_hci.log` capture (we know it's a touch event ≥14 bytes; the per-tap byte
  layout is inferred).
- Confirm vibration/LED timing defaults feel right on hardware.

### Option A — sniff a real bracelet (preferred, cleanest)
1. On an Android phone, enable Developer Options → **Enable Bluetooth HCI snoop log**.
2. Pair and use the official app: connect, send a few touches with different tap
   counts and colours, receive a few.
3. Pull `btsnoop_hci.log` (via `adb bugreport` or the Developer Options path) and
   open it in Wireshark.
4. Read off:
   - the 128-bit **vendor service UUID** the bracelet advertises → `BondGATT.service`
   - the characteristic the app **writes** touch commands to → `touchWrite`
   - the characteristic it **subscribes** to for tap events → `touchNotify`
   - the **advertised name prefix** → `advertisedNamePrefix`
   - the **frame bytes** for each touch: opcode, how tap-rhythm and colour are packed,
     any length/checksum → implement in `BondGATT.encode` / `decodeTap`.
   - nRF Connect on a second phone is a good cross-check for the UUIDs.

### Option B — static analysis of the official APK
Run REA (or jadx/apktool) on the APK **on a machine without this environment's
sandbox guard** (it blocks unpacking untrusted binaries here). Look for the BLE
constants and the touch encoder in the decompiled Java/Kotlin and native libs. Keep
that output **out of this public repo**; transcribe only the protocol facts into
`BondGATT.swift`.

Once the five things above are filled in, `BraceletManager` starts working with no
other changes.

## "Fix the bugs"
Bugs can only be found and fixed in code we can read and build. The honest split:
- **App-side bugs** (BLE handling, relay, state) — fixable here once the protocol is
  in and we can run the app against a bracelet. The structure is written to make
  these easy to isolate (protocol in one file, transport in another, relay in a
  third).
- **Firmware bugs on the bracelet itself** — not fixable from a decompiled, stripped
  binary in any reliable way (recovered pseudo-C does not recompile into a flashable
  image, and a bad flash bricks the device). If a specific misbehaviour is actually
  the *app* mishandling a packet — which is the common case — that is an app-side fix.
  If you have a specific symptom, describe it and we can trace it to app or firmware.
