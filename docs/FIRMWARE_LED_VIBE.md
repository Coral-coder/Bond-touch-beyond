# Bracelet firmware: how LED and vibration patterns are accepted and played

This comes from static analysis of the official DFU images in `Firmware/`. Nothing here was
run on a bracelet. A **fact** is something read directly from the code. Anything marked
**HYPOTHESIS** is an inference, and the evidence is given with it. Addresses are absolute
(load base + file offset).

Related docs: `BLE_PROTOCOL.md` (GATT layout, app side) and `BTM_TOUCH_FORMAT.md` (Bond
Touch More touch samples, FFB2). This document covers the firmware side of those protocols.

## TL;DR

| | Bond Touch (v2), Bond Touch 4, Bond Mini | Bond Touch More (v3/BTM) |
|---|---|---|
| **Light only, no vibration** | `0x26` with `strength = 0` (or `vibMs = 0`). The motor and the LED are handled separately. | FFB1 `[01 4B 00 00 R G B]`. This code path never calls the motor. |
| LED hardware | AW9109 9-channel LED driver = 3 RGB LEDs. It runs a small uploaded pattern program. | AW20036 matrix driver, 9 LEDs along the bar |
| Brightness field | **1..100 (%)**. **0 or >100 turns the LEDs OFF.** | Global setting, cmd `0x4D` |
| Pattern clock | Per-step app_timer. v2: 1.007 ms ticks, **minimum 5 ticks**. v4/Mini: 30.5 µs ticks. | Fixed **50 ms** per FFB2 sample |
| Hardware blink | `0x26` ledMode 3: `hold` = on time, `sleep` = off time. Programmed in 0.5 ms units. | n/a |
| Max steps per pattern | `0x33` queue: **256 steps**. `0x26` queue: **20 steps**. | 200 samples (10 packets) |

Example: 1 s of red at 80 % with no vibration, on v2, Bond Touch 4 or Mini (FFA6, 20 bytes):

```
26 00 00 00 00 00 01 FF 00 00 50 00 00 00 00 00 00 E8 03 00
│  │  │  │  └vib┘ │  └─RGB──┘ │  └trans┘└hold┘└sleep┘└exec┘
op    q  strength  mode=1     bright=80             execute=1000 ms
```

**Bug in the app.** `BondGATT.ledMotor(...)` sends `brightness: 255` by default, and so does
`heartbeatPulse`. On the v2, v4 and Mini firmware a brightness above 100 takes the
"LEDs off" branch. Those heartbeat pulses therefore buzz without lighting. Use a value from
1 to 100.

---

## 1. Images, MCUs, base addresses

| Image | MCU / SoftDevice | Base | Evidence |
|---|---|---|---|
| `bondTouch.zip` (v2 2.7.9) | nRF51822, Cortex-M0, S130 | **0x1B000** | SP 0x200068B0; reset 0x1B0D9; only the HardFault vector is set (M0); fixed calls resolve |
| `bondTouch4.zip` (2.0.3) | nRF52832 (64 KB RAM), Cortex-M4, S132 v6/v7 | **0x26000** | SP 0x20008ED8 (more RAM than an nRF52810 has); reset 0x263E1; MemManage, Bus and Usage vectors present |
| `bondMini.zip` (1.2.0) | same family as BT4 | **0x26000** | SP 0x20008610; same vector layout and code base as BT4 |
| `bondTouchMore.zip` (3.1.1) | nRF51822, M0 | **0x1B000** | already established in `BTM_TOUCH_FORMAT.md` |
| `bondTouch-hw203.zip` (v1 1.2.96) | nRF51822, M0, S130, legacy DFU 0.5 | **0x1B000** | SP 0x200033C8; reset 0x1B0F5 |

The v2, v4 and Mini images are one Keil code base with shared source paths: `user_ble.c`,
`app_misc.c`, `user_queue.c`, `user_leds.c`, `user_timer.c` and `aw9109_support.c`.
Strings are referenced with `adr` (PC-relative), not through literal pools. BTM is a
different code base (`common/ble_bond3/*.c`, `bond3_fsm.c`).

Peripherals:

| Function | v2 / v4 / Mini | BTM |
|---|---|---|
| LED driver | **AWINIC AW9109** at I2C **0x2C**. v2: TWI0, SCL P0.03, SDA P0.04, **400 kHz** (config at 0x2CE2C = `{0x40003000, 3, 4, 0x06680000}`) | AW20036 |
| Motor | 1 ERM motor on **app_pwm**, period **5000 µs** (200 Hz), duty = strength %. v2 instance at 0x2CE04. | 2× AW86224 haptic drivers (I2C 0x58) |
| Accelerometer (taps) | DA217 / BMA253 (v4: SC7A20H) | |

