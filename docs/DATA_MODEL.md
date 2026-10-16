# Bond Touch — Backend & Data Layer

Reference documentation of the backend, local persistence, REST API, Firebase usage,
and cryptography of the original Android app `com.impossible.bondtouch` v11.2.0
(versionCode 490). Feature behavior is in [FEATURES.md](FEATURES.md); the bracelet
protocol is in [BLE_PROTOCOL.md](BLE_PROTOCOL.md).

---

## 1. Hosts, URLs, and telemetry destinations

All network destinations and telemetry sinks of the original app. The iOS port
replaces the Bond backend with iCloud/CloudKit and sends no telemetry; these hosts
must not be contacted.

### Backend hosts

| Host / URL | Purpose |
|---|---|
| `https://api.bond-touch.com/` | Main REST backend (Bond API v3/v4) |
| `https://api.bond-touch.com/heart/api/` | Heart/heartbeat device REST API |
| `https://track-prod.api.bond-touch.com/` | Analytics / CDP (Dare Data) service — `alias`, `profile`, `track` |
| `https://<project_id>-default-rtdb.firebaseio.com` | Firebase Realtime Database root (presence/live location); URL derived from the Firebase project id at runtime |

### Firebase Cloud Storage paths

| Path | Purpose |
|---|---|
| `crypto/<firebaseId>/<secretName>` | Encrypted E2E key-secret backups (secret names suffixed `_<index>`) |
| `images/<firebaseId>/profile` | Profile photos |
| `memories/<bondId>/<messageId>` | Chat / "memories" gallery photos |

### Telemetry destinations (the port sends none of this)

Three telemetry/SDK destinations are present:

1. **Dare Data API** (first-party, base `https://track-prod.api.bond-touch.com/`): all
   analytics events and profile attributes (`profile` and batched `track`). Events
   buffer in-memory and flush at `EVENTS_FLUSH_THRESHOLD = 40` or on demand; the user is
   keyed by `userIdentifier`.
2. **Klaviyo** (`com.klaviyo.analytics.Klaviyo`): push/marketing SDK.
3. **Firebase Analytics** (`com.google.firebase.analytics.FirebaseAnalytics`): bundled;
   the only first-party `logEvent` use is Remote Config wiring. No analytics event is
   routed to Firebase Analytics. Firebase Auth is used pervasively for identity.

**Analytics events (→ Dare Data API):** `app_opened`, `touch_sent` / `touch_sent_btl`
(`durations_array`, `meaning_type`, `meaning`, `touch_id`, `partner_firebase_id`,
`start_color`, `end_color`), `meaning_sent` (`durations_array`, `meaning`, `meaning_id`,
`start_color`, `end_color`, `is_from_widget`), `create_touch_meaning` (`meaning_type`,
`meaning`, `durations_array`, `start_color`, `end_color`, `re_sent`, `source`),
`chat_message_sent` (`partner_firebase_id`), `photo_sent` (`asset_id`,
`partner_firebase_id`), `secret_photo_sent` (`asset_id`, `partner_firebase_id`),
`place_enter` (`category`, `icon`), `presence_enter`, `geo_location` (`location` =
`"<lat>,<long>"`), `unbond` (`partner_email`), `widget_created`. Every event also
carries a device-info string.

**Profile attributes (→ Dare Data API):** on identify — `email_address`, `app_version`
("11.2.0"), `app_version_code` (490), `os_version`, `phone_brand`, `phone_model`,
`device_type` ("Android"), `phone_native_language`; on widget change —
`has_active_widget`.

**Klaviyo profile data** (`KlaviyoProfileData`, stored locally in
`klaviyo_datastore.json`): `externalId` (Firebase UID), `email`, `phoneNumber`,
`platform`, `appVersionCode`, `heartFwVersion` (Bond Heart firmware version), `devices`.
Sent on push-token change, on profile update, on app stop (`updateAll`), and cleared on
logout.

### Firebase SDKs in use

- **Firebase Auth** — `com.google.firebase.auth.FirebaseAuth`; its ID token is the API
  bearer token.
- **Firebase Realtime Database** — live presence/location.
- **Firebase Cloud Storage** — crypto secrets + photos.
- **Firebase Cloud Messaging** — push wake-ups.
- Firebase config fields read at runtime: `google_app_id`, `google_api_key`,
  `firebase_database_url`, `ga_trackingId`, `gcm_defaultSenderId`, `google_storage_bucket`,
  `project_id`. Firebase project id is `bond-touch`; database URL
  `https://bond-touch.firebaseio.com`; storage bucket `bond-touch.appspot.com`; sender id
  `625752440215`. Crashlytics is present.

