# Bond Touch — BLE / Hardware Protocol

Interface facts (UUIDs, opcodes, byte layouts, state machine, DFU) for the Bond Touch
bracelets and the Bond Heart device, from the Android app `com.impossible.bondtouch`
v11.2.0 (versionCode 490).

Byte-format codes are Android `BluetoothGattCharacteristic` format constants:
`17` = FORMAT_UINT8, `18` = FORMAT_UINT16 (little-endian), `20` = FORMAT_UINT32
(little-endian). `setValue(value, format, offset)` writes at a byte offset.

There are five Bond Touch bracelet protocol variants, selected at runtime (see §1.2):
`v1`, `v2`, `v3`, `v4`, `mini`. The Bond Heart device ("BondHeart") is a completely
separate protocol (§2).

---

## 1. Bond Touch bracelet BLE protocol

### 1.0 Identity: UUID base, service/characteristic UUIDs

Bond Touch uses a vendor 128-bit UUID base `d3c0XXXX-add3-1d4b-0000-0000b5006bb1`
(several characteristics use the variant node `…-0001-0000b5006bb1`).

**Top-level UUIDs:**
- `d3c0ff10-add3-1d4b-0000-0000b5006bb1` — v3 API-version characteristic
- `d3c0ffb3-add3-1d4b-0000-0000b5006bb1` — v1/v2/v4/mini API-version characteristic
- `d3c00003-add3-1d4b-0000-0000b5006bb1` — v3 primary service
- `d3c00001-add3-1d4b-0000-0000b5006bb1` — v1/v2 primary service (control/OTA service)
- `00002902-0000-1000-8000-00805f9b34fb` — CCCD (Client Characteristic Config Descriptor)
- `d3c0ffb1-add3-1d4b-0000-0000b5006bb1` — v3 FFB1 characteristic (write + notify)
- `d3c0ffb2-add3-1d4b-0000-0000b5006bb1` — v3 FFB2 characteristic (write, touch pattern)

**Scan / advertised names:**
- Normal advertised names (used as scan filter): `BOND`, `Bond More`, `BOND 4`,
  `BOND MINI`. A scanned device is accepted only if its advertised name is in this set.
- DFU advertised names: `BOND_DFU`, `BOND_M_DFU`, `BOND_4_DFU`, `BOND_MINI_DFU`.

**v1/v2/v4/mini services:**
- `d3c00001-add3-1d4b-0000-0000b5006bb1` — control service:
  - `d3c0ffb3-…-0000-…` — API-version read
  - `d3c0ff06-…-0000-…` — **battery** read + notify (v2/v4/mini `[level %, reserved]`; v1
    `[millivolts u16LE]`). It is *not* a command characteristic.
  - v1 only: `d3c0ff03-…-0000-…` — firmware `[patch, minor]`
- `d3c00002-add3-1d4b-0001-0000b5006bb1` — main app service:
  - `d3c0ffa1-…-0001-…` — token write ("12345678")
  - `d3c0ffa2-…-0001-…` — AUID / device-id write (u32LE)
  - `d3c0ffa4-…-0001-…` — state read + notify (bond state, charging, busy flags)
  - `d3c0ffa5-…-0001-…` — touch/event notify
  - `d3c0ffa6-…-0001-…` — **app-command write for every non-v3 generation** (v1 sequenced
    frames; v2/v4/mini LED/motor/config/DFU frames)
  - `d3c0ffa7-…-0001-…` — v1 command-result (ack) notify
  - `d3c0ffa8-…-0001-…` — v4/mini encrypted notify char; enabling it makes the phone bond
- `0000180a-…` — standard DIS service; `00002a26-…` — firmware string char; `00002a24-…` — model-number char

**v3 service `d3c00003` characteristics:**
- `d3c0ffb1-add3-1d4b-0000-0000b5006bb1` — FFB1 (write app-commands, notify events); subscribed via CCCD
- `d3c0ffb2-add3-1d4b-0000-0000b5006bb1` — FFB2 (write touch pattern)
- `0000180f-…` — battery service; `00002a19-…` — battery level char
- `00002a24-…` — model-number char

### 1.1 MTU / connection setup