## 2. Command table: v2, v4 and Mini (characteristic `d3c0ffa6`)

### 2.1 Write path

- **v2**: `ffa6_on_write` 0x20848 calls `process_app_cmd` 0x286E4 directly with the
  20-byte frame.
- **v4** (`ffa6_on_write` 0x2C274) and **Mini** (0x2B368) also accept two other forms:
  - **Batch**: `[0x88, len1, frame1…, len2, frame2…]`. Each sub-frame is passed to
    `process_app_cmd` in turn. v4 asks for an ATT MTU of **247**
    (`nrf_ble_gatt_att_mtu_periph_set(…, 0xF7)`), so one write could carry about 13
    `0x33` steps. **HYPOTHESIS**: the FFA6 attribute `max_len` is large enough for this.
    Its value was not checked; the presence of the batch decoder suggests it is.
  - **Ping**: a 1-byte write `[0x10]` schedules a handler that sends `"ABCD"` back.
    **HYPOTHESIS**: this is a link test.

### 2.2 Dispatcher

Opcode = `frame[0]`, and `frame[1]` is ignored. Every opcode except `0x31` is rejected
unless the bond state (global +8) is ≥ 0x85 (CONNECTED) and ≠ 0xFF. A rejected frame only
logs "BondTouch has not been certified".

v2 is a Keil `switch8` at 0x28706: count byte 0x10, target = 0x2870A + 2·b. v4 is a `tbb`
at 0x37BC0. Mini is at 0x343F0 and adds `0x35`.

| Op | Meaning | Payload / notes |
|---|---|---|
| `0x25` | DFU | `[25 00 11 22 33 44]`. "Goto DFU mode. Restart now!" |
| `0x26` | **LED + motor control** | §3. `frame[2]` = 1 adds the frame to the CTRL queue; any other value runs it now. |
| `0x27` | Config write | `config_cmd_process` (v2 0x20C6C, v4 0x2C858). Properties as in BLE_PROTOCOL.md. |
| `0x29` | **Factory/test mode** | The check is inverted in all three images: the firmware enters factory mode when bytes 2..5 are **not** `11 22 33 44` (v2 0x287B6: `memcmp == 0` returns; v4 0x37C8A; Mini `if (memcmp != 0)`). So `[29 00 11 22 33 44]` does nothing, and any other payload enters factory mode. v4 logs "Goto Factory mode now!". v2 sets state 0x87, lights white at 100 % and starts a 30 s timer. Avoid sending it by accident. |
| `0x2A` | **Reboot** | `[2A 00 11 22 33 44]`. v4 logs "Bond Touch reboot now!". |
| `0x31` | PAIRED answer | Accepted only in OOBE (0x84) after event 0x13. Plays a white breathe and a 300 ms buzz at 80 %. |
| `0x32` | **Start queue** | `[32 00 11]` runs the CTRL queue (`0x26` items). `[32 00 22]` runs the TEST queue (`0x33` items). |
| `0x33` | **Add a step to the TEST queue** | §4 |
| `0x34` | Double-tap test mode | `[34 00 11]` = on ("Set BONDTOUCH to double tap test mode!"), `[34 00 22]` = normal. Not ANCS: this corrects BLE_PROTOCOL.md §1.3. |
| `0x35` | Mini only | `[35 00 88]` toggles a pair of flags (0x39194 / 0x391AC). The `0x26` path writes the same flags. **HYPOTHESIS**: they gate tap/touch input. |

There is **no** separate "LED only", "find me" or notification opcode. Light-only output is
`0x26` (or `0x33`) with strength 0. Charging, low-battery, OOBE and disconnect animations
are internal LED modes (§5). Their colours and timings come from config properties
0x21–0x29 and 0x31.

## 3. `0x26`: LED and motor control

`cmd26_led_motor_ctrl_execute` is at v2 0x21878, v4 0x2DF34 and Mini 0x2CB20. The code is
the same in all three. `p` = `frame + 2`.

| frame byte | field | firmware behaviour |
|---|---|---|
| 2 | queue | 1 = add to the CTRL queue (20 entries × 17 bytes). Otherwise run now. |
| 3 | strength | If **0 or >100**, or `vibMs == 0`: `motor_off()`. Otherwise `motor_on(strength %, vibMs)`. |
| 4–5 | vibMs (LE) | Motor stop timer |
| 6 | ledMode | 1 = solid, 2 = breathe, 3 = **blink**, 4 = off. Other values leave the LEDs unchanged. |
| 7–9 | R, G, B | Raw RGB. The firmware applies per-channel calibration (`led_color_calibration`). |
| 10 | brightness | **1..100**. 0 or >100 = **LEDs off** |
| 11–12 | transition (LE) | breathe rise time = fall time |
| 13–14 | hold (LE) | breathe top / blink on time |
| 15–16 | sleep (LE) | breathe bottom / blink off time |
| 17–18 | execute (LE) | **total LED time**. 0 = LEDs off. A timer turns all LEDs off when it expires ("User LEDs timer timeout. All LEDs off."). |

