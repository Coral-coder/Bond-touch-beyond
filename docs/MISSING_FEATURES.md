# What the original Bond Touch app has that Bond Touch Beyond doesn't

Audited from the decompiled original Android app (jadx), checked against `docs/FEATURES.md`
and our Swift code (October 2026). Sizes: S = small, M = medium, L = large.

## Done since this audit (not yet tested on a device)

- All of section 0: v2/v4/mini playback frames, v1 characteristic, taps/double-tap,
  v2-base paired reply and handshake order, Private Space double-tap unlock and 72 h
  expiry, favourite flag kept, vibration + colour sent to the bracelet, meaning play button.
- Bracelet: settings re-sent after every pairing; vibration Low/Medium/High/Strong +
  fine-tune + balance (Bond Touch More) with live preview; user colour with live preview;
  device card (battery, charging, firmware, model, battery-alert lights); partner slot
  chosen on the bracelet selects it in the app and vice versa (v3 event 180, v4 0x37).
- Touch delivery from every partner in its slot, up to 15 min old.
- Library: replay on own bracelet, delete confirmation.
- Heartbeat as an EKG (bracelet light, screen, beep), in history; location sharing on by
  default and kept across reinstalls.
- Home-screen widget (§2): partner name + photo and up to 10 meanings (favourites first)
  with their touch drawn, in small / medium / large; on iOS 17 a tap sends in the background
  and shows Sent / Failed for 5 s, on iOS 16 it opens the app, which sends it
  (`Widget/`, `Sources/Shared/`, `AppModel+Widget.swift`; App Group `group.<bundle id>`).
  No promo screen.

## 0. Broken — we claim or attempt it, but it doesn't work (fix first)

| Issue | Detail | Size |
|---|---|---|
| v2/v4/mini touch playback mis-built | Original 0x33 frame is `[0x33,0,strength,80,80,80,RGB1,RGB2,RGB3,ms LE16]`, one frame per 200 ms step with gradient + zero-colour frames for gaps, `[0x32,0,0x22]` sent only *after* the frames; single colour uses queued 0x26 frames then `[0x32,0,0x11]`. Ours shifts everything by a byte and adds an opening 0x32 — rhythm likely never plays. (BLE_PROTOCOL.md §1.3 has the same error.) | S |
| v1 commands to the wrong characteristic | We write `d3c0ff06`; original writes to `d3c0ffa6`. | S |
| v2-base taps sent as touches | Single tap (0x16) and double-tap (0x17) become outgoing touches; the original only logs a tap and treats double-tap as an action (Private Space unlock). | S |
| v2-base paired signal unanswered | Original answers event 0x13 with `[0x31,0,0x11,0x22,0x33,0x44]`. | S |
| v2-base marked connected too early | Before the token/AUID handshake and firmware read; busy states 0x86/0x88 (pause queue 15 s) and setup mode 0x84 ignored. | S |
| Private Space "double-tap to unlock" | The screen says it, nothing handles the double-tap (v2-base 0x17, v3 event 178). | S |
| Private Space "kept 72 h" | Nothing deletes old messages. | S |
| Favourite flag wiped | Our meaning updates always send `favourite:false`, clearing the partner's favourite. | S |
| Vibration slider / colour picker | Saved locally, never sent to the bracelet. | S |
| Meaning "play" button in the library | Does nothing. | S |

## 1. Bracelet

| Feature | Original behaviour | Size |
|---|---|---|
| Settings pushed after pairing | User colour (f), vibration (B/F), partner menu (A), saved selected slot (s); v2-base also low-battery alert 10 % red blink, min touch 50 ms, ANCS off | M |
| Vibration strength + balance | Low/Medium/High/Strong (+fine-tune) with live preview; v2-base motor-strength setting, v3 `[1,0x48,2,level,balance,3]`, levels 28–100, balance 0–4; saved on the server user record | S |
| User colour on the bracelet | Written + live preview (v3 `[1,0x4B,0,0,R,G,B]`) | S |
| Device screen | Battery + charging (v2-base ff06 byte 0, ffa4 byte 1), firmware (2A26), model (2A24), battery-alert lights guide | M |
| Firmware updates (OTA) | Compare to latest (v1 1.2.96, v2 2.7.9, v3 3.1.1, v4 2.0.3, mini 1.2.0), prompt, enter update mode, Nordic DFU. We only rescue bracelets already stuck in DFU | L |
| Touch delivery rules | Plays touches from *every* bond (each in its slot), up to 15 min old; missed-touch notification when offline. Ours: selected partner only, 120 s | M |
| Bracelet notifications | General (special vibration) / Secret (rainbow), max one per 30 s | M |
| Do-not-disturb schedule | From/To (default 22:00–07:00); suppressed touches marked "not played" | S |
| Partner menu on v4/mini, slot selection from the bracelet | v4 `UserMenu(color, slot|0x80)`, selected user 0x37; v3 event 180; saved + restored | M |
| v3 battery-alert settings | Read `[1,0x49,1]` answer (thresholds + colours) | S |
| Low-battery phone alert | Notification + battery in the foreground notification | S |
| Setup/pairing prompts | Setup mode → "double-tap the flashing bracelet"; "too many bracelets", "pairing failed" | M |
| Lights tutorials, arrival animation, diagnostics reads | Wake-up / select-partner / preview lessons; breathing pulse; lot no., device id, health/flash stats | M–L |

