# Bond Touch More (BTM, generation 3) touch message format

Scope: how the third-generation bracelet ("Bond More", service `d3c00003-add3-1d4b-0000-0000b5006bb1`) records, transmits and plays back a touch, including slides along the bar. Everything here comes from static analysis only:

- the Android app (jadx output under `re/out/sources`, re-decompiled with `--show-bad-code` into `re/out3`)
- the BTM application firmware `dfu_v3.1.1.zip` (`nrf51822_xxac.bin`, byte-identical to `res/raw/dfu_v311_hw3g.zip`), disassembled with capstone (Thumb, Cortex-M0)
- strings from the iOS app

Firmware addresses below are absolute: load address 0x1B000 + file offset. Items marked **UNCERTAIN** are inferences that the code does not fully pin down.

## TL;DR

- A gen-3 touch is **not** a list of on/off durations. It is a **time series of position samples, one byte every 50 ms**. Time is the list index; the position along the bar is in the byte.
- Each sample byte holds two 4-bit position fields, one per finger:
  - `0xFF`: no finger on the bar
  - `0xF0 | p`: one finger at position `p` (0..8). The high nibble is `0xF`, which means "no second finger".
  - `(p2 << 4) | p1`: two fingers, at positions `p1` (low nibble) and `p2` (high nibble)
  - Any nibble greater than 8 means "no finger" for that slot.
- The bar has **9 positions (0..8)**. They map 1:1 to the 9 LEDs, and they drive a 2-motor haptic "pan".
- **Slides have no gesture code.** A slide is just consecutive samples whose position changes, for example `F1 F2 F3 F4 F5 F6 F7`. The app's "swipe" graphics are a heuristic applied when it draws the message. Playback reproduces the motion by moving the lit LED and panning the vibration, one sample per 50 ms.
- The server pattern for `generation: "3"` is exactly this byte list, stored as `List<Long>` with values 0..255. Its duration is `pattern.size * 50` ms. The maximum is 200 samples, which is 10 s.

## 1. Bracelet to phone: a recorded touch

### 1.1 How the firmware samples the touch sensor

The touch IC is an I2C device at **7-bit address 0x15**, driven by `common/touch/touch_low_level.c` (string at 0x33C30, assert reference at 0x28968).

- Init (0x287BC) can talk to a bootloader at address **0x6A** (writes `A0 01 AB`, then checks for reply `0x55`).
- Sleep (0x28C48) writes register **0xE5 = 0x03**.
- Address 0x15, bootloader 0x6A and sleep register 0xE5=3 together match a Hynitron CST816-family capacitive controller. **UNCERTAIN** (no part-number string).

The IRQ handler (0x28970) reads these registers one byte at a time with `twi_read(0x15, reg)`:

| reg | stored at | use |
|---|---|---|
| 0x01 | – | if `== 3`, a "type 0" event is reported (see below) |
| 0x02 | 0x20003030 | number of fingers (1 or 2) |
| 0x04 | 0x20003032 | finger 1 X low byte (unused for position) |
| 0x06 | 0x20003036 | **finger 1 Y low byte = raw position** |
| 0x0A | 0x20003034 | finger 2 X low byte (unused) |
| 0x0C | (r5) | **finger 2 Y low byte = raw position** |

The handler also timestamps the event in ms from RTC1 (`COUNTER * 1000 / 32768`, at 0x2899A..0x289B8) and restarts a 100 ms idle timer (0xCCD ticks).

The callback 0x1F784 turns driver events into scheduler/FSM events:

- one finger: stores raw Y1 at 0x200024EB, then FSM event 4
- two fingers: stores Y1 at 0x200024E9 and Y2 at 0x200024EA, then FSM event 5
- reg1 == 3: FSM event 6
- 100 ms idle: FSM event 7

**Converting raw Y to a position** (recording handler at 0x26E6E..0x26E9A and 0x26EE0..0x26EF4, same helper at 0x1FA5C):

```
p = (240 - Y) / 26        // signed divide (__aeabi_idiv at 0x31344)
if (p == 9) p = 8          // 0x282F4 / 0x282FC / 0x28304
```

So raw Y from 0 to 240 maps to p from 8 down to 0. The result is 9 discrete positions.

### 1.2 The recording state machine (MSG_RECORDING)

The bond FSM is `common/fsm/bond3_fsm.c`. Its dispatcher is at 0x269B8, the state variable is at 0x200020F6, and the per-state jump table is at 0x333A4. Internal state 7 is MSG_RECORDING: its entry handler 0x2773E sends SYS_STATE `0x86` (= 134) through 0x25BC4.