The motor and the LEDs are decided **independently**:

```
; v2 0x21878 (p = frame+2)
00021878  ldrb r0,[r0,#1]          ; strength
0002187e  cmp r0,#0 / beq off      ; 0      -> motor_off
00021882  cmp r0,#0x64 / bhi off   ; >100   -> motor_off
0002188a  vibMs = p[3]<<8|p[2] / beq off
00021890  bl motor_on(strength, vibMs)        ; 0x1d408
00021894  exec = p[16]<<8|p[15]
0002189e  beq leds_off                        ; execute == 0
000218a2  cmp ledMode,#4 / beq leds_off
000218a8  cmp bright,#0x64 / bhi leds_off     ; brightness > 100 => OFF
000218ae  cmp bright,#0 / beq leds_off
000218be  mode 1 -> leds_req_blink(rgb, bright, 0xFFFF, 0, exec)   ; solid
000218c6  mode 3 -> leds_req_blink(rgb, bright, hold, sleep, exec) ; blink
000218ca  mode 2 -> leds_req_breath(rgb, bright, trans, trans, hold, sleep, exec)
```

In mode 1, `hold` and `sleep` are ignored (the firmware forces 0xFFFF and 0). The `0x26`
path gives all three LEDs the same colour.

Byte examples (20 bytes, zero-padded):