---

## 2. Local data model (Room)

Two Room databases exist.

### 2a. `AppDatabase`

Schema version 66 (migrations 17→66). DAOs: `HistoryMessagesDao` (a read-only
view/query over the message tables, no table of its own), `ChatMessageDao`,
`HeartbeatDao`, `PartnerDao`, `ReceivedInviteDao`, `ReceivedMessageDao`, `RequestDao`,
`SavedPlaceDao`, `SentMessageDao`, `TouchMeaningDao`, `TouchMeaningRecommendationDao`,
`UserDao`.

**User** (local device owner)
`id` INTEGER PK AUTOINCREMENT, `phone_number` TEXT NOT NULL, `email` TEXT, `photo_uri`
TEXT, `dirty` INTEGER NOT NULL, `oobe_submission_pending` INTEGER NOT NULL, `vibration`
INTEGER NOT NULL, `vibration_balance_level` INTEGER NOT NULL, `touch_device` TEXT,
`firebaseId` TEXT NOT NULL, `name` TEXT NOT NULL, `color` INTEGER NOT NULL, `has_image`
INTEGER NOT NULL, `version` INTEGER NOT NULL.

**Partner** (bonded partner)
`id` INTEGER PK AUTOINCREMENT, `phone_number` TEXT NOT NULL, `invitation_status` TEXT,
`invitation_date` INTEGER, `online` INTEGER NOT NULL, `active` INTEGER NOT NULL,
`touch_device` TEXT, `bond_id` TEXT NOT NULL, `firebaseId` TEXT, `email` TEXT NOT NULL,
`name` TEXT NOT NULL, `color` INTEGER NOT NULL, `has_image` INTEGER NOT NULL, `version`
INTEGER NOT NULL, `encounter_date` INTEGER, `encounter_date_modified` INTEGER,
`bond_message` TEXT, `bond_message_date_modified` INTEGER, `bond_icon` TEXT,
`bond_color` INTEGER. Indexes: UNIQUE on `id`, UNIQUE on `bond_id`, UNIQUE on `email`.

**ReceivedMessage** (incoming touches)
`internal_id` INTEGER PK AUTOINCREMENT, `status` INTEGER NOT NULL, `receivedTimestamp`
INTEGER NOT NULL, `id` TEXT (server id), `bond_id` TEXT NOT NULL, `meaning_id` TEXT,
`playing_status` INTEGER NOT NULL, `sender` TEXT, `recipient` TEXT, `timestamp` INTEGER
NOT NULL, `pattern` TEXT NOT NULL, `generation` TEXT NOT NULL. Indexes: INDEX on
`bond_id`, UNIQUE on `id`.

**SentMessage** (outgoing touches)
`internal_id` INTEGER PK AUTOINCREMENT, `status` INTEGER NOT NULL, `id` TEXT (server id),
`bond_id` TEXT NOT NULL, `meaning_id` TEXT, `playing_status` INTEGER NOT NULL, `sender`
TEXT, `recipient` TEXT, `timestamp` INTEGER NOT NULL, `pattern` TEXT NOT NULL,
`generation` TEXT NOT NULL. Indexes: INDEX on `bond_id`, UNIQUE on `id`.

**ChatMessage** (Private Space chat)
`id` INTEGER PK AUTOINCREMENT, `server_id` TEXT, `sender` TEXT NOT NULL, `recipient`
TEXT NOT NULL, `bond_id` TEXT NOT NULL, `is_received` INTEGER NOT NULL, `type` INTEGER
NOT NULL, `status` INTEGER NOT NULL, `bookmarkStatus` INTEGER NOT NULL, `downloadStatus`
INTEGER NOT NULL, `screenshotDetected` INTEGER NOT NULL, `message` TEXT NOT NULL
(ciphertext/base64 for E2E), `timestamp` INTEGER NOT NULL, `server_timestamp` INTEGER
NOT NULL.

