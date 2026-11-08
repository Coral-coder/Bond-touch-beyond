# The Bond Touch cloud integration (removed)

Until this change, Bond Touch Beyond could also talk to **Bond Touch's own servers**, the
ones the official Bond Touch app uses. It could sign in to a Bond Touch account, sync
partners who were still on the original app, and send touches to them. All of that code is
now gone from the app. This document describes, from the code itself, exactly what it did.
Use it to understand the old behaviour or to bring it back.

The app now runs on the owner's own infrastructure only:

- **iCloud / CloudKit** (`Sources/Cloud/CloudRelay.swift`). It carries partners, touches,
  chat, profiles, presence and Touch Language.
- The owner's **own Firebase project** (`Sources/Cloud/FirebaseStore.swift`), configured by
  the `GOOGLE_SERVICE_INFO_PLIST` secret, for Android pairing. It also calls
  `identitytoolkit.googleapis.com` and `securetoken.googleapis.com`, but with the owner's own
  project and key. It has nothing to do with Bond's project.
- **APNs** (`Sources/Cloud/APNsClient.swift`), weather, and Bluetooth to the bracelet and
  the pendant.

Everything below is about the removed side. Endpoint lists of the original Android app
that this app never called are in [DATA_MODEL.md](DATA_MODEL.md). The original app's chat
protocol is described byte by byte in [CHAT_PROTOCOL.md](CHAT_PROTOCOL.md).

> **Secrets.** Bond's Firebase Web API key and related identifiers were hard-coded in
> `Sources/Legacy/BondBackend.swift` (`BondBackend.apiKey`, `senderId`). The Debug panel also
> showed them. This document never repeats their values. The verbatim archive copy of that
> file (`archive/bond-touch-cloud/Sources/Legacy/BondBackend.swift`) still contains them, as
> does git history.

---

## 1. Where the code is now

| What | Where |
|---|---|
| The full working app, with the integration | branch **`bond-cloud-final`** (and the local tag of the same name), at commit `b39e283` (`origin/main` before this change) |
| Every file removed outright, verbatim, at its original relative path | `archive/bond-touch-cloud/` |
| Code removed from files that stay | `archive/bond-touch-cloud/removed-hunks.patch` |
| How to restore it | `archive/bond-touch-cloud/README.md` and §12 below |

`archive/` is not in any `sources:` list of `project.yml` or `uitests.yml`, so none of it
compiles into the app.

---

## 2. Hosts

