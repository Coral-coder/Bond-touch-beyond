# totwoo BLE Communication Protocol

Reverse-engineered from `com.totwoo.totwoo.apk` **v4.7.7 (versionCode 408)**, targetSdk 36.
All findings come from static analysis of the decompiled app (jadx + apktool). The app is
R8/ProGuard-obfuscated; class/field names below are the obfuscated names so you can cross-check
against `jadx_out/sources/`.

> Scope note: this documents the **"TWO"/"LCT" jewelry line** protocol (Nordic-nRF-based devices
> and the Locket "LCT" camera/locket). The app also bundles a second OTA stack for **Bluetrum
> (AB-series)** audio SoCs — see `FIRMWARE_OTA.md`.

---

## 1. Roles and transport

- The phone is **GATT central**; the device is **GATT peripheral**.
- The device is also registered as a **Companion Device (`CompanionDeviceManager`, WATCH profile)**;
  `com.totwoo.jewelry.ble.nordic.TotwooCompanionService` observes device presence and triggers
  reconnect/notify logic (`handleDeviceAppeared` → `zd.h.F("device_present")`).
- The BLE stack is **Nordic's Android BLE Library** (`no.nordicsemi.android.ble`). The totwoo
  device manager is `ae.n extends no.nordicsemi.android.ble.a` (a `BleManager`). The singleton
  façade/controller is `zd.h` (`h.q()`), which owns connection state and all command builders.
- Write type for commands is **Write Without Response** where possible (`setWriteType(1)`),
  and the library uses PRN (packet-receipt notifications) for OTA.

Key classes:

| Obfuscated | Role |
|---|---|
| `zd.h` (`h.q()`) | High-level BLE controller / singleton; builds and sends commands |
| `ae.n` | Nordic `BleManager` subclass; holds the 14 GATT characteristics; `o()` parses RX; `u()/v()/w()/x()/t()` send |
| `x4.c` | **Wire codec**: `g()` encode frame, `i()` decode frame, `b()` int→4B BE, `c()` bytes→int LE |
| `ad.b` | "AppPackage" (a logical command/response) |
| `ad.a` | A TLV **segment** inside an AppPackage |
| `ad.d` | Helpers: `b()` checksum (additive), `c()` bytes→int **big-endian**, `a()` hex, `f517a` reassembly buffer |
| `ad.f0.a()` | Monotonic 16-bit packet-index generator |

---

## 2. GATT table

Characteristics are discovered by matching the **16-bit UUID segment** (chars 4–8 of the 128-bit
UUID string) in `no/nordicsemi/android/ble/BleManagerHandler$4.java` (totwoo-patched discovery).
All proprietary UUIDs use the **Bluetooth base UUID** `0000xxxx-0000-1000-8000-00805F9B34FB`.

### 2.1 Proprietary data channels (three write/notify pairs)

| 16-bit | Field in `ae.n` | Direction | Purpose |
|---|---|---|---|
| **`FD1A`** | `f620k` (k) | **Write** (phone→device) | **Primary command channel** (most commands go here, via `u()`) |
| **`FD19`** | `f621l` (l) | Notify (device→phone) | Primary RX / responses |
| `FD0A` | `f624o` (o) | Write | Secondary write channel |
| `FD09` | `f625p` (p) | Notify | Secondary notify (`p()` enables this on connect) |
| `FD2A` | `f631v` (v) | Write | Tertiary write channel (`x()`) |
| `FD29` | `f632w` (w) | Notify | Tertiary notify |

The three pairs correspond to three vendor services (service UUIDs `FD08`/`FD18`/`FD28`, each with
an odd=notify / even=write characteristic). Primary traffic is the `FD18` service (`FD19`/`FD1A`).

### 2.2 Device Information Service (standard 0x180A) + battery