How recording starts:

- From the partner menu (0x27E2E..0x27E50): the bracelet notifies `[0x02, 0xB4 (USER_SELECTED), index]` and enters state 7.
- As a reply from REPLY_MENU (0x27718..0x27736).

In both cases the selected partner index (1..3) is stored at 0x20003016.

On entry, the bracelet enables touch reports and starts a **repeating 50 ms app_timer**:

- timer id 0x20002DFC (created at 0x2850C with mode 1 and handler 0x26991)
- started with 0x666 ticks = 1638 / 32768 s = 50 ms (0x27782..0x27786)
- each expiry posts scheduler event 0x0A, which becomes FSM event 3 (0x24470)

Handlers in state 7 (jump table 0x335F4):

- **Event 4, one-finger report** (0x26ECA):
  - disables further touch reports
  - `buf[count++] = 0xF0 | p` (0x26F08..0x26F1A); the buffer is at 0x20002F4C and `count` at 0x20002E7F
  - live feedback: LED `display(1, [p], partnerIdx)` (0x2237C) and haptic `motor(p)` (0x22DB8)
- **Event 5, two-finger report** (0x26E56):
  - `buf[count++] = (p2 << 4) | p1` (0x26EB4..0x26EC6)
  - display mode 2 lights LEDs p1..p2; motor runs at `(p1 + p2) / 2`
- **Event 3, 50 ms tick** (0x26F1E):
  - if `count > 199`, the message is finished (0x2830C, below)
  - otherwise, if no report was stored during this 50 ms window (last position is still `0xFF`), append `0xFF` (0x284AC) and turn the LEDs and motor off
  - then re-enable touch reports
  - The effect is exactly **one byte per 50 ms window**: the first report in the window wins, and an empty window becomes `0xFF`.
- **Event 6, reg1 == 3** (0x26E0E): stops the timer, clears `count`, plays an animation and returns to state 4. The touch is discarded. **UNCERTAIN** what physical gesture the IC reports as 3 (possibly a cancel or cover gesture).

**End of recording.** When 200 samples (10 s) have been recorded, 0x2830C stops the 50 ms timer, turns the LEDs and motor off and enters state 8, which sends the message. No silence-based early stop appears in the state-7 handlers, so a recording is always 200 samples and the receiver strips the `0xFF` padding. **UNCERTAIN** (an end trigger outside these handlers cannot be ruled out).

### 1.3 Transfer to the phone (FFB2 notifications)

State 8 sends the message as notifications on **FFB2** (`d3c0ffb2-…`) through 0x26610 (`ble_bond3` notify).

**Header** (sent on entry, at 0x270DA..0x27102). 20 bytes:

| byte | value |
|---|---|
| 0 | partner/menu index (0x20003016, 1..3) |
| 1 | `0xC8` (200 = total sample count) |
| 2 | `0x0A` (10 = number of data packets) |
| 3..19 | `0x00` (the stack buffer is zeroed at 0x269F6) |

**Data packets** (0x2704A..0x2706E): 10 packets of 20 bytes each, `buf[i*20 .. i*20+19]` for i = 0..9, one per FSM event 22 (probably one per notification-sent callback; **UNCERTAIN**). The finish handler is 0x28086.

**App-side reassembly** (`BleBondManagerV3.t()`, the FFB2 branch, re-decompiled into `re/out3/.../v3/BleBondManagerV3.java`, method `t`):

1. The first FFB2 notification while the "receiving" flag `k` is false is the header. The app reads `partnerId = b[0]`, `numberOfFrames = b[1]`, `numberOfPackets = b[2]` as uint8 values, then sets `k = true`.
2. For each following notification, it increments the packet counter `l` and appends **exactly 20** uint8 values. A notification shorter than 20 bytes aborts reception and resets the state.
3. When `l == numberOfPackets`, it removes trailing `255`s, then removes leading `255`s (everything before the first non-255 value). It converts the remaining bytes to `Long` and calls `onTouchReceivedFromBracelet(list, MenuIndex(partnerId))`.

The resulting list goes unchanged through `BleBondRepository$start$9` (`OnTouchReceived`) and `MessagesRepository.h()` to `MessagesRepository$onTouchMessageFromBracelet$1`. That builds `TouchMessageContent(timestamp, pattern = list, generation = THIRD)` and POSTs it. The bytes are never converted.

