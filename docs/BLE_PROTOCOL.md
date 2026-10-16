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

**v1/v2/v4/mini service `d3c00002` characteristics:**
- `d3c00001-add3-1d4b-0000-0000b5006bb1` — control/OTA service
- `d3c00002-add3-1d4b-0001-0000b5006bb1` — main app service
- `d3c0ff06-add3-1d4b-0000-0000b5006bb1` — v1 `FF06` command characteristic (v1 main write char)
- `d3c0ffa1-add3-1d4b-0001-0000b5006bb1` — token write ("12345678")
- `d3c0ffa2-add3-1d4b-0001-0000b5006bb1` — AUID / device-id write; v1 also uses it as a state-notify char
- `d3c0ffa4-add3-1d4b-0001-0000b5006bb1` — state notify (BondState, battery); subscribed via CCCD
- `d3c0ffa5-add3-1d4b-0001-0000b5006bb1` — touch/event notify + command write (main LED/motor/config char); subscribed
- `d3c0ffa6-add3-1d4b-0001-0000b5006bb1` — app-command write (LED/motor/config; v2/v4/mini)
- `d3c0ffa8-add3-1d4b-0001-0000b5006bb1` — v4/mini bonding/ANCS notify char
- `0000180a-…` — standard DIS service; `00002a26-…` — firmware string char; `00002a24-…` — model-number char
- v1 only: `d3c0ff03-…-0000-…` — v1 firmware-version read char; `d3c0ffa7-…-0001-…` — v1 char

**v3 service `d3c00003` characteristics:**
- `d3c0ffb1-add3-1d4b-0000-0000b5006bb1` — FFB1 (write app-commands, notify events); subscribed via CCCD
- `d3c0ffb2-add3-1d4b-0000-0000b5006bb1` — FFB2 (write touch pattern)
- `0000180f-…` — battery service; `00002a19-…` — battery level char
- `00002a24-…` — model-number char

### 1.1 MTU / connection setup

- GATT is opened with `connectGatt(ctx, autoConnect, cb, TRANSPORT_LE=2)`.
- No explicit `requestMtu` is issued for Bond Touch; all command writes are padded to
  **20 bytes** (`Arrays.copyOf(frame, 20)` in every v2/v4/mini command builder; v3
  frames are also 20 bytes, padded with `0xFF`).
- After connect: `onConnectionStateChange` → `discoverServices()`; on
  `onServicesDiscovered` the client reads the API-version characteristic.
- v2/v4/mini request `requestConnectionPriority(0)` (BALANCED) once the "connect burst"
  of descriptor writes settles.
- v3 FFB1/FFB2 writes use `WRITE_TYPE_NO_RESPONSE` (`setWriteType(2)`).

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
  - Used by: single color (ledMode 1, execute = -1), test color, blink, stop LED (ledMode 4), motor-only.
- `0x27` (39) = **Configuration write**. Frame:
  `[0x27, 0x00, propertyId:u8, 0x01, ...payload]` padded to 20. Also used as a DFU
  trigger (see §3) with a magic payload.
  - Colors encode as 4-byte big-endian ARGB `{i>>>24, i>>>16, i>>>8, i}`.
  - u16 config values are big-endian; u32 config values are big-endian.
- `0x32` (50) = **queue-pause / resume marker**: `[0x32, 0x00, z?0x22:0x11]`. Pauses
  the command queue 5 s on write.
- `0x33` (51) = **"send-message" LED/motor-with-meaning step**: 15-byte body
  `[0x33, 0, r, g, b, color1(3B BE), color2(3B BE), color3(3B BE)] + durationU16LE`.
- `0x31` (49) = PAIRED_SIGNAL handler response write: `[0x31, 0x00, 0x11, 0x22, 0x33, 0x44]`.
- `0x34` (52) = ANCS-ish toggle: `[0x34, 0x00, z?0x11:0x22]`.
- `0x25` (37) = **DFU enter**: `[0x25, 0x00, 0x11, 0x22, 0x33, 0x44]`.

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
- WAITING_TOKEN → writes ASCII "12345678" to `d3c0ffa1`. WAITING_AUID → writes
  device-id u32LE to `d3c0ffa2`. CONNECTED → resumes queue, reads firmware (`00002a26`).

**Touch / tap notify — characteristic `d3c0ffa5`**:
- If `value[0]==0x19` (25) and length ≥ 14 → treated as a BLE-params blob forwarded raw.
- Otherwise parsed as the **AppEvent frame**:
  `[eventId:u8@0, counter:u8@1, touchDurationMs:u32LE@2, releaseDurationMs:u32LE@6, stopFlag:u32LE@10]`
  (v4 also reads `deviceId:u8@14`).
- **AppEvent IDs**: `0x11` = AUID_RIGHT (paired/activate menu), `0x12` = AUID_ERROR,
  `0x13` = PAIRED_SIGNAL (writes `0x31` reply), `0x14` = SEND_MSG (a touch segment
  received from partner), `0x15` = SEND_MSG_TIMEOUT, `0x16` = TAP_DETECTED_SIGNAL,
  `0x17` = NO_ACTION_DOUBLE_TAP_DETECTED.