## 2. Touches, meanings, home, widgets

| Feature | Original behaviour | Size |
|---|---|---|
| Home-screen widget | Partner + up to 10 meaning slots with pattern images and photo; tap sends in background with Sent/Failed; promo screen | L |
| Delivery status | Sending / Sent / Seen / Failed, auto-resend on start | M |
| Missed touches | Flagged in the feed + "you might have received new touches" | S |
| Edit meaning name / colour | API exists in our code, no UI | S |
| Favourites | Toggle per meaning | S |
| Recommended meaning names | `GET meanings/recommendations` | M |
| Create-meaning flow | Pick from past touches, 20-char name, duplicate check, bracelet-palette colours, "Skip to meaning" | M |
| Library actions | Per-meaning send status, replay on own bracelet, delete confirmation | S |
| Dashboard message presets | "Hey look it's us", "In touch with ourselves", "We're just a touch away", "You complete me", "Better together" | S |
| Encounter animations | CountdownStart/Countdown/Everyday/Today/CountdownEnd; auto messages | M |
| History summary | "Last sent / received", 2-day empty state | S |
| Coach marks, Touch Language tutorial, weather icon on partner | | S each |

Meaning recognition in the original is server-side and exact (server returns the matched
meaning id on send; received touches carry it; new meanings retro-tag identical patterns).
Ours additionally matches close touches locally (by request).

## 3. Partners, chat, Private Space, presence, account

| Feature | Original behaviour | Size |
|---|---|---|
| Chat inside Private Space | Behind passcode/biometrics, screenshots blocked | M |
| Shared gallery | 24 h / 72 h countdowns, bookmark up to 10, delete for both, retry | L |
| Secret photos | Heart icon, press-and-hold, unlocked by bracelet, 24 h | L |
| Read receipts, typing, delivery ticks, screenshot alert | | M |
| Private Space settings | Change/reset passcode (email, `pincode/*`), unlock toggles, General/Secret notifications | M |
| Map extras | Weather, Street View (+full screen), city & local time, "updated X ago", centre buttons, pause sharing, banners | M |
| Saved places + arrival alerts | Partner feels a touch when you arrive (Presence+) | L |
| Presence+ live location | Real-time stream, mutual opt-in, per-partner (paid) | L |
| Phone notifications | Touch missed, chat, invites, bond/unbond, encounter set/changed, low battery, failed send | M |
| Push from the original backend | Register device token; handle TOUCH_SYNC, BOND_SYNC, BOND_INVITE, CHAT_*, USER_DETAILS_SYNC, PRESENCE_ARRIVAL, … | M |
| Share our battery/chat info | `PUT user/details/battery`, `/chatinfo` every 6 h | S |
| Account | Delete account (`DELETE v3/user` + Heart), Google/Apple sign-in, 6-digit email code, full profile setup (photo, vibration, placement), age gate + parental consent, camera profile photo, 25-char username rule, logout wipe | M |
| Partners | Icon picker (9 icons, encounter countdown), invite with colour/icon + bracelet preview, 3-partner limit, decline endpoint | S |
| Help & support / legal | Help centre, feedback, report a problem with logs, privacy, terms | S |
| Smaller | App-rating prompt, forced update, chat history restore, temperature unit | S |
| Encrypted chat with original-app partners | Blocked: their servers only let the official app use photo/key storage | – |

## 4. Watch

Original Wear app is standalone (receives touches with haptics, replay, favourites, swipe
between people, works without the phone, paid "Bond Touch Lite"). Ours only sends, via
the phone.

## 5. Bond Heart (separate pendant product)

Whole second mode: record a heartbeat with the camera, customise (colour/name/memory),
heartbeat library, wear on the pendant, share/request by email, received/waiting screens,
hold counter (share with 3 people / 24 h), pendant pairing, settings, DFU, tutorials,
`heart/api/v2` endpoints. Protocol documented in BLE_PROTOCOL.md §2. None of it built.

## Paid in the original

Presence+ (live location, places, arrival alerts; monthly/lifetime, 7-day trial) and
Bond Touch Lite (watch app).