- GATT is opened with `connectGatt(ctx, autoConnect, cb, TRANSPORT_LE=2)`.
- No explicit `requestMtu` is issued for Bond Touch. v2/v4/mini command frames are
  `Arrays.copyOf(frame, 20)` — **zero-padded** to 20 bytes. v3 FFB2 frames are 20 bytes
  padded with `0xFF`; v3 FFB1 commands are written at their exact length. v1 frames are
  16 (or 8) bytes, zero-filled.
- After connect: `onConnectionStateChange` → `discoverServices()`; on
  `onServicesDiscovered` the client reads the API-version characteristic.
- v2/v4/mini request `requestConnectionPriority(0)` (BALANCED) once the "connect burst"
  of descriptor writes settles.
- v3 FFB1/FFB2 writes call `setWriteType(2)`, which is `WRITE_TYPE_DEFAULT` (write
  **with** response; NO_RESPONSE is 1). All other writes use the default type too.

### 1.2 Device-version selection

`onServicesDiscovered`: if discovered services contain `d3c00003` → read char
`d3c0ff10` (v3), else read char `d3c0ffb3`. The returned uint8 API-version maps to a
device:
- `66` (0x42) → BT2 → `BleBondManagerV2`
- `68` (0x44) → BT4 → `BleBondManagerV4`
- `69` (0x45) → BT_MINI → `BleBondManagerMini`
- any other value → BT1 → `BleBondManagerV1`
- presence of `d3c00003` service → BTM (v3) → `BleBondManagerV3`

`BleBondTouchDevice` ordinals: 0 = BT1, 1 = BT2, 2 = BTM/v3, 3 = BT4, 4 = mini; model
strings "1", "2", "3", "4", "mini".

Baseline firmware per variant: v1 `1.2.96`, v2 `2.7.9`, v3 `3.1.1`, v4 `2.0.3`,
mini `1.2.0`.

### 1.3 v2/v4/mini protocol (the main modern protocol)

All multi-byte command frames are written to characteristic `d3c0ffa6` on service
`d3c00002`, unless noted. Frames are `byte[20]`.

**Command opcodes (first byte):**
- `0x26` (38) = **LED + Motor command**. Frame:
  `[0x26, 0x00, queue:u8, vibStrength:u8, vibTimeMs:u16LE, ledMode:u8, red:u8, green:u8, blue:u8, ledBrightness:u8, ledTransitionMs:u16LE, ledHoldMs:u16LE, ledSleepMs:u16LE, ledExecuteMs:u16LE]`.
  - Constructor arg order: `(queueByte, vibStrength, vibTimeMs, ledMode, red, green, blue, ledBrightness, transition, hold, sleep, execute)`.
  - `ledMode`: `1` = solid/breathe, `4` = off/stop, `2` = pattern step (seen in special vibration).
  - `queue` `1` = queued as part of a message (closed by `[0x32,0,0x11]`), `0` = immediate.
  - Used by: single-colour touch playback (queue 1, ledMode 2), hold colour (ledMode 1,
    brightness 80, execute 0xFFFF), LEDs off (ledMode 4), vibration preview (strength,
    2000 ms, ledMode 4), blink.
- `0x27` (39) = **Configuration write**. Frame:
  `[0x27, 0x00, propertyId:u8, 0x01, ...payload]` zero-padded to 20.
  - Colours are the colour-mapped (ColorMapperHelper.b) ARGB int, 4 bytes big-endian
    (so `[0xFF, R, G, B]`). `LowBatteryData` and `DisconnectedParamsData` use big-endian
    u16/u32; `MinTouchDuration`, `MaxTouchDuration`, `MessageTimeout` are **u32
    little-endian**; `UserMenu(colour, index)` = colour BE32 + index BE32 (property 0x24).
- `0x32` (50) = **end-of-message marker**: `[0x32, 0x00, z?0x22:0x11]` — `0x22` after
  `0x33` steps, `0x11` after queued `0x26` frames. Written only *after* the frames; once
  written the app pauses its command queue 5 s (resumed early by state CONNECTED).
- `0x33` (51) = **"send-message" step** (BleAppCommandHelper.a):
  `[0x33, 0x00, strength, bright1, bright2, bright3, RGB1(3B), RGB2(3B), RGB3(3B), ms:u16LE]`
  (17 bytes, zero-padded). Touch playback uses brightness 80,80,80 and the same colour in all
  three slots; gaps are a frame with everything 0 and `ms` = gap length.