| 16-bit | Field | Meaning | Where it's used |
|---|---|---|---|
| `2A19` | `f626q`→**no**, actually `j` | **Battery Level** (notify enabled on connect) | battery % to UI |
| `2A24` | `f626q` (q) | **Model Number String** → `kd.a.f20601b` = `model_number` | OTA / firmware check |
| `2A27` | `f627r` (r) | **Hardware Revision String** → `kd.a.f20603d` = `hardware_revision` | OTA |
| `2A25` | `f628s` (s) | **Serial Number String** → `kd.a.f20604e` = **`psn`** | OTA |
| `2A28` | `f622m` (m) | **Software Revision String** (firmware version) | OTA / UI |

> On connect these three strings are cached in SharedPreferences keyed by MAC:
> `ble_cache_model_<mac>`, `ble_cache_hw_<mac>`, `ble_cache_psn_<mac>`. If present they are reused
> instead of re-reading the characteristic.

### 2.3 Other characteristics

| 16-bit | Field | Purpose |
|---|---|---|
| `2AF0` | `f623n` (n) | Custom notify (realtime/raw sensor stream — notifications enabled on connect) |
| `FF14` | `f629t` (t) | **LCT (Locket) OTA** input/notify |
| `FF15` | `f630u` (u) | **LCT (Locket) OTA** output (firmware bytes written here via `ae.n.t(byte[])`) |
| `2902` | — | CCCD (standard, for enabling notifications) |

---

## 3. Connection handshake (observed order)

From `BleManagerHandler$4` after service discovery + char mapping:

1. Enable notifications on **battery `2A19`** (callback `ae.e(n,2)`).
2. Enable notifications on **`2AF0`** (callback `ae.e(n,3)`).
3. `ae.n.p()` → enable notifications on the primary notify char (`FD19` path, char `f622m`/`FD09`).
4. Read **Model (`2A24`)**, **Hardware rev (`2A27`)**, **Serial/psn (`2A25`)** from DIS unless cached;
   store into `kd.a` (`ToTwooApplication.f12747f`) and prefs.
5. **Send time-sync**: `commandId = 0x01`, segment `type = 0x03`, value = **4 bytes big-endian** of
   `(unixSeconds + TimeZone.rawOffset/1000)` (i.e. local-time epoch). Sent via `ae.n.u()`.
6. 1.5 s later, mark connection ready (`p.t(true)`).

---

## 4. Wire format

Two layers: a **logical AppPackage** (`ad.b`), serialized into a **framed BLE payload** by
`x4.c.g()`, then (if needed) **fragmented** into 20-byte GATT writes.

### 4.1 Logical AppPackage (`ad.b`)

```
field f499a : int      index (16-bit sequence number; 0 ⇒ auto-assigned via ad.f0.a())
field f500b : byte     commandId  (category: 1,2,3,4,6 — see §6)
field f501c : boolean  isReply
field f502d : ad.a      single segment        (OR)
field f503e : List<ad.a> multiple segments
```

### 4.2 Segment / TLV (`ad.a`)  — `f491c` byte layout

```
[0] type      (1 byte)   the actual operation code (see §6)
[1] 0x00      (reserved / sub-type, always 0 on TX)
[2] len       (1 byte)   length of value
[3..3+len]    value bytes
```
(If value is null: `[type, 0x00, 0x00]`.)

### 4.3 Inner payload (output of the AppPackage serializer, before BLE framing)

`x4.c.g()` first builds `bArr2`:

```
[0] index & 0xFF           (little-endian low byte)
[1] (index >> 8) & 0xFF    (little-endian high byte)
[2] commandId              (f500b)
[3] 0x18                   (constant marker — protocol/version tag, always 24)
[4..] segment(s) concatenated   (each = type,00,len,value…)
innerLen = 4 + Σ segment.length
```

### 4.4 BLE transport framing (what is actually written to FD1A)

**Single frame** (when `innerLen ≤ 16`):

```
[0] 0xFF                 sync / start-of-frame
[1] 0x00                 fragment header (single & final)
[2] totalLen = innerLen+4
[3..3+innerLen] inner payload (§4.3)
[last] checksum = (Σ all preceding frame bytes) & 0xFF   (ad.d.b)
```