> FFB1 carries only state and event notifications. There is no per-touch FFB1 frame. The one exception is the factory response `[0xA1, 21, fingersCount, position1, position2]` (BleBondManagerV3.t, `intValue == -95`), which feeds `OnFactoryTouchPositions(fingersCount, position1, position2)` and is used for factory testing only.

## 2. Slides and swipes

- The protocol has **no gesture, direction or speed field**. Firmware state 7 stores only the per-window position byte (§1.2). The app's FFB2 parser produces nothing but the byte list (§1.3).
- Slide direction, speed and extent are implicit in the time series. For example:
  - an upward slide with one finger: `F1 F2 F3 F4 F5 F6 F7`
  - a slow slide: the same values, each repeated
  - a two-finger pinch: `0x35, 0x44` (fingers at 5/3, then 4/4)
- The app reconstructs "swipes" **only for drawing**:
  - `TouchViewV3Kt.a` (re-decompiled) and the legacy `components/TouchMessageV3View.a/b/g` decode each sample: `hi = (v & 0xFF) >>> 4`, `lo = v & 0xF`, and a nibble counts only if `< 9`. They build a grid of N columns (time) by 9 rows, with row `8 - p`, so position 8 is drawn at the top.
  - A swipe is a chain of set cells in consecutive columns whose row changes by ±1 per column in one direction. Up to 6 flat steps are allowed (`i23 + 1 >= 7` breaks the chain). The chain is kept if its first and last rows differ by at least 1. Everything else is grouped into rectangular "blocks".
  - `TouchMessageV3View.SwipeDirection` has `UP` and `DOWN`. These are display-only types: `TouchViewV3Swipe(positions)`, `TouchViewV3Block(x, y, width, height)`, `TouchViewV3Model(blocks, swipes)`.
- The legacy view's edit-mode preview data (TouchMessageV3View constructor, `isInEditMode`) shows the encoding: `F0 F0 FF… 80 80 80 … 88 F1 72 F3 F4 F5 F5 F5 F5 F7`.

## 3. Phone to bracelet: playback

### 3.1 FFB2 write frames (app side)

`BleBondManagerV3.g(gatt, BondTouchMessage msg, int color1, int color2, int vibration, int menuIndex, boolean z)` is called from `DelegatingBraceletConnection.f`. The arguments are `(…, i, i2, userVibration, menuIndex.a, z)`.

The header packet is 20 bytes, `WRITE_NO_RESPONSE`:

| byte | value |
|---|---|
| 0 | `menuIndex` (MenuIndex FIRST/SECOND/THIRD = 1/2/3). This is the sender slot, **not** a device id. |
| 1 | `pattern.size` (uint8, truncated) |
| 2 | `ceil(pattern.size / 20)` |
| 3..5 | color1 R, G, B |
| 6..8 | color2 R, G, B |
| 9 | `z ? 1 : 0` |
| 10..19 | `0xFF` padding |

The `vibration` argument is **not** sent.

Data packets: the pattern is split into chunks of 20 (`ta1.X1(list, 20, 20, true)`). Each element is written as **one uint8** (`setValue((int) long, FORMAT_UINT8, i)` in `WriteFFB2Command.execute`), and the remainder of the last packet is padded with `0xFF`.

### 3.2 Firmware FFB2 write handler (0x254CC, `ble_bond3.c`)

**First packet** (receive counter 0x20002DF2 == 0):

- The packet is rejected unless `b[0]` is 1..3 and `b[2]` is 1..10. So **at most 10 packets, which is 200 samples**.
- Fields are stored as follows:

| byte | stored at | meaning |
|---|---|---|
| `b[0]` | 0x20003015 | sender index |
| `b[1]` | 0x20002DF3 | play length |
| `b[2]` | 0x20002DF4 | packet count |
| `b[3..5]` | 0x20002634 | color1 |
| `b[6..8]` | 0x20002630 | color2 |
| `b[9] != 0` | flag 0x20002E7C (0x28668) | see below |

- The bracelet then selects colour mode 1 if color1 == color2 and mode 2 (gradient) otherwise (0x22BC8).
- It starts a 10 s receive timeout (`0x28680(10000)`).

**Packet k** (k = 1..count): copied verbatim to `0x20002E84 + (k-1)*20` (0x28610 → memcpy 20 bytes). After the last packet it posts the play event (0x2557C).

**Meaning of `b[9]`.** At the end of playback (0x27520..0x27536), if the flag is set the bracelet enters internal state 6, REPLY_MENU (SYS_STATE `0x89` = 137). Otherwise it returns to idle (0x27394, state 4). So "stopFlag" in BLE_PROTOCOL.md is really **"offer the reply menu after playing"**. The Android code paths found always pass `false`. **UNCERTAIN** whether another path passes `true`.