- `0x31` (49) = PAIRED_SIGNAL handler response write: `[0x31, 0x00, 0x11, 0x22, 0x33, 0x44]`.
- `0x34` (52) = ANCS-ish toggle: `[0x34, 0x00, z?0x11:0x22]`.
- `0x25` (37) = **DFU enter**: `[0x25, 0x00, 0x11, 0x22, 0x33, 0x44]` (on `d3c0ffa6`).

**ConfigurationProperty IDs** (used as `propertyId` in the `0x27` frame and echoed in
config reads):
`OUID=0x11, TOKEN=0x12, MAX_TOUCH_COUNT=0x13, MIN_TOUCH_DURATION=0x14,
MAX_TOUCH_DURATION=0x15, MESSAGE_TIMEOUT=0x16, LOW_BAT_THRESHOLD=0x17,
MOTOR_STRENGTH=0x18, BLE_PARAMS=0x19, LOW_BAT_COLOR=0x21, OOBE_COLOR=0x22,
OOBE_PAIRED_COLOR=0x23, DOUBLE_TAP_COLOR=0x24, TOUCH_COLOR=0x25,
TOUCH_WARNING_COLOR=0x26, ERROR_COLOR=0x27, CHARGING_COLOR=0x28,
CHARGE_DONE_COLOR=0x29, ACCEL_SENSITIVITY=0x30, DISCONNECTED_PARAM=0x31,
ANCS_PARAM=0x33, FACTORY_MODE=0x35, RESET_CONFIG=0xEF, SELECTED_USER=0x37`.
`SELECTED_USER` write sets which partner/menu slot (1/2/3) is active.

**Config READ layout**, response bytes `[0x27?, _, propertyId@2, _, value@4..]`:
colors = u32 BE at [4..8]; `LowBatteryData` = `b[4], u16BE@5, u16BE@7, u32BE@9,
u32BE@13`; `BleParamsData` = six u16LE at [4,6,8,10,12,14];
`MinTouchDuration/MessageTimeout/MaxTouchDuration` = u32LE; `SelectedUser` = `b[8]`.

**State notify — characteristic `d3c0ffa4`**. Frame bytes:
`[bondStateId:u8, chargingStateId:u8, ledBusy:u8, motorBusy:u8, touchBusy:u8]`.
- `ChargingState`: `0` = NOT_CHARGING, `1` = CHARGING, `2` = FULL_CHARGE, `0xFF` = ERROR.
- `BondState`: `0x00` = NO_STATE, `0x82` = WAITING_TOKEN, `0x83` = WAITING_AUID,
  `0x84` = OOBE, `0x85` = CONNECTED, `0x86` = MSG, `0x87` = FACTORY,
  `0x88` = QUEUE_EXECUTING. (Stored as signed bytes −126…−120.)
- Session start (manager constructor): read `d3c0ff06` (battery), enable notifications on
  `d3c0ff06`, `d3c0ffa5`, `d3c0ffa4`; then v2 writes the token at once, v4/mini read
  `d3c0ffa4`. Each *new* bond state is handled once (repeats ignored, initial NO_STATE):
  WAITING_TOKEN → writes ASCII "12345678" to `d3c0ffa1`. WAITING_AUID → writes
  device-id u32LE to `d3c0ffa2`. OOBE → setup mode (the user double-taps to pair).
  CONNECTED → resumes queue; the first time, reads firmware (`00002a26`) — that answer is
  "device paired" (settings go out, §1.7). MSG → pause queue 15 s. QUEUE_EXECUTING
  (notified) → re-read the state after 5 s.
- After the firmware read: v2 (fw ≥ 2.5.0) toggles ANCS by OS-bond state; v4/mini write
  ANCS off and, if not OS-bonded, enable notifications on `d3c0ffa8` to start bonding.
- On OS bond (`D()`): `LOW_BAT_THRESHOLD [10]`; `LOW_BAT_COLOR [1, 1000 BE16, 500 BE16,
  1171 BE32, 0x00FF0000 BE32]`; `MIN_TOUCH_DURATION 50 (u32LE)`; `DISCONNECTED_PARAM`
  all zero; v2 also `ANCS_PARAM [0]`.