**TouchMeaning** (named touch patterns)
`internal_id` INTEGER PK AUTOINCREMENT, `_id` TEXT (server id), `user_phone_number` TEXT
NOT NULL, `paired_phone_number` TEXT NOT NULL, `bond_id` TEXT NOT NULL, `name` TEXT NOT
NULL, `pattern` TEXT NOT NULL, `timestamp` INTEGER NOT NULL, `is_new` INTEGER NOT NULL,
`startColor` INTEGER, `endColor` INTEGER, `generation` TEXT NOT NULL, `favourite`
INTEGER NOT NULL, `deprecated` INTEGER NOT NULL. Index: UNIQUE on `_id`.

**TouchMeaningRecommendation**
`id` TEXT NOT NULL PK, `name` TEXT NOT NULL, `timestamp` INTEGER NOT NULL.

**HeartbeatItem** (Bond Heart feature)
`localId` INTEGER PK AUTOINCREMENT, `id` TEXT, `pattern` TEXT NOT NULL, `name` TEXT NOT
NULL, `color` INTEGER NOT NULL, `message` TEXT NOT NULL, `pendingStatus` TEXT NOT NULL,
`createDate` TEXT NOT NULL, `createBy` TEXT NOT NULL, `selected` INTEGER NOT NULL,
`isDirty` INTEGER NOT NULL, `deleted` INTEGER NOT NULL, `seen` INTEGER NOT NULL,
`hasImage` INTEGER NOT NULL, `imageTimestamp` TEXT, `imageUriToUpload` TEXT, `emails`
TEXT NOT NULL, `totalPlayedCount` INTEGER NOT NULL, `latestPlayedCount` INTEGER NOT NULL,
`latestPlayedCountSince` INTEGER NOT NULL. Index: UNIQUE on `id`.

**Request** (Bond Heart invites/requests)
`localId` INTEGER PK AUTOINCREMENT, `id` TEXT, `fromUser` TEXT NOT NULL, `fromUserName`
TEXT NOT NULL, `toUser` TEXT NOT NULL, `createdDate` TEXT NOT NULL, `seen` INTEGER NOT
NULL. Index: UNIQUE on `id`.

**SavedPlace** (Presence+ geofenced places)
`internal_id` INTEGER PK AUTOINCREMENT, `place_id` TEXT NOT NULL, `bond_id` TEXT NOT
NULL, `name` TEXT NOT NULL, `place_icon` TEXT NOT NULL, `category_icon` TEXT NOT NULL,
`lat` REAL NOT NULL, `lng` REAL NOT NULL, `arrival_notification` INTEGER NOT NULL,
`address_name` TEXT NOT NULL DEFAULT ''. Index: UNIQUE on `place_id`.

**ReceivedInvite** (incoming bond invitations)
`internal_id` INTEGER PK AUTOINCREMENT, `bond_id` TEXT NOT NULL, `email` TEXT NOT NULL,
`name` TEXT NOT NULL, `color` INTEGER NOT NULL, `version` INTEGER NOT NULL, `has_image`
INTEGER NOT NULL, `firebase_id` TEXT NOT NULL, `version_os` TEXT NOT NULL, `is_ios`
INTEGER. Index: UNIQUE on `bond_id`.

`pattern` columns store a JSON array of Longs (`Converters`). The `generation` enum
(`v29`) serializes as "2" (SECOND) or "3" (THIRD); unknown → SECOND.

### 2b. `CryptoDatabase`

Separate DB, schema version 4 (migrations 1→4). DAO: `CryptoStoreDao`. Holds the Signal
protocol key material for Private Space.

**PrivateSpaceSession**
`deviceId` INTEGER NOT NULL, `bondId` TEXT NOT NULL, `sessionRecord` BLOB NOT NULL, `id`
INTEGER PK AUTOINCREMENT, `recipientPhoneNumber` TEXT NOT NULL.

**PrivateSpacePreKey**
`keyId` INTEGER NOT NULL, `publicKey` TEXT NOT NULL, `privateKey` TEXT NOT NULL, `id`
INTEGER PK AUTOINCREMENT.

**PrivateSpaceSignedPreKey**
`keyId` INTEGER NOT NULL, `publicKey` TEXT NOT NULL, `privateKey` TEXT NOT NULL,
`signature` TEXT NOT NULL, `timestamp` INTEGER NOT NULL, `id` INTEGER PK AUTOINCREMENT.