**Fragmented** (when `innerLen > 16`): split into 20-byte GATT writes, 16 payload bytes each:

```
per fragment i:
[0] 0xFF
[1] fragment header:
      continuation (not last) = (i + 0x80)     → bit7 set
      final fragment          = (i + 0xC0)     → bit7+bit6 set
[2] fragment length (0x14=20 for full chunks; (tail+4) for the last)
[3..18] up to 16 payload bytes
[19] per-fragment checksum = Σ(bytes of this fragment) & 0xFF
```

### 4.5 Decode (`x4.c.i`) — device→phone

Operates on `byte[1]` flags of the raw frame (after the `0xFF` sync):

- `b1 & 0x20` → **isReply** (`f501c=true`)
- `b1 & 0x80 (STATE_TWS_DISCONNECTED)` clear → **single/unfragmented**: payload = `bytes[3 .. len-1]`
- fragmented: `b1 & 0x40` clear → **continuation** (append to `ad.d.f517a` reassembly buffer);
  set → **final** (append, then emit)
- Reassembled inner payload is parsed:
  - `commandId = payload[2]`
  - `index = payload[0..1]` via `ad.d.c` (note: **`ad.d.c` is big-endian**; encode used LE — see §7)
  - segments from offset 4: `type=payload[i]`, `len=payload[i+2]`, `value=payload[i+3 .. i+3+len]`,
    advance `i += len + 3`.

### 4.6 Response correlation & ACK

- `ae.n` keeps `ConcurrentHashMap x` mapping **index → pending request** (`nh.o`). On RX,
  `o()` reads the 16-bit index at **offset 3** (`ByteBuffer…LITTLE_ENDIAN.getShort(3)`), removes the
  matching entry and completes the coroutine (`v()` is the suspend send-and-await with timeout).
- Unsolicited device frames are dispatched by first byte:
  - `0xC1` → **sleep-data** upload (see §5.1)
  - `0xC3` → **activity/step** upload (see §5.2)
  - otherwise → `k(x4.c.i(bytes))` generic AppPackage dispatch.
- The app replies with **ACK**: `commandId = 0x04`, segment `type = 0x01` or `0x03` echoing the
  index bytes (`ae.n.u()` at lines 584/692).

---

## 5. Device→phone bulk uploads

### 5.1 Sleep data — frame opcode `0xC1`
Parsed in `ae.n.o()`:
- `bytes[1..3]` = block counter. `0x0001` = start (clears `ad.f.f525c`), `0xFFFF` = end-of-stream.
- Payload bytes `bytes[3 .. len-1]`: each byte packs **4 × 2-bit** sleep states (one per minute),
  MSB-first: `(b&0xC0)>>6, (b&0x30)>>4, (b&0x0C)>>2, (b&0x03)`.
- States are run-length-grouped into `SleepUpdateBean(startEpoch, endEpoch, durationMin, state)`
  anchored to `now - count*60000`. Emitted via `zd.l.f29658f` (LiveData `r1`).
- App ACKs each block (`commandId 0x04`, `type 0x01`).

### 5.2 Activity / step data — frame opcode `0xC3`
- `bytes[3..5]`, `[5..7]`, `[7..8]`, `[8..9]` decoded via `ad.d.c` (big-endian) into a `z1` bean
  (`a/b/c/d` fields — steps, distance, calories, active-minutes). Emitted via `zd.l.f29657e`.
- App ACKs (`commandId 0x04`, `type 0x03`).

---

## 6. Command catalog (phone→device)

`commandId` groups a category; the **segment `type`** is the real sub-command. Confirmed builder
sites (file:line in `jadx_out/sources/`). Payload columns use the observed byte layouts.