**Touch / tap notify — characteristic `d3c0ffa5`**:
- If `value[0]==0x19` (25) and length ≥ 14 → treated as a BLE-params blob forwarded raw.
- Otherwise parsed as the **AppEvent frame**:
  `[eventId:u8@0, counter:u8@1, touchDurationMs:u32LE@2, releaseDurationMs:u32LE@6, stopFlag:u32LE@10]`
  (v4 also reads `deviceId:u8@14`).
- **AppEvent IDs**: `0x11` = AUID_RIGHT (ignored), `0x12` = AUID_ERROR (→ OOBE),
  `0x13` = PAIRED_SIGNAL (writes `[0x31,0,0x11,0x22,0x33,0x44]` to `d3c0ffa6`),
  `0x14` = SEND_MSG (a touch segment the user recorded on this bracelet),
  `0x15` = SEND_MSG_TIMEOUT, `0x16` = TAP_DETECTED_SIGNAL (only logged),
  `0x17` = NO_ACTION_DOUBLE_TAP_DETECTED (the double-tap *action*, not a touch).
- **Touch-pattern decode**: on SEND_MSG, `counter==1` starts a new pattern
  `[touchDuration]`; subsequent segments append `[releaseDuration, touchDuration]`
  (each clamped to ≥ 50 ms). `stopFlag == 0xFFFFFFFF` ends the pattern and delivers it
  (v2: menu FIRST; v4: the slot in byte 14 — if that's not the selected slot the app
  records the new selection). SEND_MSG_TIMEOUT with counter 0 clears the buffer, then
  delivers whatever is left. The mini reports the fixed pattern `[500,250,500,250,500]`
  for every SEND_MSG / timeout event.