- Solid red, 80 %, 1 s, no motor: `26 00 00 00 00 00 01 FF 00 00 50 00 00 00 00 00 00 E8 03 00`
- Hardware blink, white, 5 ms on / 5 ms off for 1 s, no motor: `26 00 00 00 00 00 03 FF FF FF 64 00 00 05 00 05 00 E8 03 00`
- LEDs off: `26 00 00 00 00 00 04 …`
- Motor only (the app's preview): strength `S`, vib 2000 ms, ledMode 4

Queued `0x26` items (`start_execute_queue_led_motor_ctrl`, v2 0x2A994, v4 0x3A3D4) run
through the same function. The next item starts after **max(vibMs, execute)** ms. While the
queue runs the state is 0x88 QUEUE_EXECUTING and single-tap detection is switched off. When
the queue is empty the state goes back to 0x85. The LEDs are switched off by the execute
timer of the last item.

## 4. `0x33`: TEST queue steps (arbitrary patterns, per-LED colour)

Layout: `[33 00 strength b1 b2 b3 R1 G1 B1 R2 G2 B2 R3 G3 B3 ms_lo ms_hi 00 00 00]`. 15
bytes are stored per step and the queue holds **256 steps** (nrf_queue descriptor v2
0x2CDA4, v4 0x402F8, Mini 0x3A8C0: `size 0x100`, `elem 0xF`). Playback starts with
`[32 00 22]`.

Step executor: v2 0x21934, v4 0x2DFC8. Queue runner: v2 0x2AAC0, v4 0x3A4F8.

- `ms == 0`: motor off and LEDs off. The runner then stops its timer without finishing the
  queue. **HYPOTHESIS**: the queue stalls in state 0x88. Do not send `ms = 0`.
- Motor: strength 1..100 runs the motor for `ms`. Strength 0 turns it off. **Strength 0 =
  silent step.**
- LEDs: if any of b1..b3 is in 1..100, the step shows **three separately coloured RGB
  LEDs** (`leds_req_test_3color`, mode 0x17). Otherwise the LEDs are off for this step.
  Colour and brightness can therefore change from step to step. The on time is programmed
  as `ms + 100` with off time 0, so steps join without a gap.
- The next step starts after `ms` (0xFFFF = no timer, hold forever). When the queue is
  empty, the motor and LEDs go off and the state returns to 0x85.
- AW9109 channel map (`aw9109_build_blink_program_3rgb`, v2 0x23958 / v4 0x30604):
  LED1 = ch 6/5/4, LED2 = ch 3/2/1, LED3 = ch 8/9/7. Each value is
  `value = channel · (b/100) · calib`, computed in double precision (`100.0` = 0x40590000).

**HYPOTHESIS**: the three AW9109 RGB groups are three physical LEDs under the diffuser.
For: three independent colour slots in `0x33`, and nine channels in three groups. Not
verified: whether they are far enough apart to look like separate pixels.

## 5. LED back end (v2, v4, Mini)

The `leds_req_*` functions only fill a request block (v2 0x20004F70, v4 0x200054C8), set
the mode byte at +0x31 and set a busy flag. The **main loop** (v4 0x31610) dispatches the
mode:

| mode | name (v4 debug string) | runner (v2 / v4) |
|---|---|---|
| 0x11 | LEDS_MODE_BREATH | 0x23668 / 0x301D8 |
| 0x12 | LEDS_MODE_BREATH_DISCONNECT | 0x235B8 / 0x30128 |
| 0x13 | LEDS_MODE_BREATH_LOWBATTERY | 0x23610 / 0x30180 |
| 0x14 | LEDS_MODE_FADE_OUT | 0x236FC / 0x30274 |
| 0x15 | LEDS_MODE_CONSTANT_ON | 0x236B8 / 0x30230 |
| 0x16 | LEDS_MODE_BLINK (used by `0x26` modes 1 and 3) | 0x23564 / 0x300D4 |
| 0x17 | LEDS_MODE_TEST (used by `0x33`) | 0x23740 / 0x302B8 |
| 0x19 | partner-colour breathe (v4) | – / 0x3C468 |
| 0x1A | LEDS_MODE_TEST_JS: fixed blue breathe | – / 0x2FF10 |

Every LED change **builds an AW9109 instruction program and uploads it over I2C**. The
direct-PWM path is not used.

```
aw9109_load_program (v2 0x1E798, v4 0x2A774):
  wr16(0x53,0) ; wr16(0x54,0) ; wr16(0x7E,0)        ; stop the engine, SRAM address 0
  for each word: wr16(0x7F, word)                    ; 21 words (blink) / 40 words (breathe)
aw9109_run_program (v2 0x1E7EA):
  wr16(0x5F,0) ; wr16(0x54,2) ; wr16(0x53,1)
```

Blink/solid program (21 words) and the WAIT encoder:

```
[0..8]   0xA000 | (ch+1)<<8 | on_value     ; set the 9 channels
[9]      WAIT(on_ms)
[10..18] 0xA000 | (ch+1)<<8 | 0            ; channels off
[19]     WAIT(off_ms)
[20]     0x0000

aw9109_encode_wait (v2 0x1E10C, v4 0x29E90):
  ms < 510 : 0x3800 | (ms*2)                 ; units of 0.5 ms
  else     : 0x3800 | 0x400 | (ms>>4)        ; units of 16 ms
```

**HYPOTHESIS**: word 20 (`0x0000`) loops the program, so blink and breathe repeat in
hardware until the execute timer switches them off.

- For: the mode is called BLINK, and it has separate on and off times.
- For: the app's touch playback sets `execute = on + off` to get exactly one breath cycle,
  which would only be needed if the program repeats.
- Against: there is no AW9109 datasheet here to confirm the opcode.

The 0.5 ms and 16 ms step sizes are also inferred, from the 2× and ÷16 scaling and the
510 ms threshold.

Upload cost: each register write is 4 bytes on the I2C bus, about 90–100 µs at 400 kHz. A
21-word program plus 6 control writes is about **27 writes ≈ 3 ms**, plus driver overhead.
On v2 add the soft-float colour math on a 16 MHz M0. **HYPOTHESIS**: the LEDs stay dark or
hold their last value while the engine is stopped during the upload, so each step change
can glitch for a few ms.

## 6. Timing resolution and limits

| | v2 (nRF51) | v4 / Mini (nRF52) |
|---|---|---|
| ms → ticks | `(ms·32768 + 16500) / 33000` (prescaler 32, **1.007 ms/tick**) | `(ms·32768 + 500) / 1000` (prescaler 0, **30.5 µs/tick**) |
| `app_timer_start` minimum | ticks < 5 returns `NRF_ERROR_INVALID_PARAM` (0x1DD04) | ticks < 5 returns 7 (0x29A3C) |
| Effect of a too-short timeout | `APP_ERROR_CHECK` → app_error_handler 0x1D3A0 → `NVIC_SystemReset` (0x1BF30). **The bracelet reboots.** | same path ("System reset"), but 1 ms = 33 ticks is always valid |
| Smallest safe step (`0x33` ms, `0x26` execute/vibMs, queue step) | **≥ 5 ms** (1–4 ms reboots the bracelet) | **≥ 1 ms** |
| Engine blink resolution (`0x26` mode 3) | 1 ms in the field (0.5 ms internally) up to 509 ms; 16 ms steps above | same |

Values for v2 that would crash it, and must be avoided: `vibMs` 1..4, `execute` 1..4, and a
`0x33` `ms` of 1..4.

The app's current 50 ms sampling is a choice made by the app, not a firmware limit, on
v2/v4/Mini. On BTM, 50 ms *is* the firmware clock: the FFB2 player uses a fixed 0x666-tick
(50 ms) timer; see `BTM_TOUCH_FORMAT.md`.

## 7. Persistence of vision (POV): fastest LED toggling and a recommended format

1. **Fastest toggle: AW9109 hardware blink**, one `0x26` frame with mode 3. On time = `hold`
   ms and off time = `sleep` ms, both at least 1, so up to about 500 Hz. The rate holds
   steady until `execute` runs out because it does not depend on BLE or the CPU. It can
   only make a periodic one-colour square wave, though. Good for a strobe or flicker
   effect, not for text.
2. **Arbitrary columns: the `0x33` TEST queue.** Up to 256 steps. Each step has 3 RGB
   colours, 3 brightness values and a motor strength (set it to 0). The step time is
   firmware-timed, so BLE jitter does not matter once the queue is loaded.
   - v4 / Mini: use **4–5 ms per column**. 1 ms is legal, but each step re-uploads the
     AW9109 program (about 3 ms of I2C), so shorter columns blur or glitch.
   - v2: **at least 5 ms** (hard limit, see the crash above). Plan on 6–8 ms.
   - Load: write N `0x33` frames, then `[32 00 22]`. On v4/Mini, pack them in
     `[0x88, 17, frame, 17, frame, …]` writes; v2 has no batch form. A 256-column message
     at 5 ms lasts 1.28 s. Repeat it by sending it again.
   - A "pixel" is a whole LED (only 3 LEDs on v2/v4/Mini), so a column is at most 3 pixels.
     **HYPOTHESIS**: the three LEDs are not lined up for vertical POV text. A one-pixel
     POV heart or text has to come from swinging the whole band, with each step = one
     column (on/off or colour).
3. **Do not** stream single `0x26` frames for POV. Every write goes through BLE with
   response (one or more 7.5 ms+ connection events) plus the AW9109 upload, which gives
   tens of ms with jitter.
4. **BTM**: 9 bar LEDs, but the only sequenced player (FFB2) runs at a fixed 50 ms per
   sample, and each sample lights at most 2 LEDs at full brightness plus dim neighbours
   (exact rule in §12.2). That is too slow for POV. See §12 for every per-LED and speed
   option found.

## 8. Bond Touch More (BTM): FFB1 commands relevant here

The FFB1 dispatcher is `ffb1_app_cmd_dispatch` at 0x249C4. The frame is `[prefix, cmd,
args…]`. Up to 18 argument bytes are copied, and the jump table at 0x3312C is indexed by
`cmd − 0x11` (valid commands 0x11..0x57). For the "set or read" commands, `args[0] == 0`
means set and anything else means read back with an ack `[0x0A, cmd, …]`.

| cmd | Meaning (firmware) |
|---|---|
| `0x4B` | `cmd4b_led_color` 0x22B84. `[01 4B 00 led R G B]` schedules display event 2 at 0x21E64. `led == 0`: all 9 LEDs show RGB at the saved brightness (`display_all_leds_color` 0x21CF0). `led == 1`: brightness is set on all 9, then the colour on LEDs 0 and 1. `[01 4B 01]` = clear. **No motor call.** Before scheduling, it also posts FSM event 0x1E, but no state handles that event (§12.4), so `0x4B` changes no state. No timeout was found in this path, so the light stays until cleared. TEST_COLORS is entered by `0x47` (§12.3). |
| `0x48` | Vibration. Requires `args[0]` bit 0 clear, level ≤ 100 and balance ≤ 4; otherwise it only sends the ack `[0A 48 level balance]`. It sets `gain[i] = level·base[i]/100` for the 9 positions (0x23238) and the balance offset (0x232C0). `args[0] == 0` then plays a preview buzz (0x232D4); otherwise it saves (0x29E00). **Level 0 is accepted** (there is no lower bound). |
| `0x4D` | **Global LED brightness**: `[01 4D 00 val]` sets (0x22690 / 0x29DA4), `[01 4D 01]` reads. The original app never sends it. |
| `0x4E` | LED driver setting, low nibble (0x29DBC); values 0..3 or 8..14. **HYPOTHESIS**: AW20036 global current. |
| `0x45`, `0x49`, `0x4A` | User menu, battery-alert settings, accelerometer sensitivity (same set/read pattern) |
| `0x2A` | DFU |
| `0x1B` / `0x1C` / `0x40` / `0x41` / `0x42` | Device id (0xAB), firmware (0xAC), stats (0xAD / 0xAE / 0xAF) |
| `0x43` / `0x44` | Posts FSM events 0x18 / 0x19 (ANCS on/off) |
| `0x11`–`0x17`, `0x30`, `0x31`, `0x4C`, `0x4F` | Post FSM events 0x27..0x23, 0x10, 0x14, 0x1D and 0x20 (state changes such as test modes; not traced) |

**Light-only touch playback on BTM: HYPOTHESIS.** `motor_pan_position` (0x22DB8) writes
AW86224 register 0x1E with `gain[p] − bal` on motor A and `gain[8−p] + bal` on motor B. With
level 0 every `gain[i]` is 0.

- To try: save level 0 with `[01 48 02 00 02 03]`, then play an FFB2 touch.
- Expected: LEDs only.
- Unverified: whether `bal` for centre (balance 2) is 0. The balance table is at
  0x200020D0 and is initialised at run time. Also unverified: whether register 0x1E is a
  gain (0 = silent).
- Afterwards, restore the user's level.

## 9. Bond Touch classic (v1, hw203)

The v1 dispatcher is at 0x1B774: opcode u16 − 0x21, Keil `switch8`, target = 0x1B78E + 2·b.

| Op | Meaning |
|---|---|
| `0x21` | **Colour only, no motor.** `color u32 LE @4` = `[B, G, R, bright%]`. Each channel is scaled to `c·bright/100` (0x1B7A2) and written with `v1_led_set_color` 0x1D034 (3 PWM channels). Black turns the LED off. Light-only for v1: `[21 00 seq_lo seq_hi BB GG RR 64 …]`. |
| `0x22` | Sets or clears GPIO P0.10 and reconfigures the accelerometer (0x1FAEC). Meaning unclear; not the LED. |
| `0x25` | DFU when `@4 == 0xFFFFFFFF` (GPREGRET 0xB1 + reset) |
| `0x26` | LgtVib (as BLE_PROTOCOL.md §1.4); not traced further |
| `0x27` | ActConfig (param 1000 = save, …) |
| `0x23`, `0x24`, `0x28`, `0x29`, `0x31` | Present; not analysed |

## 10. Differences between models

| | v1 hw203 | v2 Bond Touch | Bond Touch 4 | Bond Mini | BTM |
|---|---|---|---|---|---|
| LED driver | direct PWM, 1 RGB | AW9109, 3 RGB | AW9109, 3 RGB | AW9109, 3 RGB | AW20036, 9 LEDs |
| Motor | GPIO/PWM | 1 ERM, PWM | 1 ERM, PWM | 1 ERM, PWM | 2× AW86224 haptic |
| Light-only | `0x21` | `0x26` strength 0 | same | same | `0x4B` |
| `0x88` batch / `[0x10]` ping | – | – | yes | yes | – |
| Timer tick / min step | ? | 1.007 ms / **5 ms (else reboot)** | 30.5 µs / 1 ms | 30.5 µs / 1 ms | 50 ms (FFB2) |
| Extra opcodes | – | – | – | `0x35` | `0x4D`, `0x4E` |

The Mini firmware accepts the full `0x26` / `0x33` protocol. The fixed `[500,250,500,250,500]`
touch pattern is something the original Android app does, not a firmware limit (the Mini
`0x26` handler 0x2CB20 is identical to v4's).

## 11. Reproducing

The DFU zips were unpacked into separate scratch directories. Two tools were used:

- capstone linear Thumb disassembly, with `adr` and literal-pool string annotation;
- Ghidra 11.1.2 headless (`BinaryLoader`, `ARM:LE:32:Cortex`, bases as in §1), with
  functions seeded from the vector table and from `bl` targets.

The derived pseudo-C, the annotated listings and the name maps are in
`Firmware/decompiled/<image>/`.

## 12. BTM per-LED colour

The goal checked here: light any subset of the 9 bar LEDs (a 9-bit mask per column, one
colour is fine), changed in ≤ 10 ms per column, for 9-pixel-tall POV text.

**Result: no command, on any characteristic, takes a per-LED mask or a per-LED
colour/brightness list.** The LED driver can do it (each LED has its own colour, scaling
and enable), and the firmware has an internal mask painter, but nothing from BLE reaches
it. Below are the closest options, each with its exact rule, followed by the evidence.

### 12.1 Driver facts (AW20036, I2C address 0x3A)

- **Per-LED records**: 9 records of 15 bytes at 0x20002578:
  - `[0..2]` enable copy
  - `[3..5]` R, G, B
  - `[6..8]` scaling (brightness) per channel
  - `[9..14]` register addresses (PWM, scaling)
- **Functions**:
  - `aw20036_set_rgb(led, rgb)` 0x2087C
  - `aw20036_led_on(led, on)` 0x20A08
  - `aw20036_set_brightness(led, sR, sG, sB)` 0x20824
- **Commits**:
  - `aw20036_commit_all` 0x2024C: page 2 (scaling) 27 writes, page 1 (PWM = RGB >> 2) 27
    writes, then the enable registers (`aw20036_write_enables` 0x20108, 7 writes). Total
    **63 two-byte I2C writes** per full-bar refresh.
  - `aw20036_commit_led` 0x203E8 refreshes one LED (about 9 writes).
- **Internal mask painter**: `display_mask_color(mask9, rgb)` 0x21BB0 turns everything
  off, then for each set bit `i` (bit 0 = LED 0 … bit 8 = LED 8) sets the colour, turns
  the LED on and commits it. Its **only callers** are the power-off animation in
  `bond3_fsm` (0x26C66 / 0x26CCA, mask `0x38` = LEDs 3–5, SYS_STATE 0x8C). No FFB1 or FFB2
  path reaches it.
- **TWI clock**: not found as a literal; it is probably in RW data initialised at boot.
  The I2C costs below are therefore given as transaction counts. At 400 kHz a 2-byte write
  is about 70–100 µs including driver overhead; at 100 kHz it is about 4× that.

### 12.2 FFB2 sample → lit LEDs (the fallback, exact rule)

Playback tick handler 0x274B0, 50 ms. Renderer `display_show(mode, pos[], idx)` 0x2237C.
`B` = global brightness byte at 0x200020C0, set by FFB1 `0x4D`. `b2` = byte at 0x200020C1 =
`max(1, B >> 3)` (`display_set_brightness` 0x22690).

```
s == 0xFF        -> all LEDs off (and motor off)               ; 0x274be -> 0x28376
lo = s & 0x0F ; hi = s >> 4
hi == 0xF        -> display_show(1, [lo])                       ; 0x274d0 -> 0x282b6
otherwise        -> display_show(2, [lo, hi])                   ; 0x274ea
motor: one finger -> motor_pan_position(lo); two -> ((lo+hi)/2)

mode 1 (one finger at p):  all off; p = FULL(B); p-1 = DIM(b2) if p>0; p+1 = DIM(b2) if p<8
mode 2 (a = lo, b = hi):   all off; a = FULL; b = FULL
    L = min(a,b), H = max(a,b), span = H-L
    H+1 = DIM if H<8 ;  L-1 = DIM if L>0
    span == 2  -> middle (H-1) = B>>1
    span >= 3  -> L+1 = DIM and H-1 = DIM ; LEDs L+2 .. H-2 stay OFF
    span 0 / 1 -> nothing more
```

All lit LEDs in a sample share one colour.

**HYPOTHESIS: out-of-range nibbles are unsafe.** The firmware does not check that a nibble
is ≤ 8. `lo` or `hi` = 9..14 would index past the 9 LED records and corrupt RAM. Send
only `0xFF`, `0xF0|p` or `(p2<<4)|p1` with `p`, `p1`, `p2` in 0..8.

This corrects `BTM_TOUCH_FORMAT.md` §3.3: a two-finger sample does **not** light the whole
range lo..hi. It lights the two positions plus their outer neighbours, and fills the inside
only when the span is ≤ 3.

What one FFB2 sample can therefore show, at full brightness:
- 1 LED, or
- 2 LEDs anywhere (`(p2<<4)|p1`), or
- 3 adjacent LEDs (span 2, with the middle LED at half brightness).

There is always a dim halo of `b2/B` ≈ 1/8 on the outer neighbours. It cannot be turned
off, because `b2` is at least 1.

**Colour modes** (byte 0x20002603, set by `display_set_color_mode` 0x22BC8):

| mode | colour | set where |
|---|---|---|
| 1 | colour 1 | FFB2 header, when colour 1 == colour 2 (0x25598) |
| 2 | **time** gradient `c1 + idx·(c2−c1)/len` | FFB2 header, when the colours differ (0x2553A) |
| 3 | menu-slot colour | only on entering MSG_RECORDING (0x2777C) |
| other | default colour at 0x20002600 | – |

- The gradient is per sample index, not per position.
- No header byte selects mode 3 or a per-position colour.
- Header byte 9 only sets the reply-menu flag (0x28668).

**The 50 ms period is fixed.** It is the literal `0x666` (1638 ticks of 32768 Hz) loaded at
0x275EC (playback entry) and 0x27782 (recording entry). No header or config field feeds it.

### 12.3 Options reachable from BLE

| # | Command (FFB1 unless noted) | What it lights | Speed / limits |
|---|---|---|---|
| A | `0x4B` all LEDs: `01 4B 00 00 R G B` | all 9, one colour | Per write: sched event → `display_all_leds_color` 0x21CF0 → 2 full commits ≈ **126 I2C writes**. Probably ~10–15 ms at 400 kHz (**HYPOTHESIS**, TWI clock unknown). Rate is set by BLE plus this cost. |
| A′ | `0x4B` "LED_0": `01 4B 00 01 R G B` | **LEDs 0 and 1 only**, one colour (0x21ECC) | `led` is **not** an index or mask: `1` → LEDs 0+1, any other value → all 9 (0x21E88) |
| A″ | `0x4B` clear: `01 4B 01` | off | **Powers the AW20036 down** (P0.01 low, 0x21F3C–0x21F4A). The next set raises P0.01, spins a 2000-iteration delay and re-initialises the driver. **For fast toggling, send "off" as `01 4B 00 00 00 00 00`.** |
| B | `0x47` TEST_COLORS: `01 47 R1 G1 B1 R2 G2 B2 SS` | **LEDs 0–3 = colour 1, LED 4 = off, LEDs 5–8 = colour 2** (`display_test_colors_split` 0x22A88), for `SS` = 1..10 s (other values → 10) | Enters state 20 (SYS_STATE 0x8E) from idle (`cmd47_store_test_colors` 0x28630 → display event 4 → FSM event 0x1B → 0x276BE). **A new `0x47` while in TEST_COLORS repaints at once and restarts the timer** (0x27610), costing **one** commit (63 writes), half the cost of `0x4B`. Use colour `000000` to turn one half off. This gives a 2-pixel column: top half / bottom half. If the bracelet is busy (flag 0x20002DF7), entry is deferred. |
| C | FFB2 touch (§12.2) | ≤ 2 LEDs at full brightness + halo | fixed 50 ms/sample, firmware-timed, ≤ 200 samples. Motor runs too, unless level 0 works (§8). |
| D | `0x45` partner menu colours | the MENU page shows LEDs 0–2 / 3–5 / 6–8 in the 3 slot colours (`display_partner_menu` 0x21F9C, page = active-slot mask 7) | MENU opens only from a physical touch gesture: touch IC reg1 == 3 → sched code 6 → FSM event 9 (`sched_event_to_fsm` 0x24380 → 0x27EAC). It cannot be triggered from BLE. |

**Write type.** FFB1 and FFB2 are declared with properties `0x1E` = read | **write without
response** | write | notify, with max length 20. Fact from `ble_bond3_service.c` char add
(Ghidra: `local_44[0] = … | 0x1e`, `local_50 = local_4c = 0x14`). Streaming A or B with
write-without-response avoids the ATT round trip. The original app uses write *with*
response.

### 12.4 Other FFB1 commands traced

| cmd | FSM event | Handled in | Effect |
|---|---|---|---|
| `0x12` | 0x26 | idle (4) | enters state 17: factory touch test. Touches draw with `display_factory_touch_two_color` 0x2260C (finger 1 and finger 2 in two fixed colours from 0x200020B0 / 0x200020AC), and positions are reported to the app. The positions come from the touch IC, not from BLE. |
| `0x15` | 0x24 | state 17 | → state 15: factory LED test. All 9 LEDs one colour (0x21CF0), stepping every 0.5 s (0x4000 ticks). |
| `0x13` | 0x25 | state 15 | → state 16: touch + motor test (0x2260C, 0x22DB8) |
| `0x11` | 0x27 | states 15 / 16 | leave the factory test |
| `0x17` | 0x23 | state 16 | (handler 0x26F9C; leave the test) |
| `0x4C` | 0x1D | MSG_PLAYING (10) | **stop FFB2 playback** and return to idle (0x27404) |
| `0x4F` | 0x20 | idle | state 14; ack `0A 4F …` with three counters (0x29F60 / 6C / 78) |
| `0x30` | 0x10 | state 3 | → state 2, SYS_STATE 0x82 (WAITING_TOKEN) |
| `0x31` | 0x14 | state 2 | (0x272F4) |
| `0x4B` | 0x1E | – | **no state handles event 0x1E**, so `0x4B` changes no state. This corrects the hypothesis in §8. |
| `0x43` / `0x44` | 0x18 / 0x19 | idle / state 19 | ANCS; state 19 sends SYS_STATE 0x8D |

None of them accepts per-LED data.

### 12.5 What this means for 9-pixel POV on a BTM

- **Not possible** with the stock firmware: an arbitrary 9-LED mask per column, at any
  speed.
- **Best streamable approximations**:
  1. A whole-bar on/off strobe with `0x4B` set colour / set black. Write-without-response
     on FFB1, about one update per connection event at best. **HYPOTHESIS**: around 10–15 ms
     per update, because of the I2C refresh.
  2. A 2-pixel column (LEDs 0–3 / LEDs 5–8) with repeated `0x47` writes. Cheaper refresh
     (63 writes) and firmware-held between writes. Enter the mode once from idle; each later
     `0x47` repaints.
- **Firmware-timed but slow**: FFB2 at 50 ms per column, ≤ 2 bright pixels + halo per
  column (§12.2).
- A true 9-pixel font would need modified firmware.
  **HYPOTHESIS**: the Nordic DFU path accepts unsigned images. For: `BOND_M_DFU` packages
  use a 141-byte init packet. Against: that size could include a signature.