### 3.3 Playback rendering (MSG_PLAYING, internal state 10, SYS_STATE 0x87)

- **Entry** (0x275BC): sets the play length from `b[1]` (0x20002E7E) and starts the same **50 ms repeating timer** (0x666 ticks).
- **Each tick** (0x274B0) reads `s = inbuf[idx]`:
  - `s == 0xFF`: LEDs off and motor off (0x28376)
  - otherwise `lo = s & 0xF`, `hi = s >> 4`:
    - `hi == 0xF` (one finger, 0x282A6): `display(mode 1, [lo])` lights LED `lo`, and `motor(lo)` runs
    - two fingers: `display(mode 2, [lo, hi], idx)` lights LEDs lo..hi, with the in-between LEDs dimmer (0x223D2..0x2245E), and `motor((lo + hi) / 2)` runs
  - `idx++`; when `idx >= length - 1` the message ends (0x274FA..0x27506 → 0x2809E). The last sample may therefore not be rendered. **UNCERTAIN** (off-by-one).
- **LEDs**: `common/display/AW20036.c` / `display.c` (0x2237C). The display loop clears **9 LEDs** (indices 0..8), then sets the RGB color (0x2087C), turns the LED on (0x20A08) and sets brightness (0x20824) for the LED at index = position. The colour comes from color1/color2 according to the colour mode. A sample-index argument (`idx`) is passed in, which fits a color1→color2 gradient over time. The app's `TouchViewV3Kt.b()` likewise interpolates colour along the time axis. **UNCERTAIN** exactly how the firmware computes the colour.
- **Haptics**: `common/motors/HMD_AW86224.c`, `motor(p)` at 0x22DB8. Two AW86224 haptic drivers (I2C address 0x58) sit on two TWI instances (0x20002094 and 0x2000208C). Motor A gets register 0x1E = `table[p] - balance`. Motor B gets register 0x1E = `table[8-p] + balance`. The 9-entry table is at 0x20002638 and the balance is at 0x20002641. The vibration is therefore **panned between two motors according to position**, so a slide feels like it moves along the bar. **UNCERTAIN**: the exact AW86224 register semantics of 0x1E (likely a gain or amplitude).
- **During recording** the same display and motor calls give live feedback (§1.2).

## 4. Server message and generation conversion

`TouchMessageContent` (`models/TouchMessageContent.java`) has JSON fields `timestamp`, `pattern: List<Long>` and `generation` (enum `v29`: SECOND = `"2"`, THIRD = `"3"`; an unknown value falls back to SECOND).

- **Generation 3 pattern** = the sample bytes (0..255) as stored. There are no negative numbers or sentinels other than `255` = no touch. Leading and trailing 255s are already stripped by the receiver.
- **Duration**: `TouchMessageContent.Companion.a()` returns `size * 50` ms for THIRD and `sum(pattern)` for SECOND.
- **Gen 3 → gen 2**: `c(SECOND)` is used when the local bracelet is gen 2 and the message is gen 3:
  - start with `h = [50]` and `on = (p[0] != 255)`
  - for each sample: if a 255 arrives while `on`, append 50 and set `on = false`; if a non-255 arrives while not `on`, append 50 and set `on = true`; otherwise add 50 to the last element
  - The result alternates on/off durations in ms. Position is lost. Quirk: the first segment includes the initial 50, so it is 100 ms for the first sample.
- **Gen 2 → gen 3**: `c(THIRD)` is used when the local bracelet is a BTM and the message is gen 2:
  - `step = 50` if the total is at most 10 000 ms, otherwise `total * 50 / 10000`
  - each duration `d[i]` becomes `max(1, d[i] / step)` samples
  - even indexes (on) become the value **53 = 0x35**, which is two fingers at positions 5 and 3: LEDs 3..5 lit, motor centred at 4
  - odd indexes (off) become 255
  - the result is truncated to **200** samples
- The local generation comes from `BleBondRepository.a()`: `BleBondTouchDevice` ordinal 2 (BTM) → THIRD, the others → SECOND. `BleBondRepository.h()` calls `touchMessage.getC().c(gen)` before `DelegatingBraceletConnection.f`. If the converted list is empty, it falls back to `[500, 250, 500, 250, 500]` (`BleBondManagerMiniKt.b`). That fallback is a gen-2-style list, and on a BTM its bytes would be written truncated to uint8 (500 → 0xF4). This is a quirk; avoid it.
- If a gen-3 pattern is longer than 200 samples, the app still sends it, but `b[2] = ceil(n/20) > 10` makes the firmware reject the header (§3.2). It also truncates `b[1]` to uint8. **Keep gen-3 patterns at 200 samples or fewer.**