**Playing a touch** (BleBondManagerV2Base.g, colours through ColorMapperHelper.b,
strength = the user's vibration level, 80 if unset, all on `d3c0ffa6`):
- one colour (start == end): per on/off pair one queued `0x26` frame `[queue 1, strength,
  vib = on, ledMode 2, RGB, brightness 80, transition = ⌊on·0.25⌋, hold = on − 2·transition,
  sleep = off, execute = on + off]` (a missing last off = 0), then `[0x32, 0, 0x11]`;
- gradient: for each on segment `n = max(1, ⌊on/200⌋)` and **n + 1** `0x33` frames of
  200 ms (Kotlin `0..n`), colour = start→end blend at elapsed/total; each gap one all-zero
  `0x33` frame with `ms` = gap; then `[0x32, 0, 0x22]`. No opening marker.
- mini always plays `[500,250,500,250,500]`; an empty pattern falls back to it. v4 then
  writes `SELECTED_USER` = the touch's partner slot (if its menu is enabled).

**Battery:** `d3c0ff06` in service `d3c00001` (read + notify), `[level:u8@0, reserved:u8@1]`.
**Charging:** state byte 1 (`CHARGING` and `FULL_CHARGE` both reported as charging).

**Motor strength / vibration:** writes `MOTOR_STRENGTH` (property `0x18`), one byte
strength. Valid strengths: `{28, 33, 40, 58, 60, 73, 80, 88, 100}`; the balance `{0…4}`
(2 = centre) is used only by v3. Preview: `0x26` with strength, 2000 ms, ledMode 4.

**User colour** (`f()`): `TOUCH_COLOR`, then v2 `DOUBLE_TAP_COLOR`, v4/mini
`UserMenu(colour, 0x80)`. **v4 partner menu** (`A()`): `UserMenu(colour, slot|0x80)` for
an active slot, `UserMenu(0xFF000000, slot&0x7F)` otherwise, slot 1 shown only when slot 2
or 3 is active; then `SELECTED_USER` = min(last active slot, selected). SELECTED_USER is
skipped while neither slot 2 nor 3 is active.

### 1.4 v1 protocol (legacy)

- Commands are written to **`d3c0ffa6`** on service `d3c00002` (the class is named
  `WriteFF06Command`, but `d3c0ff06` is the battery characteristic).
- **Frame**: `[opcode:u16LE@0, seq:u16LE@2, ...payload]`, 16 bytes (8 for the short
  commands), zero-filled; `seq` increments per command and wraps after 65535.
  - `0x21` (33) ColorCommand: `[op, seq, color:u32LE@4]` then byte 7 overwritten with 100.
  - `0x26` (38) LgtVibCommand: `[op, seq, ledId:u8@4, mode:u8@5, kind:u8@6, 1:u8@7, (100:u16LE@8, steps:u16LE@10)]`.
    A touch = one frame per on/off entry, modes alternating 2, 1, 2, …, kind 1, steps =
    `max(100, ms)·10 / ledSteps` (ledSteps 100, 30 for red); then a closing frame mode 2,
    kind 2 without the timing words.
  - `0x27` (39) ActConfigCommand (16 B): `[op, seq, param:u32LE@4, value:u32LE@8]`; user
    colour = param 1003 (palette ARGB), 1006 (LED id), then SaveConfig (8 B, `1000:u32LE@4`).
  - `0x25` (37) DFU (8 B, `-1@4`); `0x29` (41) reboot (sent after 10 ACR_BUSY acks).
- Session: read `d3c0ff03` (firmware `[patch@0, minor@1]` → `1.minor.patch`), enable
  notify + read `d3c0ff06`; after the firmware read (if no update is needed) enable
  notifications on `d3c0ffa5`, `d3c0ffa4`, `d3c0ffa7` and write "12345678" to `d3c0ffa1`.
- State notify `d3c0ffa4`: `[bondEventId@0, pairedEventId@1, chargingId@2]`; charging
  0 = not, 1 = yes; pairedEvent 244 → write the AUID u32LE to `d3c0ffa2`, 246 = connected
  ("device paired", queue resumed), 247 = busy (queue paused 30 s; the listener's
  double-tap callback is raised).
- Event notify `d3c0ffa5`: `[id@0, counter@1, count:u16LE@2, touchMs:u16LE@4]`; 18 = AUID
  error, 19 = paired signal → write the single byte `0x31` to `d3c0ffa6`, 20 = touch
  segment (count 1 starts, 0xFFFE timeout / 0xFFFF end; gaps from arrival times; all
  rounded to 50 ms).
- Ack notify `d3c0ffa7`: `[result:u16LE@0, count:u16LE@2]` (1 = ACR_SUCCESS, 11 = BUSY…).
- Battery `d3c0ff06` (service `d3c00001`) as `[mV u16LE]` → `pct = max(0, min(400, mV-3700))*100/400`.
- Colours: ColorMapperHelper.a snaps to the base palette; `ColorInfo.ledId` 0…10 indexes
  the ARGB table `BleColorTable`.

### 1.5 v3 protocol

- All app commands written to FFB1 `d3c0ffb1`; touch patterns written to FFB2
  `d3c0ffb2`; both with the default write type (with response).
- **FFB1 write frame**: `[prefix:u8, cmd:u8, ...args]`, written at its exact length (not
  padded). prefix `1` = normal app command, `3` = token: `[3] + "12345678"` (9 bytes), sent
  only after the bracelet reports `WAITING_TOKEN` (130); `7` = AUID: `[7, id]` — a **single
  byte**, sent only after `WAITING_AUID` (131). On `CONNECTED` (133) the original app sends
  `[1,0x19] [1,0x1B] [1,0x41] [1,0x42] [1,0x49,1] [1,0x1C]` once. (Bond Touch Beyond earlier
  sent the token and a 4-byte AUID padded to 20 bytes unprompted on every connect; fixed.)
  - cmd `0x4B` (75) LED color: `[1, 0x4B, 0x00, displayLed:u8, r:u8, g:u8, b:u8]`
    (DisplayLed ALL = 0, LED_0 = 1); clear with `[1, 0x4B, 0x01]`.
  - cmd `0x48` (72) vibration: preview `[1, 0x48, 0x00, level, balance, 3]`; save
    `[1, 0x48, 0x02, level, balance, 3]` (levels 28…100 as v2, balance 0…4, 2 = centre).
    The ack `[0x0A, 0x48, level, balance]` is answered with a save if it differs from the
    user's setting.
  - The original sends no user-colour command (`f()` is a no-op on v3).
  - cmd `0x45` (69) user-menu/select: enable `[1, 0x45, 0x01]`; set menu
    `[1, 0x45, 0x00] + user1(4B) + user2(4B) + user3(4B)` where each user block =
    `[activeState:u8, r:u8, g:u8, b:u8]`.
  - cmd `0x2A` (42) = DFU enter (`[1, 0x2A]`).
  - cmds `0x19, 0x1B, 0x41, 0x42, 0x49, 0x1C` written on CONNECTED to enable features/notifications.
  - cmds `0x43` / `0x44` = ANCS on/off.
- **FFB2 touch frame** (BleBondManagerV3.g): header `[slot (MenuIndex 1…3), sampleCount,
  ceil(count/20), color1 R,G,B, color2 R,G,B, replyFlag]` (colours not colour-mapped;
  replyFlag is 0 when playing a received touch), then the 50 ms position samples 20 per
  packet; every packet padded with `0xFF` to 20 bytes.
- **FFB1 notify decode**: first byte = category:
  - `0x02` onBondEvent: `[0x02, eventId:u8@1, ...]` — eventId `0x13` = PAIRED_SIGNAL,
    `0xB2` (178) = NO_ACTION_DOUBLE_TAP, `0xB3` (179), `0xB4` (180) = USER_SELECTED
    `[index@2]`.
  - `0x04` onSystemEvents/SYS_STATE: `[0x04, bondStateId:u8@1]` — `0x01` = START,
    `130` = WAITING_TOKEN, `131` = WAITING_AUID, `132` = OOBE, `133` = CONNECTED,
    `134` = MSG_RECORDING, `135` = MSG_PLAYING, `136` = MENU, `137` = REPLY_MENU,
    `138` = WAIT_FOR_ACT_PAIRED, `141` = WAIT_DOUBLE_TAP, `142` = TEST_COLORS,
    `143` = WAITING_START_AUTH.
  - `0x0A` (10) onAckReceived: `[0x0A, ackCmd:u8@1, ...]` — `0x45` = user-color menu
    (3×[state, r, g, b]@2..), `0x48` = vibration `[level@2, balance@3]`, `0x49` = battery
    settings `[low%@2, R, G, B, critical%@6, R, G, B]`, `0x4A` = accel sensitivity.
  - `0xAA` (−86) = lot number `bytes[1..5]`; `0xAB` (−85) = device id `bytes[1..5]`;
    `0xAE` (−82) = health stats; `0xAF` (−81) = flash stats `[u16@1, u16@3, u16@5]`;
    `0xB0` (−80) = ANCS; `0xAC` (−84) = firmware `[minor@1, major@2, generation@3]`.
- Battery read from `00002a19` as `[u8@0]`.

### 1.6 Checksums / CRC

No application-level checksum or CRC is computed on command frames in any variant.
Integrity relies on GATT/L2CAP. DFU images use the Nordic DFU library's own init-packet
CRC (§3). The token/AUID pairing handshake is the only app-layer authentication; the
fixed token string "12345678" is written in these builds.

### 1.7 Pairing / bonding steps

The client registers a receiver for `ACTION_PAIRING_REQUEST`,
`ACTION_BOND_STATE_CHANGED`, and `adapter.ACTION_STATE_CHANGED`.

1. Scan (by advertised name) or connect to a bonded/associated device; discover
   services; read API version.
2. Instantiate the version manager; enable notifications on the state + event
   characteristics (write CCCD `00002902` = ENABLE_NOTIFICATION_VALUE).
3. Bracelet reports BondState WAITING_TOKEN → app writes token "12345678";
   WAITING_AUID → app writes AUID (device index / user id, u32LE); the PAIRED signal
   (AppEvent `0x13`) is answered. "Device paired" = firmware read (v2/v4/mini 2A26, v3
   0xAC answer) or v1 paired state 246. Then (BleBondClient listener `j()`), once per
   connection: user colour `f()`, vibration `B(level, balance)` (if set), partner menu
   `A()` (v3: `[1,0x45,1]` read + diff write; v4: menu entries), saved slot `s()` (v4
   SELECTED_USER).
4. v2/v4/mini/v3 optionally call `createBond()` / enable ANCS (property `0x33`) when the
   OS bond is absent. A successful Android `createBond` →
   `ACTION_BOND_STATE_CHANGED` = BONDED(12) → the manager writes default config.
5. On Android 12+ the device is registered with `CompanionDeviceManager` (association +
   `startObservingDevicePresence`); unpairing disassociates and stops observing.

### 1.8 Connection state machine

- States (`ConnectionState`): `DISCONNECTED`, `OOBE`, `CONNECTED`. Exposed as a
  `BondBleState` StateFlow.
- Force-connect is guarded by permissions, a paired flag, and
  `ReconnectPolicy = paired && !rePairRequired`. It prefers a bonded `BluetoothDevice`,
  else starts a filtered scan, else `connectGatt(autoConnect=true)`.
- `connect(device, autoConnect)`: closes any existing gatt, then `connectGatt`.
  autoConnect = true posts a reconnect-retry runnable after 1,200,000 ms;
  autoConnect = false calls `BluetoothGatt.refresh()` (reflection).
- `onConnectionStateChange`: status 0 & state CONNECTED → `discoverServices`. On
  disconnect: if ReconnectPolicy true → reconnect; else if status 133 (GATT_ERROR) and
  retries < MAX(5) → close & retry after 200 ms; status 5/15 logged as stale-bond /
  auth failure.
- Reconnect triggers: Bluetooth adapter STATE_ON, location-providers-changed, app
  foreground.
- Bond-loss: `BondLossDetector` + `WedgeDetector` (BLE command-queue stall) decide
  "re-pair required" → raises a bond-lost exception, resets the manager.
  `QueueHealthEvaluator` / `BleCommandHandler` run the serialized write queue with
  pause/resume/barrier messages.
- The Android "retrieveConnectedPeripherals" equivalent is a scan of
  `BluetoothManager.adapter.getBondedDevices()` for a bonded device whose name matches
  and address equals the saved address (`SAVED_BLE_DEVICE_ADDRESS` in prefs).

### 1.9 Scan filters

`startScan(address, duration, names, scanMode)` builds `ScanFilter`s: one by
`setDeviceAddress(address)` and one per advertised name via `setDeviceName(name)`;
`ScanSettings.setScanMode(scanMode)` (0 = LOW_POWER). On result it connects to the first
device. A single client manages exactly one paired bracelet (address persisted in
prefs); the Bond Heart device is a separate stack.

---

## 2. Bond Heart device (heartble) BLE protocol

A separate GATT device, advertised/scanned as **`BondHeart`**, DFU name
**`BOND_H_DFU`**. Built on the Nordic `no.nordicsemi.android.ble` `BleManager`.

**UUIDs:**
- Service `014F0A00-02CD-4DD4-842D-39FDFABC66F9`
- `014FFA01-02CD-4DD4-842D-39FDFABC66F9` — notify: state / events / acks; write: savePattern
- `014FFA02-02CD-4DD4-842D-39FDFABC66F9` — write: commands (token / AUID / paired / setting)
- `014FFA03-02CD-4DD4-842D-39FDFABC66F9` — read: heartbeat count (encrypted/bonded)
- Battery service `0000180F`; battery level char `00002A19` (notify + read)

Initialization requires the service and the three custom chars plus battery. It
subscribes to `014FFA01` (parsed as `HeartRateCharacteristicResponse`) and to the
battery char.

**Notify frame on `014FFA01`** — `byte[0]` = message type:
- `0x01` = State: `byte[1]` = `HeartPeripheralState` — `130` = WAITING_TOKEN,
  `131` = WAITING_AUID, `132` = OOBE, `133` = CONNECTED.
- `0x02` = Event: `byte[1]` = `HeartEvent` — `19` = PAIRED_SIG, `20` = TIMEOUT,
  `21` = WRONG_TOKEN, `22` = UNSUPPORTED_MSG_ID, `23` = NO_AUTH,
  `24` = FACTORY_BUTTON_PRESSED, `25` = FACTORY_BUTTON_RELEASED,
  `26` = FACTORY_SHAKE_DETECTED. PAIRED_SIG triggers the app to send the paired signal.
- `0x0A` (10) = Acknowledge: `byte[1]` = `AcknowledgeId` — `1` = RESET, `2` = ERASE,
  `3` = VIBRATION `[byte2]`, `4` = LED_BRIGHTNESS `[byte2, byte3]`,
  `5` = LED_COLOR `[byte2, byte3, byte4]`,
  `28` = FW `[byte2..byte5]` = FirmwareVersion(major, minor, patch, build).

**Write commands** (all to `014FFA02` except savePattern):
- `sendToken`: `[0x09, '7','6','5','4','3','2','1','0']` (9 bytes).
- `sendAuid`: `[0x0A, auid:u32@offset1(format20)]`, 9 bytes; AUID is a persisted random
  int (`HEART_SAVED_AUID`).
- `sendPairedSignal`: `[0x07, 0x31]`.
- `setSetting`: `[0x10, 0x33]`.
- `savePattern` — **the heartbeat pattern pushed to the partner** — written to
  `014FFA01`: `[0x01, b1, b2, …]` up to 19 payload bytes, each payload byte =
  `((intervalMs - 260) * 255) / 1280` (u8), i.e. heartbeat inter-beat intervals
  normalised to 0–255.
- `unbond` removes the OS bond.

**Reading heart rate / heartbeat count:** reads char `014FFA03`
(`HeartbeatCountCharacteristicResponse`), yielding `beatsCount` and `playedCount` (two
ints). This is a stored beat count, read on a 1 s poll, not a continuous HR stream;
there is no standard Heart-Rate-Service (0x180D / 0x2A37) usage.

`HeartState`: `Disconnected`, `Dfu`, `NeedsBattery`, `Connected(batteryLevel,
factoryTestMode)`. Firmware thresholds: current/DFU-needed `1.0.3.10`, min supported
`1.0.2.0`.

---

## 3. DFU / firmware update

Both device types use **Nordic Secure DFU** (`no.nordicsemi.android.dfu`), feeding a
firmware ZIP bundled as an app raw resource.

- **Trigger (Bond Touch):** write the DFU-enter command on the running protocol —
  v2/v4/mini `0x25` magic `[0x25, 0x00, 0x11, 0x22, 0x33, 0x44]` (zero-padded to 20) to
  `d3c0ffa6`; v3 FFB1 `[0x01, 0x2A]`; v1 DfuCommand (`0x25`, 8 bytes) to `d3c0ffa6`. The bracelet reboots into its DFU bootloader
  advertising one of the `*_DFU` names.
- **DFU target address derivation:** take the connected MAC, increment the 48-bit
  address by 1, and separately XOR bytes[4] and bytes[5] with `0xAA` — both candidate
  DFU MAC addresses are scanned for. Advertised name is matched case-insensitively.
- **DFU name → device set:** `BOND_DFU` → {BT1, BT2}, `BOND_M_DFU` → {BTM/v3},
  `BOND_4_DFU` → {BT4, mini}, `BOND_MINI_DFU` → {mini}.
- **Heart DFU:** drives the Nordic DFU service with a raw-zip resource image.
  `DfuState`: Idle → Starting → InitializingDFU → (progress) → Completed / Aborted /
  Error. Scans for `BOND_H_DFU`.
- **Image format / packet sequence:** the ZIP contains the Nordic init packet (.dat,
  with image CRC/signature) plus firmware image (.bin). The packet sequence (Start DFU,
  init-packet transfer with CRC, image transfer with packet-receipt notifications,
  validate, activate + reset) is the standard Nordic Secure DFU protocol handled
  entirely by the Nordic library; no custom DFU opcodes are implemented in app code.

---

## 4. Connection lifecycle summary (both stacks)

- **Scanning:** filtered `BluetoothLeScanner.startScan` by name and/or address; the
  Heart device uses a Nordic scanner.
- **Auto-reconnect:** `connectGatt(autoConnect=true)` plus a long-delay retry runnable;
  reconnect on BT-on, location-change, app-foreground, and status-133 GATT errors
  (bounded to 5 retries / 200 ms); the Heart manager reconnects to the saved Heart
  device address.
- **"retrieveConnectedPeripherals" equivalent:** enumerate `getBondedDevices()` filtered
  by Bond name + saved address; also `CompanionDeviceManager.getAssociations()` /
  `startObservingDevicePresence` on API 30+.
- **Multi-device:** one Bond Touch bracelet + one Bond Heart device, each a separate
  singleton client keyed by a persisted MAC; no simultaneous multi-bracelet of the same
  type.
- **Permissions gating:** scanning requires BLUETOOTH_SCAN + CONNECT (API 31+) or
  location enabled + ACCESS_FINE/COARSE_LOCATION (pre-31) + adapter enabled.

Colors are Android ARGB ints (e.g. `-16777216` = black `0xFF000000`). A color-mapper
remaps app colors to the small set the firmware supports before sending.