| commandId | type | Value layout | Meaning (inferred) | Site |
|---|---|---|---|---|
| 0x01 | 0x03 | 4B BE local-epoch | **Set time** | `BleManagerHandler$4:718`, `ae.n` |
| 0x01 | 0x04 | `{0x01}` | Enable/subscribe (pair w/ 0x03 query) | `a0/l.java:104` |
| 0x01 | 0x06 | 4B BE (`x4.c.b(min)`) | **Set sedentary/idle reminder (minutes)** | `fe/b.java:61` |
| 0x01 | 0x08 | byte[] | Config blob (notification/contacts set) | `zd/h.java:395` |
| 0x01 | 0x09 | `{0x01,idx,RRGGBB}` | **Set alarm/reminder #idx (variant 1)** + color | `zd/h.java:373` |
| 0x01 | 0x09 | `{0x02,idx,RRGGBB}` | **Set alarm/reminder #idx (variant 2)** | `zd/h.java:409` |
| 0x01 | 0x0A | 2B BE | Set 16-bit parameter | `zd/h.java:402` |
| 0x01 | 0x0C | `{b}` | Single-byte setting (`u4` activity) | `com/.../u4.java:69` |
| 0x01 | 0x15 (21) | `{0/1}` | **Toggle feature on/off** | `zd/h.java:358` |
| 0x01 | 0x16 (22) | `{0x03,RR,GG,BB}` | **Set touch/tap notify colour** | `CustomTouchColorActivity:172/248` |
| 0x02 | 0x01 | `{b10,b11,RR,GG,BB}` | **Send "totwoo" / notify event (colour+type)** | `zd/h.java:555/578/601` |
| 0x02 | 0x04 | byte[] | Control blob | `zd/h.java:499` |
| 0x02 | 0x07 | `{b}` | **Trigger vibration/alert pattern** (find-device etc.) | `zd/h.java:189`, `l9/b.java:1358` |
| 0x02 | 0x0A | `{0/1}` | Enable/disable control | `zd/h.java:457` |
| 0x03 | 0x01 | null | **Query** (request state; `isReply` path) | `a0/l.java:108` |
| 0x03 | 0x04 | null | **Query** (request data) | `ae.n:751` |
| 0x04 | 0x01 | index bytes | **ACK** for device upload (sleep) | `ae.n:586/694` |
| 0x04 | 0x03 | index bytes | **ACK** for device upload (activity) | `ae.n:586` |
| 0x06 | 0x01 | `{b10,b11,p9(3B),b10,b11}` | Extended/legacy colour-send | `a0/j.java:523` |

Colours are 24-bit `RRGGBB` packed big-endian (`(p>>16)&0xFF, (p>>8)&0xFF, p&0xFF`).
`b10/b11` in the 0x02/0x01 and 0x06 builders are notify-type / sub-mode selector bytes derived
from the calling feature (emoji id, flash pattern). To fully label these, read the owning methods
in `zd/h.java` and `a0/j.java`.

---

## 7. Gotchas for reimplementation

- **Mixed endianness**: the **packet index** is little-endian in the frame header (`x4.c.g` bytes
  0–1) and is read little-endian on RX (`ByteBuffer…LITTLE_ENDIAN.getShort(3)`), **but** segment
  multi-byte *values* use **big-endian** (`ad.d.c` and `x4.c.b`). The `index` re-parse in
  `x4.c.i` via `ad.d.c` (BE) is effectively only used for logging; trust the LE read at offset 3.
- **`0x18` marker** (payload[3]) is constant on TX. Validate but don't vary it.
- **Checksum** is a plain 8-bit additive sum (not CRC, not XOR). Per-fragment for multi-frame.
- **Frame sync** byte is always `0xFF`; fragment header bit7=fragmented, bit6=final, bit5=reply.
- **MTU/chunking**: fragments are hard-coded to 16 payload bytes / 20-byte writes — the app does not
  rely on a negotiated MTU for the command channel.
- The reassembly buffer `ad.d.f517a` is a **static** field (shared) — a single connection at a time
  is assumed.