| Host | Used for | File |
|---|---|---|
| `identitytoolkit.googleapis.com` (`/v1/accounts:*`, Bond's key) | Firebase Auth for Bond's project `bond-touch`: email-link sign-in, anonymous sign-up, custom token | `BondBackend.swift` |
| `securetoken.googleapis.com` (`/v1/token`, Bond's key) | Refreshing the Firebase ID token | `BondAPI.swift` |
| `api.bond-touch.com` | The Bond REST API (`bond/api/v3`, `bond/api/v4`), the Heart API (`heart/api/v2`) and the Signal key directory | `BondBackend.swift`, `BondAPI.swift`, `HeartAPI.swift`, `BondChat.swift` |
| `firebasestorage.googleapis.com` (buckets `bond-touch.appspot.com`, `bond-touch-galleries`) | Profile photos, heart memory photos, Signal public keys, chat photos | `FirebaseStorage.swift` |
| `bond-touch.firebaseapp.com` | Only the `continueUrl` of the sign-in email; the app never requested it | `BondBackend.swift` |
| `bond-touch.firebaseio.com` | Declared as `BondBackend.rtdbURL` and shown in Debug. Never requested by the sync. A separate client, `LegacyFirebaseClient`, could reach *any* Realtime Database URL the user typed in (§9). | `BondBackend.swift`, `LegacyFirebaseClient.swift` |

Other constants in `BondBackend` were `projectId = "bond-touch"`, `storageBucket =
"bond-touch.appspot.com"` and `iosBundleId = "com.impossible.bondtouch"` (the official iOS
app's bundle ID). There was also the GCM sender ID; its value is not repeated here.

---

## 3. Authentication

### 3.1 Identity Toolkit calls (`BondBackend.identity`)

- `POST https://identitytoolkit.googleapis.com/v1/<method>?key=<Bond API key>`
- Headers: `Content-Type: application/json` and
  **`X-Ios-Bundle-Identifier: com.impossible.bondtouch`**. Bond's key is restricted to the
  official iOS app, and this header made the request look like it came from that app.
- Errors: when the status is 400 or higher, the message is `error.message` from the JSON
  (for example `INVALID_OOB_CODE`). Otherwise it is `"Auth failed (<status>)"`.
- `Session` = `{idToken, refreshToken, uid}`. It was read from `idToken`, `refreshToken`
  and `localId` (or `user_id`).

| Method | Body | Used by |
|---|---|---|
| `accounts:sendOobCode` | `{requestType: "EMAIL_SIGNIN", email, continueUrl: "https://bond-touch.firebaseapp.com/", canHandleCodeInApp: true}` | Sign-in step 1 |
| `accounts:signInWithEmailLink` | `{email, oobCode}` | Sign-in step 2 |
| `accounts:signUp` | `{returnSecureToken: true}` | `anonymousSignIn()`, never called |
| `accounts:signInWithCustomToken` | `{token, returnSecureToken: true}` | `signIn(customToken:)`, never called |

### 3.2 The sign-in flow the user saw

This was the Firebase Email Link flow of the official iOS app, recovered from its IPA (see
[IOS_STRUCTURE.md](IOS_STRUCTURE.md)). The screen was `LegacyLoginView`, opened from
Debug → "Sign in to a Bond Touch account".

1. The user entered their Bond Touch email. The app called `beginEmailLogin`, which is
   `sendOobCode`, and Firebase emailed a link.
2. The user pasted the link back. The "Sign in" button stayed disabled until the text
   contained `oobCode`. `BondBackend.oobCode(fromLink:)` took the `oobCode` query item. For
   a Dynamic Link, it first unwrapped the URL in the `link=` query item.
3. The app called `signInWithEmailLink`.
4. It called `GET bond/api/v3/user` to read the account's `email`, falling back to the
   typed one.
5. It stored the following in `UserDefaults` (plain text, not the Keychain):
   `fbToken` = ID token, `legacyRefresh` = refresh token, `legacyEmail` = email, and
   `fbEnabled` = true. Then it called `model.startLegacySync()`.

Log out cleared those keys and called `AppModel.resetLegacy()`, which stopped sync and
dropped every original-app partner, invite and meaning. It also cleared the
`LegacySeenTouchIDs` set and reset the Signal store.

Unused alternatives in `BondBackend` were `requestPin` (`POST bond/api/v3/auth/request-pin
{email}`) and `validatePin` (`POST bond/api/v3/auth/validate-pin {email, firebaseId, pin}`
→ `{token}`, a custom token). That was the Android app's 6-digit-code flow. Neither was
wired to any UI.

### 3.3 Token refresh (`BondAPI.refreshSession`, `AppModel.legacyToken`)

- `POST https://securetoken.googleapis.com/v1/token?key=<Bond API key>`, with
  `Content-Type: application/x-www-form-urlencoded`, `X-Ios-Bundle-Identifier` and the body
  `grant_type=refresh_token&refresh_token=<token>`.
- Response: `id_token`, `refresh_token`, `user_id`.
- `legacyToken()` was called before every Bond request. It decoded the JWT `exp` claim
  (`tokenExpiry`, base64url-decoding the payload). If more than **300 s** remained, it
  reused the token. Otherwise it refreshed and saved both tokens. With no refresh token
  stored, it used the old token anyway.
- `tokenUID(jwt)` read `user_id` (or `sub`) from the token. That is the Firebase UID, used
  for Storage paths.

### 3.4 Bond API requests (`BondBackend.bond`)

- `https://api.bond-touch.com/<path>`. The default method is `POST`.
- Headers: `Authorization: Bearer <Firebase ID token>` and `Content-Type: application/json`.
- A status of 400 or higher threw `"HTTP <code> at /<path>: <body>"`.
- Paths containing `/touches` were also written to `NetLog`, the Debug panel's touch log
  ("Touch → Bond API …").
- `BondAPI.call` parsed responses leniently with `JSONSerialization`. An empty body became
  `nil`.

---

## 4. The Bond REST API, as the app used it

The facts here come from the code's comments, which cite the decompiled Android app
v11.2.0's Retrofit interface. Colours on this API are **Android ARGB signed 32-bit ints**:
`rgb(fromAndroid:)` masked them with `& 0xFFFFFF`, and `androidColor(fromRGB:)` sent
`Int32(bitPattern: 0xFF000000 | rgb)`. The touch `generation` is the string `"2"` or `"3"`.
On reading, anything that isn't 3 counts as 2.

### 4.1 Bonds

| Call | Request | Response / meaning |
|---|---|---|
| `GET bond/api/v4/bonds` | – | `{bonds: [Bond]}` (below) |
| `GET bond/api/v3/bonds/details` | – | `[{bondId, sharing: Bool, location: {lat, lng}, battery}]` |
| `POST bond/api/v4/bonds` | `{email}` | Invite an original-app user by account email |
| `POST bond/api/v4/bonds/{id}/accept` | – | Accept a received invite |
| `DELETE bond/api/v3/bonds/{id}` | – | Unbond, cancel a sent invite, or decline a received one |
| `PUT bond/api/v3/bonds/{id}/settings` | `{color: ARGB, icon}` | Your colour for that partner. The `icon` from the last sync was sent back unchanged |
| `PUT bond/api/v3/bonds/{id}/message` | `{message}` | The home greeting ("dashboard message") |
| `PUT bond/api/v3/bonds/{id}/encounter` | `{timestamp}` | Next encounter in **Unix seconds**. `0` clears it |

The fields of a **Bond** object that the app read:

- `bondId`: the partner's ID on Bond's side. It became `Bond.id`.
- `status`: one of `REQUESTED` (an invite you sent), `RECEIVED` (an invite to you),
  `BONDED`, or `NONE`. The app skipped `NONE` and anything else.
- `email`, `firebaseId` (the partner's Firebase UID), `phoneNumber`. The phone number was a
  legacy folder name in Storage.
- `profile`: `{name, color, hasImage, version}`.
- `settings`: `{color, icon}`. This is *your* colour for them.
- `touches`: `[{id, meaning, message: {timestamp (ms), pattern, generation}}]`. These are
  received touches that haven't been acknowledged. `meaning` is the ID of the saved meaning
  the server matched, as a string or a number.
- `meanings`: `[MeaningDto]` (§4.3).
- `dashboardMessage`: the greeting.
- `encounterDateTimestamp`: Unix seconds. Earlier builds of this app wrote milliseconds, so
  a value above 1e11 was read as milliseconds and rewritten in seconds.

### 4.2 Touches

| Call | Request | Response |
|---|---|---|
| `POST bond/api/v3/bonds/{bondId}/touches` | `{timestamp: ms, pattern: [Int], generation: "2"/"3"}` | `{id, meaning}`, where `meaning` is the ID of the saved meaning the server matched, if any |
| `POST bond/api/v3/bonds/{bondId}/touches/basic` | `{timestamp: ms, meaningId}` | `{id}`. Sends a saved meaning by its ID, so the partner's app plays it as that meaning |
| `PUT bond/api/v3/bonds/{bondId}/touches/{id}/acknowledge` | – | Marks a received touch delivered |

There are two pattern formats ([BTM_TOUCH_FORMAT.md](BTM_TOUCH_FORMAT.md)):

- Generation 2 is on/off milliseconds. An empty pattern was sent as `[200]`.
- Generation 3 is 50 ms position samples (Bond Touch More bar), trimmed by
  `TouchPattern.trimmed` to at most 200 samples.

### 4.3 Touch Language (meanings)

| Call | Body |
|---|---|
| `POST bond/api/v3/bonds/{bondId}/meanings` → `{id}` | `MeaningDto` body |
| `PUT bond/api/v3/bonds/{bondId}/meanings/{meaningId}` | `MeaningDto` body |
| `DELETE bond/api/v3/bonds/{bondId}/meanings/{meaningId}` | – |

The body was `{name, pattern, startColor: ARGB, endColor: ARGB, generation: "2"/"3",
favourite: Bool}`. `favourite` was sent back as it came from the server, because always
sending `false` had wiped the partner's star. When read, the server's `id` became
`TouchMeaning.serverID`, and `isNew` was read too. Defaults: label `"Touch"`, colour
`0xFF2E74`, end colour = start colour.

### 4.4 User, presence, location, profile

| Call | Request | Response |
|---|---|---|
| `GET bond/api/v3/user` | – | The user object (`email`, `profile {name, color, version, hasImage}`, `bypassFlags`, …) |
| `PUT bond/api/v3/user` | The same object, with `profile.name` / `profile.color` / `profile.hasImage` changed, `profile.version` + 1 and `bypassFlags` removed | – |
| `PUT bond/api/v3/user/status` | `{online: Bool}` | `{partners: [{bondId, online}]}`. This is how partner presence was learned |
| `PUT bond/api/v3/user/details/location` | `{lat, lng, timezone}` (IANA identifier) | – |
| `PUT bond/api/v3/user/details/sharing` | `{sharing: Bool}` | – |

The Debug-only data dump (`dumpAccount`, `dumpAccountStructured`, `rawGet`, `putRaw`) also
read these paths:

- `bond/api/v3/user/details`, `…/user/consent` and `…/meanings/recommendations`.
- `bond/api/v3/bonds/chat`.
- For each bond, `…/bonds/{id}/meanings`, `…/bonds/{id}/chatmessages`,
  `…/presences/{id}` and `…/presences/{id}/places`.

`bond/api/v3/user` and `…/user/details` could be edited and saved back with `PUT`. The dump
could be exported as `BondTouch-database-<ISO date>.json`, shaped
`{exportedAt, source, endpoints: {"/path": {status, body}}}`.

**Push tokens.** No push token was ever sent to Bond's servers. The original app is woken
by FCM pushes addressed to its own app ID, which this app cannot receive, so the code
polled instead (§6). Bond Touch Beyond's own APNs tokens only ever went to iCloud partners.

---

## 5. Bond Heart cloud API (`HeartAPI.swift`)

Paths are on `https://api.bond-touch.com/heart/api/v2/` and use the same bearer token. The
JSON keys are the Android app's Kotlin property names (Gson). Colours are sent as
`color & 0xFFFFFF`. `createdDate` is epoch **milliseconds**. On reading, a value of 1e11 or
less is taken as seconds.

| Call | Body | Response |
|---|---|---|
| `GET user/heartbeats` | – | `{heartbeats: [HeartbeatItemDto], pendingHeartbeats: [PendingHeartbeatItemDto]}` |
| `POST user/heartbeats` | `{pattern: [ms intervals], name, color, isSelf: false, createdDate, hasMemory, emails}` | Item. Its `id` became `SavedHeartbeat.serverID` |
| `PUT user/heartbeats/{id}` | `{name, color, hasMemory, emails}` | Item (edit) |
| `PUT user/heartbeats/{id}` | (no body) | Item. Accepts a pending heartbeat |
| `DELETE user/heartbeats/{id}` | – | Deletes one, or rejects a pending one. A 404 counted as done |
| `PUT heartbeats/{id}/requests` | `{toUserEmail (lower-cased), message, notify: true}` | Shares a heartbeat by email |
| `GET requests` | – | `[{id, fromUser, fromUserName, toUser, createdDate}]` |
| `POST requests` | `{fromUserName, toUser}` | Asks someone for their heartbeat |
| `DELETE requests/{id}` | – | – |
| `POST user/heartbeats/{id}/count` | `{name, count, sinceDate: "yyyy-MM-dd", controlTimestamp}` | `{controlTimestamp}` |
| `POST user/heartbeats/{id}/total_count` | `{count, name}` | – (defined, never called) |

The fields read:

- `HeartbeatItemDto`: `{id, name, color, pattern, createdDate, createdBy, hasMemory, isSelf,
  emails}`.
- `PendingHeartbeatItemDto`: `{id, name, color, createdBy, createdDate, message, pattern}`.

How the app used it (`AppModel+BondHeart.swift`):

- **`heartSync()`** ran when Bond Heart or "Shared & requests" opened, after a delete, and
  on pull to refresh. It went through these steps in order:
  1. Pushed queued deletions (`HeartLibrary.deletedServerIDs`).
  2. Uploaded edited heartbeats already on the account (`serverID != nil && dirty`). New
     recordings stayed on the phone until they were shared.
  3. Pulled the library and merged it by `serverID`. Local edits won while `dirty`. New
     items became `SavedHeartbeat` with `source` `.server` (own) or `.received`.
  4. Stored `pending` and `requests` in `HeartLibrary`. They lived in memory only.
- **Memory photos** went to Firebase Storage at `memories/<uid>/<serverID>` (JPEG). On
  download, the owner was taken to be `createdBy`, presumably the Firebase UID; the code
  itself calls that a guess. `hasMemory` was set only if the upload worked, and App Check
  normally blocked it (§7).
- **Share by email** (`HeartShareSheet`) uploaded the heartbeat if needed, then called
  `heartbeats/{id}/requests`.
- **Ask for a heartbeat** called `POST requests`. A request counted as "received" when
  `toUser` equalled the signed-in account email.
- **Answering a request** shared the chosen heartbeat with `fromUser`, then deleted the
  request.
- **Share count**: at most once every 24 h (`lastCountShare`), and only with `emails` set
  and a count above 0. It uploaded first if needed. The count is the pendant's played
  counter minus the reading when the heartbeat was worn, which is local Bluetooth and
  stays in the app. `controlTimestamp` was stored and sent back each time.

---

## 6. The sync loop and how original-app partners were modelled

### 6.1 Model

- `Bond.legacy: Bool` was `true` for a partner on Bond's servers. For those, `Bond.id` was
  Bond's `bondId`; for iCloud bonds it is a CloudKit zone code. `Bond` was never `Codable`,
  so this flag was never saved. Original-app partners were rebuilt from the server on every
  sync.
- `AppModel` state:
  - `legacyPartners` (`BONDED`), `legacyPending` (`REQUESTED`), `incomingInvites`
    (`RECEIVED`).
  - `legacyMeanings[bondId]`, `legacyPartnerIcons[bondId]`,
    `legacyPartnerAccounts[bondId] = (uid: firebaseId, phone)`.
  - `legacyStatus`, `legacyLastSync`, `legacyTask`, `legacyCycle`, `legacyPrimed`,
    `legacyLastLocationPush`, `legacyProfileTask`.
- `LocalStore` (`UserDefaults`) held `fbEnabled`, `fbURL`, `fbToken`, `legacyEmail`,
  `legacyRefresh`, `legacyChat` and `chatLinks` (a JSON map from original-app bondId to the
  iCloud bond ID).
- Other `UserDefaults` keys were `LegacySeenTouchIDs` (the last 2000 received touch IDs)
  and `ImportedLegacyMeanings`.

### 6.2 `startLegacySync()` / `legacySyncOnce()` (`AppModel+Legacy.swift`)

It started at bootstrap, before iCloud and independently of it, and again whenever the app
came to the foreground. It stopped in the background unless the app was being kept alive.

```
setOnline(true)
loop:
  token = legacyToken()                 (refresh if < 5 min left)
  bonds = GET bond/api/v4/bonds
  apply(bonds)
  cycle += 1
  if cycle % 4 == 1  → GET bonds/details   (location, phone battery)
  if cycle % 8 == 1  → PUT user/status {online: true}
  if cycle == 1      → load own photo; update keep-alive
  sleep 4 s (foreground) / 15 s (kept alive in background)
```

`apply(bonds)` worked like this for each bond:

- The partner's name was `profile.name`, else `email`, else `"Partner"`.
- The colour was `settings.color`, else `profile.color`, else `0xFF4081`.
- If `profile.hasImage`, the app loaded `images/<firebaseId>/profile` from Storage, once per
  `profile.version` (§7).
- Presence and location from the slower refreshes were kept.
- **Migrated partners** (§6.4) contributed only their entry in the partner list. Their
  touches, meanings, greeting and encounter on Bond's side were ignored.
- The greeting was copied from `dashboardMessage` and the encounter from
  `encounterDateTimestamp`. Encounters in milliseconds were repaired.
- **Received touches**: each `touches[]` ID not in `LegacySeenTouchIDs` became a
  `TouchMessage`. Its ID was `TouchMessage.stableID(from: touchId)`, and its colour came
  from the matched meaning, else the partner's colour. It was recorded and played on the
  bracelet (`deliver`) and then acknowledged (`PUT …/acknowledge`). **On the first sync
  after sign-in** touches were only recorded, not played, so old ones didn't buzz.
- At the end of `apply`, the app called `autoLinkPartners()` and fixed the selected
  partner.

`legacyRefreshDetails`:

- With `sharing == true`, the partner's coordinates were taken from `location.lat` and
  `location.lng`. Otherwise they were cleared.
- `battery` became the partner's phone battery. A value above 1 was read as a percent.

`legacySetOnline(online)` was sent on foreground, in the background without keep-alive, and
every 8 cycles. Its response set each partner's `online`, and `lastSeen` when it flipped
from online to offline.

The location, sharing and profile calls below ran only while `hasOriginalOnlyPartners` was
true, that is, while at least one original-app partner was not yet on iCloud:

- **Location**: `legacyPushLocation`, at most every 30 s in the foreground and every 120 s
  in the background. `legacySetSharing` was sent when the user toggled location sharing.
- **Profile**: `legacyPublishProfile` sent the name and colour, debounced by 1 s, through
  `GET` then `PUT bond/api/v3/user`.

### 6.3 Sending

`AppModel.transmit` for a `legacy` bond:

- If the touch matched a saved meaning that had a `serverID`, the app called
  `POST …/touches/basic {meaningId}`.
- Otherwise it called `POST …/touches` with the raw pattern. The returned `meaning` ID was
  mapped back to a saved meaning to label the touch in history.
- **Heartbeats** went as generation 2 `EKG.onOff(bpm:)`, one press per beat, because the
  original app only knows touches. iCloud partners get the generation 3 EKG instead.
- **Kisses** to original-app partners were refused ("Kisses go to partners on iCloud.").
- **Us / Together**, the **poly calendar** and **CarPlay** partner lists filtered
  original-app partners out.
- **Touch Language edits** for an original-app partner went to the meanings endpoints
  (§4.3). The greeting, encounter and partner colour went to `message`, `encounter` and
  `settings`.
- **Unbond, cancel and decline** called `DELETE bond/api/v3/bonds/{id}`.
- **Invites by email**: the pairing screen had a "Partner on the original Bond Touch app?"
  form that called `POST bond/api/v4/bonds`. "My people" listed received invites with
  Accept (`/accept`) and Decline (`DELETE`).
- **Widget**: `sendFromWidget` ran one `legacySyncOnce()` first when the bond was not known
  yet. Widget meaning IDs used `serverID` when there was one, because the local UUID changed
  on every sync. That is why `TouchMeaning.serverID` is still decoded.

### 6.4 Merging with iCloud partners

An original-app partner could move to iCloud without losing anything:

- **Linking**: `store.chatLinks[legacyID] = iCloudBondID`.
  - `inviteToICloudChat(legacyID)` created an iCloud invite (`createBond(forExistingPartner:
    true)`, which skips the partner limit), linked it, and showed the invite link. It first
    replaced an earlier unaccepted invite. This was the "Invite *name* to iCloud" button on
    the partner page and the chat screen.
  - `linkChat` linked an iCloud partner the user already had.
  - `autoLinkPartners()` (after every sync and every `refreshAll`) linked an original-app
    partner to the one iCloud partner with exactly the same name, ignoring case and
    surrounding spaces, when there was exactly one.
- **Migrated** = linked to an *accepted* iCloud bond (`migratedLegacyIDs`). After that, the
  partner showed only through the iCloud bond (`AppModel.partners` filtered them out), the
  selection moved to the iCloud bond, and Bond-side sync for them was ignored.
- **Touch Language import**: once per migrated partner (`ImportedLegacyMeanings`), the
  meanings from Bond's server were copied into the library shared with the iCloud partner.
  Labels already there were skipped, `serverID` was cleared and `updatedAt` was set to now.
- **Chat** for an original-app partner always ran through the linked iCloud bond
  (`chatBondID(for:)`). Without a link, the chat screen showed the invite and link card.
- **Background keep-alive** (`needsBackgroundKeepAlive`) also turned on for original-app
  partners, because Bond never pushes to this app. It polled every 15 s in the background
  instead.

---

## 7. Firebase Storage (`FirebaseStorage.swift`)

- Download: `GET https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<object>?alt=media`.
- Upload: `POST https://firebasestorage.googleapis.com/v0/b/<bucket>/o?uploadType=media&name=<path>`,
  with `Content-Type` set to the file type.
- Auth: `Authorization: Firebase <ID token>`, which is the SDK's scheme. The object name is
  one path segment, so every `/` is percent-encoded on download.
- A 404 meant `NotFound`. A 401 or 403 whose body mentions "App Check" set
  `FirebaseStorage.appCheckBlocked = true` and threw `AppCheckBlocked`.
- **Quirk: Bond's project enforces Firebase App Check (Apple App Attest) on Storage**, so
  in practice only the official app can read or write it. Once a block was seen, the app
  stopped trying: photo loads were skipped. Settings showed "Bond Touch's servers won't hand
  your photo to any app but theirs …", and Debug showed the block.

| Object | Bucket | Use |
|---|---|---|
| `images/<uid>/profile` | `bond-touch.appspot.com` | Profile photos (yours and partners'). After uploading, the app set `profile.hasImage` and bumped `profile.version` with `PUT bond/api/v3/user`; it did this only when the upload succeeded |
| `memories/<uid>/<heartbeatId>` | `bond-touch.appspot.com` | Heart memory photo |
| `crypto/<uid>/<name>` (fallback `crypto/<phone>/<name>`) | `bond-touch.appspot.com` | Signal public keys (§8) |
| `shared_gallery/<uid>/<file>`, `secret_gallery/<uid>/<file>` | `bond-touch-galleries` | Encrypted chat photos (§8) |

---

## 8. The Signal chat with the original app (`BondChat.swift`, `SignalStore.swift`)

**Status before removal: built but disabled.** The comment in `AppModel+Chat.swift` says it
"can't be used: its key exchange and photos live in Firebase Storage, which only the
official app may access (App Check)". The only live call was `resetLegacyChat()`, which
cleared `legacyChatEnabled` and reset the store. The app's iCloud chat never used Signal,
which is why LibSignalClient could be dropped entirely. The full wire format of the
original app is in [CHAT_PROTOCOL.md](CHAT_PROTOCOL.md). This section covers what this
app's implementation did.

**Library.** Signal's LibSignalClient **v0.86.5** (AGPL-3.0). The Swift sources were
vendored in `ThirdParty/LibSignalClient`, which is now under
`archive/bond-touch-cloud/ThirdParty/LibSignalClient`. The Rust core `libsignal_ffi.a` came
from `https://build-artifacts.signal.org/libraries/libsignal-client-ios-build-v0.86.5.tar.gz`,
SHA-256 pinned in `scripts/fetch-libsignal-ffi.sh` (now in the archive). It was never
committed. It was linked as `-lsignal_ffi -lz`, with the `SignalFfi` module on
`SWIFT_INCLUDE_PATHS` / `HEADER_SEARCH_PATHS` and per-SDK `LIBRARY_SEARCH_PATHS`.

**Key storage** (`SignalStore`). This is one JSON file,
`Application Support/signal-store.json`, written atomically with `.completeFileProtection`
under an `NSLock`. It implements the identity, pre-key, signed pre-key, Kyber pre-key and
session stores. State:

- `identity`, `registrationId`, `ownerUID`.
- `signedPreKeyId`, `preKeyLastId`, `kyberPreKeyLastId`.
- `preKeys`, `signedPreKeys`, `kyberPreKeys`, `lastResortKyberIds`.
- `partnerIdentities` and `sessions` (both keyed by bondId).
- `kyberBaseKeysSeen`, `published`, `preKeyLastCheck`.

Trust policy (taken from the original's `PrivateSpaceIdentityKeyStore`):

- Receiving is always trusted.
- When sending, a stored identity that differs is untrusted.
- A Kyber base key seen twice for the same key pair is rejected as a replay.
- One-time Kyber keys are deleted after use, but last-resort keys are kept.

**Keys** (`initKeysIfNeeded`). Once per account:

1. Generate an `IdentityKeyPair` and a random `registrationId` in 1…2147483646. The device
   ID is always **1**.
2. Read `GET bond/api/v3/signal/1` (404 → none). New key IDs start after the highest
   already used.
3. Generate a batch of **15** one-time EC pre-keys, 15 Kyber pre-keys, one last-resort
   Kyber key and a signed pre-key with a random ID below `0xFFFFFF`.
4. Upload every public part to `crypto/<uid>/` as raw bytes: `identity_<reg>`, `preKey_<id>`,
   `kyberKey_<id>`, `kyberKeySignature_<id>`, `lastResortKyberKey_<id>`,
   `lastResortKyberKeySignature_<id>`, `signedPreKey_<id>` and `signedPreKeySignature_<id>`.
   The uploads ran in parallel.
5. Publish the IDs: `PUT bond/api/v3/signal/1 {registrationId, signedPreKeyId, nextPreKeyId,
   lastPreKeyId, nextKyberPreKeyId, lastKyberPreKeyId, lastResortKyberPreKeyId}`.

`replenishIfNeeded` topped keys up when fewer than 3 remained: `PATCH bond/api/v3/signal/1
{registrationId, lastPreKeyId, lastKyberPreKeyId}`. Private keys were never uploaded, by
either app, so this device had its own identity.

**Sessions** (`createSession`):

1. `GET bond/api/v3/bonds/{bondId}/signal/1` returns the partner's IDs. A 404, or a missing
   registration or signed pre-key, meant `partnerNotReady`. No Kyber key meant
   `partnerNeedsUpdate`.
2. Download the partner's files from `crypto/<partnerUID>/`, falling back to
   `crypto/<phone>/`.
3. Build a `PreKeyBundle` (with or without a one-time pre-key) and run
   `processPreKeyBundle`. On `untrustedIdentity` (the partner reinstalled), forget the old
   identity and retry.

The address is `ProtocolAddress(name: bondId, deviceId: 1)`.

**Messages**:

- The envelope is `[CiphertextMessage type byte] + serialize()`. The message content is
  *Android* Base64 of the envelope: 76-character lines, `\n` after each, plus a trailing
  `\n`.
- Sending: `POST bond/api/v3/bonds/{bondId}/chatmessages {type, content}` → `{id, timestamp}`.
  The quotes are stripped from the `id`.
- Types: **1** = text, **6** = new session (plaintext
  `PreKeySignalMessage::NEW_SESSION::<ms>`, which announces a fresh session),
  **2** = shared photo, **3** = secret photo.
- Photos are Signal-encrypted JPEG bytes. They are uploaded to
  `shared_gallery/<uid>/<yyyyMMdd_HHmmss_><9 digits>.tmp` (or `secret_gallery`) in
  `bond-touch-galleries`, and the message content is just the file name. When receiving, a
  name containing `/`, `\` or `..` is rejected, and the phone-number folder is the
  fallback.
- Receiving:
  - `GET bond/api/v3/bonds/chat` → `{chats: [{bondId, chatMessages: [{id, type, content,
    timestamp}], info}]}`.
  - Type byte `PreKey` → `signalDecryptPreKey`; otherwise `signalDecrypt`.
  - `PUT …/chatmessages/{id}/acknowledge` and `PUT …/chatmessages/{id}/seen`.

---

## 9. `LegacyFirebaseClient` and `LegacyDataView` (dead code)

This was an older, unused experiment: a Realtime Database REST client for **any** URL the
user typed in, with an optional `?auth=<token>`.

- `GET <url>/<path>.json` and `PUT <url>/<path>.json`.
- `testConnection()` read `/.info/serverTimeOffset.json`: 200 meant ok, 401 or 403 meant
  rejected.

`LegacyDataView` had a toggle ("Use legacy Firebase"), the URL and token fields, and a
connection test. Nothing navigated to it. It shared the `fbEnabled`, `fbURL` and `fbToken`
keys with the real sign-in.

---

## 10. File-by-file map of what was removed

Removed outright (verbatim copies are under `archive/bond-touch-cloud/` at the same path):

| File | What it was |
|---|---|
| `Sources/Legacy/BondBackend.swift` | Constants, Identity Toolkit, email-link sign-in, `bond()` request helper, raw dump / `PUT` for Debug |
| `Sources/Legacy/BondAPI.swift` | Token refresh and JWT helpers, colour and pattern conversion, typed Bond API calls (§4) |
| `Sources/Legacy/HeartAPI.swift` | Heart API client (§5) |
| `Sources/Legacy/FirebaseStorage.swift` | Storage REST client, App Check detection (§7) |
| `Sources/Legacy/LegacyFirebaseClient.swift` | RTDB REST client (§9) |
| `Sources/ViewModels/AppModel+Legacy.swift` | Sync loop, presence, location, invites, legacy sends, greeting, encounter and colour pushes, plus the Touch Language code (that part is kept, see below) |
| `Sources/Chat/BondChat.swift`, `Sources/Chat/SignalStore.swift` | Signal chat (§8) |
| `Sources/Views/LegacyLoginView.swift` | "Bond Touch login" screen |
| `Sources/Views/LegacyDataView.swift` | Unused RTDB settings screen |
| `ThirdParty/LibSignalClient/` | Vendored LibSignalClient v0.86.5 (Swift + `SignalFfi` headers + licence) |
| `scripts/fetch-libsignal-ffi.sh` | Fetches `libsignal_ffi.a` |

Moved, kept in the app:

- `Sources/Legacy/NetLog.swift` → `Sources/Support/NetLog.swift`.
- The non-Bond parts of `AppModel+Legacy.swift` → the new `Sources/ViewModels/AppModel+Meanings.swift`:
  - Touch Language: the library shared per iCloud partner, publish, merge, match and tag,
    add, edit and delete.
  - `setGreeting`, `setNextMeeting` and `setPartnerColor`, now local and iCloud only.

Edited (the removed lines are in `removed-hunks.patch`):

| File | Removed |
|---|---|
| `project.yml` | `LibSignalClient` target and dependency, `SignalFfi` include paths, `LIBRARY_SEARCH_PATHS`, `OTHER_LDFLAGS -lsignal_ffi -lz` |
| `.github/workflows/ios-{build-check,quick-build,screenshots,testflight,ui-tests}.yml` | "Fetch libsignal_ffi" step |
| `Sources/Models/Bond.swift` | `legacy` flag |
| `Sources/ViewModels/AppModel.swift` | Legacy state, `BondChat`, merging of `legacyPartners` into `partners`, `legacyPending` in `pendingBonds`, legacy branches in `transmit`, `sendKiss`, `sendHeartbeat`, `removeBond`, `publishProfile`, the location and sharing hooks, start and stop of the sync loop, keep-alive for original-app partners, `autoLinkPartners` in `refreshAll` |
| `Sources/ViewModels/AppModel+Chat.swift` | Chat links, migration, auto-link, meaning import, invite / link / unlink, `resetLegacyChat` |
| `Sources/ViewModels/AppModel+BondHeart.swift` | Heart API sync, upload, memories, pending and requests, share by email, ask, answer, share count |
| `Sources/ViewModels/AppModel+Photos.swift` | Storage photo download and upload, `legacyUploadMyPhoto` |
| `Sources/ViewModels/AppModel+Widget.swift`, `Sources/Watch/WatchBridge.swift` | Watching `legacyPartners` / `legacyMeanings` (they now watch `store.cloudMeanings`), widget's legacy sync |
| `Sources/ViewModels/AppModel+Notifications.swift` | Legacy notification identifier |
| `Sources/Stores/LocalStore.swift` | `useLegacyFirebase`, `firebaseDatabaseURL`, `firebaseAuthToken`, `legacyEmail`, `legacyRefreshToken`, `chatLinks`, `legacyChatEnabled`, `legacyFirebase` |
| `Sources/Stores/HeartLibrary.swift`, `Sources/Models/SavedHeartbeat.swift` | Heart API state (`pending`, `requests`, `syncStatus`, `lastSync`, `deletedServerIDs`, `controlTimestamp`, `lastCountShare`), `PendingHeartbeat`, `HeartRequest` |
| `Sources/Views/DebugView.swift` | "Original Firebase / Bond API" section, "My database" dump / editor |
| `Sources/Views/SettingsView.swift` | App Check photo hint |
| `Sources/Views/PairingView.swift` | Email invite for original-app partners |
| `Sources/Views/PeopleView.swift` | Received invites (Accept / Decline), legacy pending rows |
| `Sources/Views/PartnerDetailView.swift` | "Original Bond Touch app" connection card and "Invite to iCloud" |
| `Sources/Views/ChatView.swift` | Invite-or-link card for original-app partners |
| `Sources/Views/BondHeartView.swift`, `Sources/Views/BondHeartLibraryView.swift` | "Shared & requests", "Share count", "Share by email", heartbeat-count emails |
| `Sources/Views/Together/TogetherView.swift`, `Together/PolyViews.swift`, `Sources/CarPlay/CarPlaySceneDelegate.swift` | `!bond.legacy` filters |

---

## 11. Saved data on old installs

- `LocalStore.init` removes these `UserDefaults` keys once:
  - The Bond account: `fbEnabled`, `fbURL`, `fbToken`, `legacyEmail`, `legacyRefresh`.
  - Chat: `legacyChat`, `chatLinks`.
  - Sync state: `LegacySeenTouchIDs`, `ImportedLegacyMeanings`.

  It also deletes `Application Support/signal-store.json`, which held the Signal private
  keys.
- Original-app partners were never stored. They came from the server on each sync, so they
  simply no longer appear. Greetings, encounters, order and photo-background settings keyed
  by their bondId are left alone. They are harmless and are never shown, because no partner
  has that ID. Touches with them in history drop out after the history's usual 3 days.
  Chat messages expire after 72 h.
- Codable fields kept for decoding:
  - `TouchMeaning.serverID`, which also keeps widget IDs stable.
  - `ChatMessage.serverID`.
  - `SavedHeartbeat.serverID`, `emails` and `dirty`.
  - `HeartLibrary.Saved.lastCountShare`, plus `controlTimestamp` and `deletedServerIDs`,
    which are now optional.
- The chat history file keeps its old name, `chat/legacy-chat.json`.
- `ChatMessage.legacySelf` (`"me"`) was renamed to `ChatMessage.localSelf`, with the same
  value, so the demo and older history still count as "mine".

---

## 12. Quirks and timing (summary)

| Behaviour | Value |
|---|---|
| Bond sync poll | 4 s foreground, 15 s kept alive in the background, none otherwise |
| Partner details (location, battery) | every 4th cycle |
| `user/status {online:true}` | every 8th cycle, on foreground; `false` when going to the background without keep-alive |
| Location push | at most every 30 s (120 s in background), only while an original-only partner exists |
| Profile push | debounced 1 s |
| Token refresh | when less than 300 s are left before `exp` |
| Seen touch IDs kept | last 2000 |
| First sync after sign-in | records touches without playing them |
| Retries | none explicit. Failures surfaced as `legacyStatus = "Sync error: …"` and the next poll simply tried again. Acks, location and presence were best-effort (`try?`). A failed touch send was marked Failed in history and could be resent |
| Encounter units | seconds. Values above 1e11 were treated as milliseconds and rewritten |
| `favourite` | echoed back from the server so the partner's star wasn't wiped |
| App Check on Storage | photos, memories, chat keys and chat photos blocked for this app |
| Pushes | Bond pushes only via FCM to the official app, so this app could only poll |

---

## 13. How to restore it

1. **Whole app as it was:** `git checkout bond-cloud-final` (a branch on `origin`; the tag
   of the same name exists locally on the machine that made this change).
2. **Into the current code:**
   1. Copy the archived files back:
      `cp -R archive/bond-touch-cloud/Sources/. Sources/`, and likewise `ThirdParty/` and
      `scripts/`.
   2. Re-apply the removed hunks: `git apply archive/bond-touch-cloud/removed-hunks.patch`.
      The patch is the diff from this change back to `bond-cloud-final` for the files that
      stayed, so applying it puts the removed lines back. Use `git apply --3way` if those
      files have changed since.
   3. Delete `Sources/ViewModels/AppModel+Meanings.swift`. `AppModel+Legacy.swift` defines
      the same functions again.
   4. Run `scripts/fetch-libsignal-ffi.sh` (or restore the workflow step the patch puts
      back), then `xcodegen generate`.

   See `archive/bond-touch-cloud/README.md`.