**PrivateSpaceIdentityKey**
`id` INTEGER PK AUTOINCREMENT, `recipientPhoneNumber` TEXT NOT NULL, `bondId` TEXT NOT
NULL, `identityKey` TEXT NOT NULL, `firstUse` INTEGER NOT NULL, `timestamp` INTEGER NOT
NULL, `nonBlockingApproval` INTEGER NOT NULL, `verified` INTEGER NOT NULL.

**PrivateSpaceKyberPreKey**
`id` INTEGER PK AUTOINCREMENT, `keyId` INTEGER NOT NULL, `timestamp` INTEGER NOT NULL,
`serialized` BLOB NOT NULL, `lastResort` INTEGER NOT NULL.

### 2c. DataStore / SharedPreferences (not Room)

Preference repositories back onto Jetpack DataStore: `AppRatePreferencesRepository`,
`ParentalConsentPreferencesRepository`, `SubscriptionPreferencesRepository`,
`TutorialPreferencesRepository`, `OobeUserRepository`. `BondAppPrefs` holds E2E
preferences and the local passcode. `LocalCipherDataImpl` uses SharedPreferences
`"UnprotectedCipherPrefs"` as a fallback cipher store. Presence+ per-partner status and
invite-status maps, plus the user's own sharing/subscription flags, are stored in
DataStore (`presence_plus_status_map`, `partner_invite_status_map`,
`user_presence_plus_sharing`, `user_presence_plus_subscription_active`).

---

## 3. Backend / network endpoints

### 3a. Main Bond REST API — base `https://api.bond-touch.com/`

All paths relative to the base URL. Retrofit annotations decode as GET/POST/PUT/DELETE
with `@Path`, `@Body`, `@Query`.

**User / account:**
- GET `bond/api/v3/user` — getUser
- PUT `bond/api/v3/user` — updateUser
- DELETE `bond/api/v3/user` — deleteUser
- GET `bond/api/v3/user/details` — getUserDetails
- DELETE `bond/api/v3/user/details` — deleteUsersDetails
- PUT `bond/api/v3/user/details/sharing` — updateUserDetailsSharing
- PUT `bond/api/v3/user/details/location` — updateUserDetailsLocation
- PUT `bond/api/v3/user/details/chatinfo` — updateUserDetailsChatInfo
- PUT `bond/api/v3/user/details/battery` — updateUserDetailsBattery
- PUT `bond/api/v3/user/status` — updateUserInfo
- PUT `bond/api/v3/user/tokens/device` — updateToken (FCM device token)
- PUT `bond/api/v3/user/tokens/applewatch` — updateWatchToken
- POST `bond/api/v3/user/token/custom` — getAuthToken (BTL custom auth token)
- PUT `bond/api/v3/user/consent` — updateParentalConsent
- GET `bond/api/v3/user/consent` — getParentalConsentStatus

**Bonds / partners:**
- GET `bond/api/v4/bonds` — getBonds → `{bonds: [Bond]}` (partners, sent/received invites,
  received touches, meanings, greeting, encounter; see §3e)
- GET `bond/api/v3/bonds/details` — getPartnersDetails → `[{bondId, location, battery, sharing, chatInfo}]`
- POST `bond/api/v4/bonds` — createBond
- POST `bond/api/v4/bonds/{id}/accept` — acceptBond
- DELETE `bond/api/v3/bonds/{id}` — cancelBond
- PUT `bond/api/v3/bonds/{id}/settings` — updatePartnerSettings
- PUT `bond/api/v3/bonds/{id}/message` — updatePartnerMessage
- PUT `bond/api/v3/bonds/{id}/encounter` — updatePartnerEncounterDate

**Touches:**
- POST `bond/api/v3/bonds/{bondId}/touches` — sendTouch
- POST `bond/api/v3/bonds/{bondId}/touches/basic` — sendBasicTouch
- PUT `bond/api/v3/bonds/{bondId}/touches/{id}/acknowledge` — ackLastTouchMessage

**Touch meanings:**
- POST `bond/api/v3/bonds/{bondId}/meanings` — createMeaning
- POST `bond/api/v3/bonds/{bondId}/meanings/basic` — createBasicMeaning
- PUT `bond/api/v3/bonds/{bondId}/meanings/{meaningId}` — updateMeaning
- DELETE `bond/api/v3/bonds/{bondId}/meanings/{meaningId}` — deleteMeaning
- GET `bond/api/v3/meanings/recommendations` — getMeaningRecommendations