- **Touch-pattern decode**: on SEND_MSG, `counter==1` starts a new pattern
  `[touchDuration]`; subsequent segments append `[releaseDuration, touchDuration]`
  (each clamped to ≥ 50 ms). `stopFlag == 0xFFFFFFFF` ends the pattern and delivers it
  with its menu index. TouchTimeout with counter 0 clears the buffer.

**Sending a touch to the partner:** the on/off millisecond pattern list is converted to
a sequence of `0x33` (send-msg LED/motor) frames with a color gradient between
`color1 → color2`, bracketed by `0x32` pause markers (`0x22` before, `0x11` after), one
command per 200 ms step, written to `d3c0ffa6`. v4 additionally writes `SELECTED_USER`.

**Battery:** delivered through the state char and the firmware DIS read. v2 parses
`[level:u8@0, reserved:u8@1]`.

**Motor strength / vibration:** writes `MOTOR_STRENGTH` (property `0x18`), one byte
strength. Valid strengths: `{28, 33, 40, 58, 60, 73, 80, 88, 100}`; valid levels
`{0, 1, 2, 3, 4}`.

### 1.4 v1 protocol (legacy)

- Main write char `d3c0ff06` on service `d3c00002`.
- **FF06 frame**: `[opcode:u16LE@0, seq:u16LE@2, ...payload]`, 16 bytes.
  - `0x21` (33) ColorCommand: `[op, seq, color:u32LE@4, 100:u8@7]`.
  - `0x26` (38) LgtVibCommand: `[op, seq, ledId:u8@4, type:u8@5, mode:u8@6, 1:u8@7, (optional steps:u16LE@8, duration:u16LE@10)]`.
  - `0x27` (39) ActConfigCommand: `[op, seq, param:u32LE@4, value:u32LE@8]` (params 1003/1006 for colors).
  - `0x25` (37) generic 8-byte config (reset-user / selection).
- Firmware version read from char `d3c0ff03`, bytes `[patch@0, minor@1]`, generation = 1.
- State notify char `d3c0ffa2`: `[bondEventId@0, pairedEventId@1, chargingId@2]`;
  charging 0 = not, 1 = yes; bondEvent 131/132; pairedEvent 244 → write device-id to
  `d3c0ffa1`, 246 = resume, 247 = message recording.
- Battery read char `d3c0ffa1` as `[u16@0]` → `pct = max(0, min(400, raw-3700))*100/400`.
- Color palette is an int[11] ARGB table indexed by a `ColorInfo.ledId`.

### 1.5 v3 protocol

- All app commands written to FFB1 `d3c0ffb1`; touch patterns written to FFB2
  `d3c0ffb2`; both WRITE_NO_RESPONSE.
- **FFB1 write frame**: `[prefix:u8, cmd:u8, ...args]`, written at its exact length (not
  padded). prefix `1` = normal app command, `3` = token: `[3] + "12345678"` (9 bytes), sent
  only after the bracelet reports `WAITING_TOKEN` (130); `7` = AUID: `[7, id]` — a **single
  byte**, sent only after `WAITING_AUID` (131). On `CONNECTED` (133) the original app sends
  `[1,0x19] [1,0x1B] [1,0x41] [1,0x42] [1,0x49,1] [1,0x1C]` once. (Bond Touch Beyond earlier
  sent the token and a 4-byte AUID padded to 20 bytes unprompted on every connect; fixed.)
  - cmd `0x4B` (75) LED color: `[1, 0x4B, 0x00, displayLed:u8, r:u8, g:u8, b:u8]`
    (DisplayLed ALL = 0, LED_0 = 1); clear with `[1, 0x4B, 0x01]`.
  - cmd `0x48` (72) vibration: `[1, 0x48, 0x00, level, balance, 3]`; variant
    `[1, 0x48, 0x02, level, balance, 3]`.
  - cmd `0x45` (69) user-menu/select: enable `[1, 0x45, 0x01]`; set menu
    `[1, 0x45, 0x00] + user1(4B) + user2(4B) + user3(4B)` where each user block =
    `[activeState:u8, r:u8, g:u8, b:u8]`.
  - cmd `0x2A` (42) = DFU enter (`[1, 0x2A]`).
  - cmds `0x19, 0x1B, 0x41, 0x42, 0x49, 0x1C` written on CONNECTED to enable features/notifications.
  - cmds `0x43` / `0x44` = ANCS on/off.
- **FFB2 touch frame**: header `[deviceId, totalLen, chunkCount, color1(3B BE),
  color2(3B BE), stopFlag]` followed by the on/off duration bytes chunked 20 per
  packet, remaining bytes padded `0xFF`.
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
    (3×[state, r, g, b]@2..), `0x48` = vibration `[level@2, balance@3]`, battery-settings
    ack `[lowVal, lowRGB, critVal, critRGB]`, `0x4A` = accel sensitivity.
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
   WAITING_AUID → app writes AUID (device index / user id, u32LE); OOBE/PAIRED signalled
   via AppEvent `0x11` / `0x13`.
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
  v2/v4/mini `0x25` magic `[0x25, 0x00, 0x11, 0x22, 0x33, 0x44]` to `d3c0ffa5`; v3 FFB1
  `[0x01, 0x2A]`; v1 `FF06` DfuCommand. The bracelet reboots into its DFU bootloader
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