## 5. Generation THIRD vs SECOND touch meanings

`TouchMeaningFeatureViewModelKt.a()` maps `TouchMeaningGeneration` ordinal 0 → `v29.SECOND` and ordinal 1 → `v29.THIRD`. A meaning stores a `TouchMessageContent` with its generation. When it is sent (`BleBondRepository.d(meaningMessage, …)`), the pattern goes through the same `c(localGen)` conversion. So:

- THIRD meanings use 50 ms position samples, at most 200 samples (10 s), with duration `size * 50`.
- SECOND meanings use alternating on/off ms durations.

No other semantic difference was found.

## 6. Notes for an interoperable generator (Apple Watch "touch bar")

1. Divide the watch's touch strip into 9 bins. Pick an orientation: the app draws p=8 at the top. On the bracelet, p increases as the controller's raw Y decreases. Which physical end that is remains **UNCERTAIN**.
2. Sample every 50 ms. For each window emit:
   - `0xFF` if no finger is down
   - `0xF0 | p` for one finger
   - `(p2 << 4) | p1` for two fingers
3. Strip leading and trailing `0xFF`. Cap the list at 200 samples. POST `{timestamp, pattern: [..bytes as numbers..], generation: "3"}`.
4. To play directly on a BTM:
   - write the FFB2 header `[slot(1..3), n, ceil(n/20), c1R, c1G, c1B, c2R, c2G, c2B, replyMenu(0/1), 0xFF × 10]`
   - then write ceil(n/20) packets of 20 sample bytes, with the last packet padded with `0xFF`

## 7. Worked example

The gesture:

- tap at position 2 for 150 ms
- 100 ms gap
- one-finger slide from 1 up to 7 over 350 ms
- 100 ms two-finger hold at 3 and 5

Samples, 50 ms each:

| t (ms) | 0 | 50 | 100 | 150 | 200 | 250 | 300 | 350 | 400 | 450 | 500 | 550 | 600 | 650 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| byte | F2 | F2 | F2 | FF | FF | F1 | F2 | F3 | F4 | F5 | F6 | F7 | 35 | 35 |
| pattern | 242 | 242 | 242 | 255 | 255 | 241 | 242 | 243 | 244 | 245 | 246 | 247 | 53 | 53 |
| 2D points (t, pos) | (0,2) | (50,2) | (100,2) | – | – | (250,1) | (300,2) | (350,3) | (400,4) | (450,5) | (500,6) | (550,7) | (600,3)+(600,5) | (650,3)+(650,5) |

Server body:

```
{"timestamp": …, "pattern": [242,242,242,255,255,241,242,243,244,245,246,247,53,53], "generation": "3"}
```

The duration is 14 × 50 = 700 ms.

**From the bracelet** (FFB2 notifications; the recording always holds 200 samples):

```
header : 01 C8 0A 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
pkt 1  : [FF … FF leading samples before the first touch]
…      : F2 F2 F2 FF FF F1 F2 F3 F4 F5 F6 F7 35 35 FF FF …
pkt 10 : FF × 20
```

The app strips leading and trailing `FF`, which gives the pattern above.

**To the bracelet** (FFB2 writes; slot 1, color1 = color2 = #FF0080, no reply menu):

```
header : 01 0E 01 FF 00 80 FF 00 80 00 FF FF FF FF FF FF FF FF FF FF
pkt 1  : F2 F2 F2 FF FF F1 F2 F3 F4 F5 F6 F7 35 35 FF FF FF FF FF FF
```

Playback on the bracelet:

- LED 2 lit with the motor panned to position 2 for 150 ms
- dark for 100 ms
- the lit LED and the vibration then walk from 1 to 7, 50 ms per step
- finally LEDs 3..5 light with the motor centred at position 4

## Corrections to BLE_PROTOCOL.md §1.5

- FFB2 header byte 0 is the **menu/partner slot (1..3)**, not a device id.
- FFB2 header byte 9 ("stopFlag") means **enter REPLY_MENU after playback**.
- "On/off duration bytes" are, for v3, **50 ms position samples**: `0xFF` means no touch, and the two nibbles hold the finger positions.
- Recorded touches arrive as FFB2 notifications: header `[slot, 200, 10, 0…]` followed by 10 packets of 20 bytes.