**Chat (Private Space):**
- GET `bond/api/v3/bonds/chat` — syncChat
- POST `bond/api/v3/bonds/{bondId}/chatmessages` — sendChatMessage
- PUT `bond/api/v3/bonds/{bondId}/chatmessages/{messageId}/acknowledge` — ackChatMessage
- PUT `bond/api/v3/bonds/{bondId}/chatmessages/{messageId}/bookmark` — bookmarkChatMessage
- DELETE `bond/api/v3/bonds/{bondId}/chatmessages/{messageId}/bookmark` — removeBookmarkChatMessage
- PUT `bond/api/v3/bonds/{bondId}/chatmessages/{messageId}/seen` — markChatMessageAsSeen
- POST `bond/api/v3/bonds/{bondId}/chat/restore` — sendNeedsRestore
- PUT `bond/api/v3/bonds/{bondId}/chat/restore/messages` — sendRestoreMessages
- DELETE `bond/api/v3/bonds/{bondId}/chat/restore/messages` — deleteRestore

**Signal / E2E key distribution:**
- PUT `bond/api/v3/signal/{deviceId}` — updateSignalInfo (publish own key bundle)
- PUT `bond/api/v3/bonds/{bondId}/signal/{deviceId}` — updatePreKeysInfo
- GET `bond/api/v3/signal/{deviceId}` — getSelfSignalInfo
- GET `bond/api/v3/bonds/{bondId}/signal/{deviceId}` — getOtherSignalInfo (fetch partner bundle)

**Presence+ / places:**
- PUT `bond/api/v3/presences/{bondId}` — updatePresence
- POST `bond/api/v3/presences/invite/{bondId}` — sendPresenceInvite
- POST `bond/api/v3/presences/{bondId}/places` — addPlace
- PUT `bond/api/v3/presences/{bondId}/places/{placeId}` — updatePlace
- DELETE `bond/api/v3/presences/{bondId}/places/{placeId}` — deletePlace
- POST `bond/api/v3/presences/{bondId}/places/{placeId}/near` — notifyPlaceNear

**Auth / passcode:**
- POST `bond/api/v3/auth/request-pin` — requestAuthPin
- POST `bond/api/v3/auth/validate-pin` — validateAuthPin
- POST `bond/api/v3/pincode/reset` — resetPassCode
- POST `bond/api/v3/pincode/validate?token=…` — validatePassCode

**Billing:**
- POST `bond/api/v3/billing/products/verify` — verifyInAppPurchase
- POST `bond/api/v3/billing/subscriptions/verify` — verifySubscription

**Auth token:** every request gets header `Authorization: Bearer <Firebase ID token>`.
The token is fetched off the main thread from the current Firebase user; expiry is
checked via the `exp` JWT claim and force-refreshed when needed. No custom API key —
identity is entirely Firebase Auth.

### 3b. Heart (device) REST API — base `https://api.bond-touch.com/heart/api/`

- GET `/heart/api/v2/user/heartbeats`
- POST `/heart/api/v2/user/heartbeats`
- PUT `/heart/api/v2/user/heartbeats/{id}` (two PUT variants)
- DELETE `/heart/api/v2/user/heartbeats/{id}`
- POST `/heart/api/v2/user/heartbeats/{id}/total_count`
- POST `/heart/api/v2/user/heartbeats/{id}/count`
- DELETE `/heart/api/v2/user`
- GET `/heart/api/v2/requests`
- POST `/heart/api/v2/requests`
- DELETE `/heart/api/v2/requests/{id}`
- PUT `/heart/api/v2/heartbeats/{id}/requests`

### 3c. Analytics / CDP — base `https://track-prod.api.bond-touch.com/`

Own OkHttp client, no Firebase auth interceptor: POST `alias`, POST `profile`,
POST `track`.

### 3e. Request / response bodies (Gson field names)

- **Bond** (`getBonds` item): `bondId`, `email`, `firebaseId`, `phoneNumber`, `status`
  (`REQUESTED` sent by me · `RECEIVED` sent to me · `BONDED` · `NONE`), `profile {name, color,
  hasImage, version}`, `settings {color, icon}`, `touches [{id, meaning, message {timestamp,
  pattern, generation}}]`, `meanings [MeaningDto]`, `presence`, `dashboardMessage`,
  `dashboardMessageModified`, `encounterDateTimestamp`, `encounterDateModified`,
  `invitationTimestamp`, `lastSeenTouchId`, `touchDevice`, `isIos`, `versionOS`.
