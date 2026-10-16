# Bond Touch BLE protocol

Reverse-engineered from the official Android app (`com.impossible.bondtouch` v11.2.0,
versionCode 490) for an interoperable open-source client. These are **interface facts**
(UUIDs, opcodes, byte layouts) — not copied source. The bracelet is a Nordic nRF device
(firmware updates use Nordic DFU). The app ships four protocol generations (`v1`–`v4`);
current hardware (BOND, Bond More, BOND 4, BOND MINI) uses **v3**, documented here.

## GATT

| Role | UUID |
|------|------|
| Primary service | `d3c00003-add3-1d4b-0000-0000b5006bb1` |
| **FFB1** — write: LED / motor / config / menu commands | `d3c0ffb1-add3-1d4b-0000-0000b5006bb1` |
| **FFB2** — write: touch rhythm; notify: incoming touches/events | `d3c0ffb2-add3-1d4b-0000-0000b5006bb1` |
| CCCD (enable notifications) | `00002902-0000-1000-8000-00805f9b34fb` |
| Battery service / Battery level | `0000180f-…` / `00002a19-…` |

Advertised names (normal mode): `BOND`, `Bond More`, `BOND 4`, `BOND MINI`.
DFU mode: `BOND_DFU`, `BOND_M_DFU`, `BOND_4_DFU`, `BOND_MINI_DFU`.

All command writes use **Write With Response** (`setWriteType(WRITE_TYPE_DEFAULT)`).

## Endianness helpers (from `BleAppCommandHelperKt`)

- `u16le(x)` → `[x & 0xFF, (x >> 8) & 0xFF]` (little-endian 16-bit) — used for all durations/params.
- `u32be(x)` → `[x>>24, x>>16, x>>8, x]`, `u32le(x)` → reverse.
- Colors are packed big-endian as three separate bytes `R, G, B` (0xRRGGBB).

## FFB1 commands (LED / motor / menu)

Frames are built, then written to FFB1.

### LED + motor (opcode `0x26` = 38) — `LedAndMotorCommand`, 20 bytes
```
[0]=0x26 [1]=queue [2]=vibrationStrength
[3..4]=vibrationTimeMs  (u16le)
[5]=ledMode [6]=red [7]=green [8]=blue [9]=ledBrightness
[10..11]=ledTransitionTimeMs (u16le)
[12..13]=ledHoldTimeMs      (u16le)
[14..15]=ledSleepTimeMs     (u16le)
[16..17]=ledExecuteTimeMs   (u16le)
```
(Original arg order: queue, vibStrength, vibTimeMs, ledMode, R,G,B, ledBrightness,
transMs, holdMs, sleepMs, execMs.)

### Three-color pattern (opcode `0x33` = 51)
```
[0]=0x33 [1]=0 [2..5]=four mode/param bytes
[6..8]=RGB color1  [9..11]=RGB color2  [12..14]=RGB color3
[15..16]=durationMs (u16le)         ; padded to 20
```

### Display LED / menu (opcode `0x4B` = 75) — via `WriteFFB1Command`
FFB1 frames are prefixed with a leading type byte `0x01`, then:
`[0x4B, 0x00, displayLedIndex, R, G, B]`.

### Simple toggle (opcode `0x32` = 50)
`[0x32, 0x00, on ? 0x22 : 0x11]` padded to 20.

## FFB2 — sending a touch (`WriteFFB2Command`)

A touch rhythm is an array of byte-sized values written into a **20-byte** frame, then
**padded with `0xFF`** up to 20:
```
[t0, t1, …, tN, 0xFF, 0xFF, … up to 20]
```
Each value is the tap position/timing (the app sends `Long[]`, truncated to bytes).

## FFB2 notifications — incoming from the bracelet

On `onCharacteristicChanged` for FFB2:
- If `value[0] == 0x19` (25) and `value.length >= 14` → a **touch/message event** from the
  partner's bracelet (the app forwards this up as "touch received"). Remaining bytes carry
  the rhythm/positions; exact field split should be confirmed against a capture.
- Otherwise it's a connection/config/heartbeat frame handled by the manager.

## Configuration (read/write on config characteristic)

`ConfigurationProperty` ordinals (byte at `value[2]` in a config read; payload from `value[4]`):

| # | Property | Payload |
|---|----------|---------|
|0|OUID|u32be @4..8|
|1|Token|8 bytes LE @4..12|
|2|MaxTouchCount|byte @4|
|3|MinTouchDuration|u32le @4..8|
|4|MaxTouchDuration|u32le @4..8|
|5|MessageTimeout|u32le @4..8|
|6|LowBatteryThreshold|byte|
|7|MotorStrength|byte|
|8|BleParamsData|6×u16le|
|9|LowBatteryData|byte + 2×u16be + 2×u32be|
|10–17|OobeColor, OobePairedColor, DoubleTapColor, TouchColor, TouchWarningColor, ErrorColor, ChargingColor, ChargeDoneColor|u32be color each|
|18|AccelSensitivity|byte|
|19|DisconnectedParamsData|byte + 3×u16be + u32be|

## Built-in color palette (`BleColorTable`, ARGB ints)

`0xFFFF0000` red, `0xFF00A2F9` blue, `0xFF003DF9` indigo, `0xFFBA2E39` …, `0xFFF8FA2D` …,
`0xFF01B500` green, `0xFF01CB80` teal, `0xFFF9F600` yellow, `0xFFF94500` orange,
`0xFFFFFFFF` white, `0xFF000000` off. (Full list in `BleColorTable.a`.)

## Firmware updates

Nordic DFU (`no.nordicsemi.android.dfu`), standard open protocol: bracelet reboots into
`*_DFU` advertising name and accepts a signed firmware zip. The images themselves are not
in the APK; they are fetched at runtime. Native libs in the APK (`libsignal`, `libsqlcipher`,
AndroidX/CameraX) are stock open-source dependencies, not custom firmware.