- **sendTouch** body `{timestamp, pattern: [ms on/off], generation}` → `{id, meaning}`.
  `generation` serialises as `"2"` (SECOND) or `"3"` (THIRD); THIRD only for the BTM bracelet.
- **MeaningDto / createMeaning / updateMeaning**: `{id, name, pattern, startColor, endColor,
  generation, favourite, favouriteCreatedTimestamp}`; colours are Android ARGB ints.
- **createBond** `{email}`; **updatePartnerSettings** `{color, icon}`; **updatePartnerMessage**
  `{message}`; **updatePartnerEncounterDate** `{timestamp}`.
- **updateUserInfo** `{online}` → `{partners: [{bondId, online}]}`.
- **updateUserDetailsLocation** `{lat, lng, timezone}`; **updateUserDetailsSharing** `{sharing}`.
- **getUser / updateUser**: `{email, appVersion, fwVersion, fwVersionHeart, isIos, touchDevice,
  profile {name, color, hasImage, version}}` (+ `bypassFlags` on GET).
- **sendChatMessage** `{type, content}` → `{id, timestamp}`; `content` is Signal ciphertext.

### 3d. Realtime transport — Firebase RTDB

Live location is written to RTDB as a map `{lat, lng, accuracy, timezone, timestamp,
mode:"live"}`. The DB root URL is `https://<project_id>-default-rtdb.firebaseio.com`.
There is no Firestore usage and no app-owned websocket — realtime is RTDB (presence) +
FCM push (everything else).

---

## 4. End-to-end encryption

### Scheme

E2E uses the **Signal protocol via `org.signal.libsignal`** with post-quantum **PQXDH**
(X3DH + CRYSTALS-Kyber).
- Identity: `IdentityKeyPair` plus a registration id.
- Signed pre-key: `SignedPreKeyRecord`.
- One-time EC pre-keys: 15 generated per batch via `ECKeyPair.generate()`; ids modulo
  `Medium.MAX_VALUE`.
- Kyber pre-keys: 15 one-time **KYBER_1024** keys per batch via
  `KEMKeyPair.generate(KEMKeyType.KYBER_1024)`, each signed with the EC identity private
  key, plus a last-resort Kyber pre-key.
- Message cipher: `SessionCipher`. Chat payloads are Base64-encoded ciphertext.

### Key distribution (through the Bond backend)

- The own public bundle (identity key, signed pre-key, pre-key ids, kyber pre-key ids)
  is uploaded with `updateSignalInfo(deviceId=1, …)` → PUT `bond/api/v3/signal/{deviceId}`
  plus `updatePreKeysInfo`.
- The partner bundle is fetched with `getOtherSignalInfo` → GET
  `bond/api/v3/bonds/{bondId}/signal/{deviceId}`; sessions are then built.
- `deviceId` is hardwired to `1`.

### Private-key secret backup (through Firebase Storage)

Private key material is encrypted and backed up to Firebase Cloud Storage at
`crypto/<firebaseId>/<secretName>` (secret names suffixed `_<index>`). This lets a
reinstall restore the same Signal identity.

### Local key storage

Signal state is persisted in the separate `CryptoDatabase` (§2b) via custom stores:
`PrivateSpaceSessionStore`, `PrivateSpaceIdentityKeyStore`, `PrivateSpacePreKeyStore`,
`PrivateSpaceSignedPreKeyStore`, `PrivateSpaceKyberPreKeyStore` (all backed by
`CryptoStoreDao` / `CryptoStoreRepository`).

### Local at-rest cipher (separate from E2E)

`LocalCipher` encrypts local data with **AES/GCM/NoPadding**; the AES key is derived
with **PBKDF2withHmacSHA1And8BIT** from the passcode + salt. Cipher material is resolved
by `LocalCipherDataImpl` (Android Keystore-protected, with a fallback to plain
SharedPreferences `"UnprotectedCipherPrefs"`).

### What is encrypted

- **Private Space chat messages** (text and photo references) — E2E via Signal;
  ciphertext stored in `ChatMessage.message`.
- **Chat/gallery photos** — stored in Firebase Storage under `memories/…`, downloaded
  and decrypted through the chat image pipeline.
- **Touches** (`sendTouch` / `sendBasicTouch`) — carry a `pattern` + `meaning_id`;
  these go through the plain REST API and are **not** wrapped in the Signal SessionCipher.
- **Live presence/location** — written to Firebase RTDB as plain map fields; not
  Signal-encrypted.

---

## 5. Sync model

All content routes through the Bond backend (`api.bond-touch.com`); the two phones never
talk peer-to-peer. The pattern is: sender does a REST write → backend fans out an FCM
data push to the recipient → recipient pulls the new state over REST.

**Touches:** send writes a `SentMessage` row then POSTs `sendTouch` / `sendBasicTouch`;
`cleanupResending` resets `playing_status` on startup and re-sends unsent rows (the
offline/retry queue). Receive is pulled during a bond sync, stored as `ReceivedMessage`,
and acked with `ackLastTouchMessage`. Ordering key is server `timestamp` + local
`receivedTimestamp`; dedup via UNIQUE index on server `id`. `generation` tags the
crypto/meaning generation.

**Chat (Private Space):** `ChatMessageRepository` sends with `sendChatMessage`, acks with
`ackChatMessage`, retries unsent items, syncs read state (`sendLastSeenId`), downloads
photos, enforces retention (`deleteExpiredMessages`), and reconciles bookmarks. Messages
are E2E (§4).

**Presence:** coarse presence/consent/sharing via REST (`updatePresence`,
`updateUserInfo`, `updateUserDetailsLocation`/`Sharing`/`Battery`); fine live location
streamed to Firebase RTDB and the partner's node observed in real time, throttled by
distance (≥ 2 m) and time.

**Push wake-ups (FCM fan-out):** a `FirebaseMessagingService` receives FCM data
messages. The message-type field maps to: `UNKNOWN`, `BOND_SYNC`, `BOND_INVITE`,
`TOUCH_SYNC`, `USER_DETAILS_SYNC`, `CHAT_SYNC`, `TOKEN_REFRESHED`, `UNDER_13_CONSENTED`,
`HEARTBEATS_SYNC`, `REQUESTS_SYNC`, `PRESENCE_INVITE`, `PRESENCE_ARRIVAL`, `CHAT_MESSAGE`,
`CHAT_INFO`. Each type enqueues a `PushSyncWorker` (unique work `push-sync-<TYPE>`);
`TOKEN_REFRESHED` updates the FCM token; Klaviyo marketing messages route to the Klaviyo
SDK. `onDeletedMessages()` schedules a `FullSyncWorker`. The orchestrator
`BondSyncCoordinator` runs bonds + touches then chat, returning a `BondSyncResult`; it
aborts if the Firebase user changed.

**Coordination guards:** `AccountWorkTags` tags every account-scoped work item with the
current Firebase uid; sync no-ops if the signed-in account changes mid-flight.

---

## 6. Background workers (WorkManager)

| Worker | Type / schedule | Does |
|---|---|---|
| `FullSyncWorker` | One-time, REPLACE; on app foreground and on `onDeletedMessages()` | Full bonds + touches + chat pull |
| `PushSyncWorker` | One-time per FCM push, unique `push-sync-<type>`, KEEP | Targeted sync by push type |
| `PrivateSpaceMessagesSyncWorker` | One-time, self-rearming loop bypassing backoff, REPLACE | Syncs Private Space E2E messages |
| `PrivateSpaceMessagesDeleteWorker` | Periodic, every 3 hours, KEEP | Deletes expired Private Space messages |
| `UserDetailsSyncWorker` | Periodic, every 6 hours, KEEP | Pushes user details (battery/location/sharing/status) |
| `SharingFlagWorker` | Periodic, every 7 days, KEEP (+ a one-time variant) | Syncs the data-sharing flag |
| `PresencePlusSyncWorker` | One-time retry, KEEP, on a failed Presence+ sync | Re-syncs Presence+ subscription/entitlement |
| `PlaceGeofenceReconcileWorker` | One-time, on place changes / boot | Reconciles OS geofences against `SavedPlace` rows |
| `BondIdMigrationWorker` | One-time | Migrates phone-number-keyed data to `bond_id` |
| `HeartbeatNetworkSyncWorker` | Registered at app start | Syncs Bond Heart heartbeats with the Heart API |

Sync workers carry a `NetworkType` CONNECTED constraint; account-scoped workers also
carry the `AccountWorkTags` tag.
