# Bond Touch — Feature Inventory

Reference documentation of the original Android app `com.impossible.bondtouch`
v11.2.0 (versionCode 490), by feature area. Describes what the app does, its data
model, and how each feature syncs. BLE/hardware details are in
[BLE_PROTOCOL.md](BLE_PROTOCOL.md); backend, Room schema, API endpoints, Firebase
usage, and crypto are in [DATA_MODEL.md](DATA_MODEL.md).

---

## Onboarding & Auth

`KickoffActivity` is the launcher/gate. `KickoffViewModel` routes to one of:
`WelcomeScreen`, `Login`, `Birthday`, `Consent`, `Profile`, `ValidatingProfile`,
`DashboardCompose`, `Heart`, `Error`. Launch intents parse to `Heart`, `None`, or
`PresenceInvite(bondId)`. The post-login gate is a valid `UserProfile` (username +
color + photo + vibration), not a paired bracelet. `DashboardActivity` is the main
post-login activity.

The entry/welcome landing screen presents a product and feature catalog
(`EntryCardId`: `Bracelet`, `Heart`, `BondTouchLite`, `PresencePlus`, `PrivateSpace`,
`TouchLanguage`, `NextEncounter`) with a language picker. The shop URL is
`https://bond-touch.com/`.

**Age gate:** date of birth is collected; age under 13 cannot proceed without a
guardian. Under-13 flow captures a parent's email and name, sends a consent request,
and waits for approval. Persisted via `ParentalConsentPreferencesRepository`.

**Profile setup sub-steps:** username (up to 25 letters and spaces, no special
characters), profile photo, color (identifies the user across the app and devices),
vibration intensity, bracelet placement guidance, and a completion screen.

**Permission requests** are presented as dedicated screens: notifications
(POST_NOTIFICATIONS, also requested in `KickoffActivity.onStart` on SDK 33+),
Bluetooth (BLUETOOTH_SCAN/CONNECT on API 31+), location (foreground/background,
used for BLE scanning pre-Android 12 and for Presence+ sharing), and camera (for
Bond Heart heartbeat recording). Terms of service and privacy policy are accepted.

**Authentication** is Firebase Authentication. `AuthenticatedUser` holds `uid`
(required) and `email` (nullable). Three sign-in providers: Continue with Google,
Continue with Apple, and Continue with email. The email path is **passwordless** —
email plus a 6-digit PIN/OTP (`request-pin` / `validate-pin`). There is no
phone-number auth and no password field. On login, E2E encryption keys are
initialized best-effort (uid-scoped, retried on entry/foreground). The Firebase ID
token is the bearer token for all REST calls. Logout and account deletion wipe
account data (`AccountDataWiper`, `AccountWipePlatform`).

---

## Dashboard / Home

`DashboardHomeUiState` is a sealed interface with three states: `Loading`,
`NoPartner`, and `Partnered`. The partnered dashboard is a horizontal pager of
`DashboardPartnerPage` (one per bond), driven by `activeIndex` and a partner-selector
chip row.

Each partner page shows a pair display: the user's and partner's photos
(`DashboardPersonUi`: photo, name, color, optional weather icon), connection status,
a central editable "dashboard message" (a short couple message shown between the two
photos; default "Hello,\nthis is us"), an encounter countdown, and a touch-history
feed. Profile states: `Bonded`, `Loading`, `NoPartner`, `InvitationPending`,
`UnsupportedPartnerState`. `DashboardPartnerStage`: `Empty`, `Requested`, `Bonded`.

**Status indicators** (`DashboardConnectionUi`): `Connected`, `NotConnected`,
`Sharing`, `NotSharing`, shown per person. Device badge (`DashboardDeviceUi`):
`Bond`, `BondMini`, `BondLite`. Snackbars cover disconnected, re-pair required, no
network, and send-failed states.

**Body slot** (`DashboardMainContent`): `AllCards`, `AppCards`, `ProductList`,
`TouchHistory`, `None`. The touch-history feed `UNION`s sent and received touches
into `HistoryMessage` rows (`id`, `bondId`, `status`, `isReceived`, `isMissed`
when received `status == -1`, `isReplaying` when `playing_status == 2`, content,
`meaningId`, `meaningName`, start/end colors). How much history loads is gated by
`DashboardTouchHistoryGate` (`hasPairedDevice`, `supportsMultiPartner`).

**Interactions** include: tap user/partner photo, cancel invitation, add partner,
pair bracelet, open the Heart app, device help, edit dashboard message, open/set
encounter, replay a touch, swipe-to-save a meaning from history. View models:
`DashboardHomeViewModel`, `DashboardViewModel`, `DashboardShellViewModel`,
`DashboardOverlayViewModel`.

---

## Touches

A touch is a tap-rhythm message sent from one partner's bracelet and played back on
the other's. The tap rhythm is captured on the physical bracelet (not by an in-app
screen) and delivered to the app over BLE as a timing pattern plus a `MenuIndex`
(the bracelet's selected partner slot, 1–3). The captured pattern plus generation is
forwarded to `MessagesRepository`.

**Pattern limits** are device/generation specific: classic bracelet up to 10 taps,
each up to 16 seconds; Bond Touch Lite up to 8 taps, each 0.5 s.

**Sending a saved meaning / touch** (`MessagesRepository.sendMeaningFromLibrary`):
takes a server timestamp, builds a `TouchMessageContent(timestamp, pattern,
generation)`, wraps it in a `SentMessage` (status 0), persists it, and POSTs it.

**Color** is not part of `TouchMessageContent`; it is carried by the meaning's
start/end color pair and the user's profile color. The user's own color is written
to the bracelet LED on pair/connect. `ColorMapper` remaps palette colors between
device variants before sending.

**Local replay / preview**: a meaning or a history message can be played on the
user's own bracelet via `BleBondRepository` with the user and partner colors. Replay
is blocked when the active picker is `Mini` or `Btl` (no physical bracelet to play
on), and requires a connected bracelet.

**Received-touch handling:** inbound touches are persisted as `ReceivedMessage`
rows and acked. Missed touches (`status == -1`) raise the notification "You might
have received new touches." A received touch is played on the paired bracelet
(pattern + colors) through the BLE stack. `playing_status == 2` marks a touch as
replaying. Received touches appear in the touch-history feed with their matched
meaning name and gradient colors when `meaning_id` resolves, otherwise as a plain
colored touch.

**Data model** (Room; see DATA_MODEL.md for full schema):
- `SentMessage`: `internal_id` PK, `status`, `id` (server id), `bond_id`,
  `meaning_id`, `playing_status`, `sender`, `recipient`, `timestamp`, `pattern`
  (JSON array of Longs), `generation`.
- `ReceivedMessage`: as `SentMessage` plus `receivedTimestamp`.
- `TouchMessageContent`: `timestamp`, `pattern` (list of Longs = tap-timing array),
  `generation`.
- `generation` enum (`v29`): `SECOND` (wire "2"), `THIRD` (wire "3"); unknown → `SECOND`.
- `pattern` is stored as a JSON array of Longs.

**Sync:** the sender writes a `SentMessage` row then POSTs `sendTouch` /
`sendBasicTouch`; the backend fans out an FCM data push; the recipient pulls the new
state over REST and stores a `ReceivedMessage`, acked with `ackLastTouchMessage`.
Ordering is by server `timestamp` plus local `receivedTimestamp`; dedup is by the
UNIQUE index on server `id`. `cleanupResending` re-sends unsent rows on startup
(offline retry queue). Touches are not Signal-encrypted; they route through the plain
REST API.

---

## Touch Language (meanings)

A meaning couples a tap pattern, a name (max 20 characters), a start/end color pair
(rendered as a two-stop gradient; stacking the two picker circles yields a single
solid color), and a generation, scoped to a `bond_id` / `user_phone_number` /
`paired_phone_number`. Flags: `is_new` (unseen badge), `favourite`, `deprecated`.

**No hardcoded starter meanings exist**; the library starts empty. The server
supplies `TouchMeaningRecommendation` rows (name + id) that the app syncs and shows
as suggested names when creating a meaning.

**User flow:** swipe left on a sent touch on the dashboard to add a meaning → pick an
existing/recommended meaning or create a custom one (name, 20 chars max, duplicate
guard) → choose a two-stop gradient color → save to the Touch Library. Per-meaning
menu: edit text, edit color, remove (removal is synced to both partners), toggle
favourite. Touch Language is available only to users with a paired Bond Touch
bracelet or an active Bond Touch Lite subscription.

**Matching** a received touch pattern to a meaning is server-driven: the history
query joins `ReceivedMessage.meaning_id` / `SentMessage.meaning_id` to
`TouchMeaning._id` to resolve name and colors. A touch with no matched meaning shows
as a plain colored touch; repeating a saved pattern attaches the meaning.

**Palettes** are per device variant (`TouchMeaningPicker` / `MeaningColorPicker`:
`V1`, `V2`, `V3`, `Mini`, `Btl`). V1 is a 9-entry palette; V2 is a 20-entry palette.

**Data model:**
- `TouchMeaning`: `internal_id` PK, `_id` (server id, UNIQUE), `user_phone_number`,
  `paired_phone_number`, `bond_id`, `name`, `pattern`, `timestamp`, `is_new`,
  `startColor` (nullable), `endColor` (nullable), `generation`, `favourite`,
  `deprecated`.
- `TouchMeaningRecommendation`: `id` PK, `name`, `timestamp`.

**Sync:** create/update/delete go through `TouchMeaningRepository` to the REST API
(`meanings` endpoints); recommendations are pulled from
`meanings/recommendations`. Deletion propagates to both partners.

---

## Partners & Invitations

A partner (`Partner`) carries `id`, `phoneNumber`, `userProfile`, `invitationStatus`,
`invitationDate`, `encounterInfo`, `online` (last-online timestamp), `bondInfo`,
`isActive`, `touchDevice`, `bondId`, `firebaseId`, `email`. Effective color =
`PartnerSettings.bondColor` else `UserProfile.color`.

**My People screen** lists partners (`MyPeoplePartnerUi`: bondId, name, email, color,
image, icon, status). From the app the user can edit a partner's **color** and
**icon**; name and email come from the partner's own profile. "Unbonding" removes a
partner.

**Invitations** are by **email** (no short code or QR). The invitation flow captures
the email, a selected color and icon, and whether location sharing is enabled.
`InvitationResult`: `Succeeded`, `Failed`. Incoming/pending invites are handled by a
`PartnerInviteQueue`; `PartnerInviteStep` is `Invite(...)` (a received invite to
accept) or `Bonded(...)` (result after bonding). Accepting an invite bonds the pair.
A data-sharing opt-in ("Share personal data") is offered.

**Multi-partner** is device-gated via `supportsMultiPartner` (a device-capability
flow), not a fixed integer cap. The classic single-bracelet path is 1 partner; the
bracelet itself supports up to 3 partner slots (`MenuIndex` FIRST/SECOND/THIRD).
`isBtm` distinguishes the Bond Touch Mini.

**Data model:**
- `Partner` table: `id` PK, `phone_number`, `invitation_status`, `invitation_date`,
  `online`, `active`, `touch_device`, `bond_id` (UNIQUE), `firebaseId`, `email`
  (UNIQUE), `name`, `color`, `has_image`, `version`, `encounter_date`,
  `encounter_date_modified`, `bond_message`, `bond_message_date_modified`,
  `bond_icon`, `bond_color`.
- `ReceivedInvite` table: `internal_id` PK, `bond_id` (UNIQUE), `email`, `name`,
  `color`, `version`, `has_image`, `firebase_id`, `version_os`, `is_ios`.

**Sync:** `createBond`, `acceptBond`, `cancelBond`, `updatePartnerSettings`,
`updatePartnerMessage`, `updatePartnerEncounterDate` over REST; bond status and
partner details are pulled via `BondRepository` / `PartnerDetailsRepository`, woken
by `BOND_SYNC` / `BOND_INVITE` FCM pushes.

---

## Chat (Private Space)

A partner-scoped (by `bond_id`), end-to-end-encrypted 1:1 text + photo chat, one
conversation per bond. Text messages, normal shared-gallery photos, and "secret"
photos are supported; there are **no voice notes / audio**.

Capabilities: a text input, typing indicator, read receipts (`sendLastSeenId`), date
separators, and screenshot detection (`chat_notification_screenshot_title`, mapped to
`ChatMessage.screenshotDetected`). New messages can trigger a bracelet light/vibration
(`sendChatNotificationToBracelet`).

**Ephemerality:** messages are wiped after 72 hours; secret photos are viewable for
24 hours; gallery images expire after 72 hours. `deleteExpiredMessages` enforces
retention. A partner-not-ready state is shown until the partner sets up Private Space.

**Data model** — `ChatMessage` table: `id` PK, `server_id`, `sender`, `recipient`,
`bond_id`, `is_received`, `type` (text / normal photo / secret photo), `status`
(sending/sent/failed), `bookmarkStatus`, `downloadStatus`, `screenshotDetected`,
`message` (ciphertext/base64), `timestamp`, `server_timestamp`.

**Encryption:** Signal protocol with post-quantum PQXDH (X3DH + CRYSTALS-Kyber); see
DATA_MODEL.md. Ciphertext is stored in `ChatMessage.message`.

**Sync:** `ChatMessageRepository` orchestrates send (`sendChatMessage`), ack
(`ackChatMessage`), retries (`sendFailedChatMessages` / `sendFailedAcks`), read state
(`sendLastSeenId`), image download, bookmark reconciliation, and `syncChat`. Woken by
`CHAT_SYNC` / `CHAT_MESSAGE` / `CHAT_INFO` FCM pushes.

---

## Private Space

A biometric/PIN-locked, end-to-end-encrypted space between a user and a partner,
containing the encrypted chat and ephemeral shared photos ("memories"). Hosted in
`PrivateSpaceHostActivity`, which is marked secure (`FLAG_SECURE`), blocking
screenshots and the recents preview.

**Unlock gate** (`PrivateSpaceUnlockAuthentication`): `Biometric` or `Pin`. Unlock
with the bracelet (double-tap) or with fingerprint is configurable. The OS biometric
prompt is driven by `PrivateSpaceBiometricPromptController`.

**Screens** (`PrivateSpaceKey`): `SetupStart`/`SetupPasscode`/`SetupFinish`
(first-time passcode creation), `Oobe`, `Chat`, `MeaningEditor`, `SharedGallery`,
`SecretGallery`, `PhotoSend` (drag-to-send gesture), `PresencePlusPaywall`. Pages are
per partner.

**Setup flow:** welcome → feature list → create passcode (and repeat) → encrypt
session → finish. Login into the space is by passcode or bracelet double-tap. An
app-version compatibility guard is present.

**Photos / "memories"** (`PrivateSpaceGalleryItem`: id, encryptedUri, downloadStatus,
bookmarkStatus, ownerColor, hoursLeft) are ephemeral (24h/72h countdown) and can be
bookmarked to persist (up to 10 saved in the shared gallery). Local bytes are
encrypted; photos are stored in Firebase Storage under `memories/<bondId>/<messageId>`
and decrypted for display.

**Crypto key material** is held in a separate `CryptoDatabase` (see DATA_MODEL.md):
`PrivateSpaceSession`, `PrivateSpacePreKey`, `PrivateSpaceSignedPreKey`,
`PrivateSpaceIdentityKey`, `PrivateSpaceKyberPreKey`.

---

## Presence (live location)

A paid ("Presence+") live-location feature between bonded partners, backed by Firebase
Realtime Database (not the normal backend).

**Shared payload** (`LiveLocation`): latitude, longitude, accuracy (meters, `-1.0`
when unavailable), timestamp (ms), timezone (`TimeZone.getDefault().getID()`), and a
mode string (`live`, `activity`, `offline`). The RTDB write payload is a map of
`{lat, lng, accuracy, timezone, timestamp, mode}` with mode hard-coded to `live` on
publish. Battery is **not** part of the presence payload (it is synced separately
through user/partner details). There is no "thinking of you" feature.

**Location acquisition** (`LivePresenceLocationTracker`): fused location, priority
HIGH_ACCURACY, interval 5000 ms, min update interval 2000 ms, max delay 5000 ms, min
displacement 10.0 m. Each fix builds a `LiveLocation` (mode `live`) and publishes it.

**Publish throttling** (`FirebaseRtdbService`): rejects out-of-range coordinates,
negative/huge accuracy, or location age > 30000 ms; requires ≥ 2.0 m haversine
distance from the last published point; minimum 10000 ms between live writes; RTDB
write-ack timeout 3000 ms. A foreground/background gate (`SessionInput`,
`PresenceCoordinator`) controls when tracking/publishing runs.

**Map** (`MapScreenKt`, Google Maps): profile-photo pins for user and partner, a
fused-pin mode (LEFT/RIGHT) when pins overlap, bottom panels for user and partner
locations, a weather card on the partner's location (`weatherCode`,
`temperatureDisplay`), and a Street View banner/caption.

**Saved Places** (`SavedPlace`: placeId, bondId, name, address, category, icon, lat,
lng, arrivalNotification): favorite map locations. `PlaceCategory`: `Love`, `Safety`,
`Routine`. A large `PlaceIcon` set (Home, Love, Restaurant, Coffee, Park, Beach,
School, Office, Shopping, Music, Cinema, Art, Gym, Parking, Travel, Hospital, Routine,
Safety, Alert, Location, Special, and more). `PlaceGeofenceManager` registers Android
geofences; `arrivalNotification` toggles the arrival alert.

**Privacy toggles:** a global sharing on/off (`LocationPreferences`, surfaced as
`isGlobalSharingDisabled` / `partnerGlobalSharingDisabled`) and per-partner sharing
(`PresencePlusStatus`: sharing, subscriptionActive, lastSyncTimestamp).
`PresencePlusSharingState`: `SHARING`, `PAUSED`, `NOT_SHARING`. Presence+ requires
mutual consent.

**Subscription / invite:** `PresencePlusRepository` persists per-partner status and
invite status plus the user's own sharing/subscription flags (DataStore). A paywall
and an invite-to-share flow exist. `PresencePlusInviteStatus`: inviteSent,
inviteTimestamp, inviteReceived, inviteReceivedTimestamp.

**Data model** — `SavedPlace` table: `internal_id` PK, `place_id` (UNIQUE),
`bond_id`, `name`, `place_icon`, `category_icon`, `lat`, `lng`,
`arrival_notification`, `address_name`. Presence+ status/invite maps are stored in
DataStore, not Room.

**Sync:** coarse presence/consent/sharing via REST (`updatePresence`,
`updateUserInfo`, `updateUserDetailsLocation`/`Sharing`/`Battery`); fine live location
streamed to Firebase RTDB and the partner's RTDB node observed in real time. Places:
`addPlace`, `updatePlace`, `deletePlace`, `notifyPlaceNear`. Woken by `PRESENCE_INVITE`
/ `PRESENCE_ARRIVAL` FCM pushes.

---

## Encounters

A shared "countdown to next time we meet" date per bond. Each partner can set an
encounter date the app counts down to.

`EncounterInfo`: `encounterDate`, `encounterDateModified`. `EncountersUiState` has one
page per partner (`EncounterPageUi`: `Set` with `daysLeft` / `isToday` /
`encounterMillis`, `NotSet` which auto-opens the picker, `Waiting`, `Empty`) plus a
partner-selector chip row. Actions: set/remove encounter date. Also surfaced on the
dashboard (with an encounter animation) and in Private Space
(`PrivateSpacePartnerInfo.daysLeftToEncounter`).

**Data model:** stored on the `Partner` table as `encounter_date` /
`encounter_date_modified`.

**Sync:** `updatePartnerEncounterDate` (PUT `bonds/{id}/encounter`); pulled with bond
details.

---

## Heartbeat (Bond Heart)

The Bond Heart is a separate BLE bracelet (advertised as `BondHeart`) that records and
plays back a heartbeat pattern between partners. A heartbeat is recorded via the
phone's camera/flashlight (not a health-platform permission). See BLE_PROTOCOL.md for
the device protocol, including the heartbeat-push encoding.

Features (from tutorials and models): waking the device, recording a heartbeat,
battery & charging, feeling the partner's heartbeat, a heartbeat count, and asking for
/ sending a heartbeat. The BLE stack reads a stored beat count (beatsCount,
playedCount) on a 1 s poll — there is no continuous heart-rate stream.

**Data model:**
- `HeartbeatItem` table: `localId` PK, `id`, `pattern`, `name`, `color`, `message`,
  `pendingStatus`, `createDate`, `createBy`, `selected`, `isDirty`, `deleted`, `seen`,
  `hasImage`, `imageTimestamp`, `imageUriToUpload`, `emails`, `totalPlayedCount`,
  `latestPlayedCount`, `latestPlayedCountSince` (`id` UNIQUE).
- `Request` table (heart invites/requests): `localId` PK, `id`, `fromUser`,
  `fromUserName`, `toUser`, `createdDate`, `seen` (`id` UNIQUE).

**Sync:** a separate Heart REST API (`https://api.bond-touch.com/heart/api/`) with
heartbeat and request endpoints; `HeartbeatNetworkSyncWorker` syncs heartbeats. Woken
by `HEARTBEATS_SYNC` / `REQUESTS_SYNC` FCM pushes. Heart photos ("heart memories") use
Firebase Storage.

---

## Bracelet (pairing / settings / DFU)

The Bond Touch bracelet pairs over BLE; see BLE_PROTOCOL.md for the full protocol,
state machine, pairing/bonding handshake, and Nordic Secure DFU firmware update. There
are five Bond Touch bracelet protocol variants (v1, v2, v3, v4, mini) selected at
runtime, plus the separate Bond Heart device.

App-facing bracelet concerns:
- **Pairing/connect** happens during onboarding or from the dashboard; the gate to the
  dashboard is a valid profile, not a paired bracelet.
- **Device badge / type** is surfaced as `Bond`, `BondMini`, `BondLite`.
- **Settings** (see Settings below): connection status, battery level, firmware
  version, battery-alert guide, disconnect/forget.
- **Vibration** level is user-configurable and stored on the `User` row (`vibration`,
  `vibration_balance_level`); it is written to the bracelet.
- **DFU** (firmware update) uses the Nordic DFU library with a bundled firmware ZIP;
  coordinated by `DfuLifecycleCoordinator`.
- Only one Bond Touch bracelet and one Bond Heart are managed at a time, each keyed by
  a persisted MAC address.

---

## Wear OS (Bond Touch Lite)

The phone app does not contain the watch UI; it contains the phone-side manager
(`BondLiteRepository`) that provisions a separate Wear OS companion app, "Bond Touch
Lite" (BTL). The watch sends and receives touches to/from another watch or any Bond
Touch bracelet. A touch is up to 8 taps, each 0.5 s. Partner status and heart rate are
not features of the watch app.

The phone pushes to the watch: a `BtlBundle` (auth token + account UID), the app
language (`WearLanguagePublisher`), and a purchase/billing flag. The watch is
discovered via `connectedAndInstalledNodes`. Setup prerequisite states
(`BtlSetupPrerequisiteResult`): `DeviceNotFound`, `AppNotInstalled`, `Error`,
`Ready(nodeId)`.

Watch touches are gated behind the `bond_lite` subscription
(`BondLiteRepository.isPairedAndPurchased`). On logout/unpair the phone schedules a
pending wipe of the watch's bundle (and optionally its purchase flag), retried if the
watch is offline. Wear preferences stored: `node_id`, `last_unpair_timestamp`,
`last_unpair_account_uid`, `pending_logout_wipe`, `pending_wipe_reset_purchase`,
`pending_wipe_node_id`.

---

## Widgets

There is exactly one home-screen widget: the **Send Meaning** widget
(`BondMeaningsWidgetReceiver` / `BondMeaningsWidget`, Glance / `AppWidgetProvider`).
Label "Send Meaning", description "Send touch meanings to your partner directly from
the home screen".

It displays a grid of configured touch-meaning slots (data from `TouchMeaningDao` and
`PartnerDao`). Empty states cover no meanings, no partner, not logged in, and loading.
Tapping a meaning slot sends that touch meaning to the partner; widget sends are
tagged `is_from_widget=true` in analytics.

Configuration launches `WidgetConfigActivity` on placement; the user chooses which
meanings appear. Storage (`WidgetConfigStore`, DataStore) keys `bond_id_<id>` and
`selected_meanings_<id>` per widget id, `MAX_SLOTS = 10`. Sizes: minWidth 180dp ×
minHeight 110dp, resizable, targetCell 4×3, updatePeriodMillis 3600000 (1 h). Refresh
via `WidgetRefreshWorker` (WorkManager).

---

## Settings

Settings destinations (`SettingsKey`): `Root`, `PersonalDetails`, `Username`,
`UserColor`, `Temperature`, `Language`, `Device`, `Vibration`, `DoNotDisturb`,
`Partner`, `PrivateSpace`, `Unlock`, `BraceletNotifications`, `ChangePasscode`,
`ResetPasscode`, `ResetPasscodeValidator`, `ResetPasscodeError`, `Help`, `Legal`,
`ReportProblem`, `LightsTutorial`.

**Top-level list:**
- Personal details → `PersonalDetails`
- My Bond Touch Bracelet / My bracelet → `Device`
- My partner / My people / Add partner → `Partner`
- Private Space → `PrivateSpace`
- Do not disturb → `DoNotDisturb`
- Bracelet notifications → `BraceletNotifications`
- Unlock → `Unlock`
- Language → `Language`
- Help & Support → `Help`
- Tutorials
- Manage Subscription
- Logout
- Delete account
- Disconnect this bracelet / Disconnect from Watch / Unbond
- Bond Touch Lite helpers (how to add partners, how to send touches)

**Personal details** (`PersonalDetails`): username (up to 25 letters, no special
characters), color (identifies the user across the app and devices), vibration level,
email (tap to copy), temperature unit, change photo.

**Vibration** (`Vibration`): legacy picker with levels Low/Medium/High/Strong and a
fine-tune slider; a V3 device picker maps device levels strong=1, high=2,
medium_high=3, medium=4, low=5.

**Temperature** (`Temperature`): Celsius or Fahrenheit; affects the
weather/temperature shared with the partner.

**Language** (`Language`): `SupportedLanguage` enum; `AppLanguageManager` applies the
locale (also reused on the Entry landing screen).

**My bracelet / Device** (`Device`): connection status, battery level (with a charging
variant), firmware version, "Learn battery alerts" → `LightsTutorial`, disconnect this
bracelet (confirm dialog; unpair "BOND" in Bluetooth settings). A Heart variant shows
"My Bond Heart", its battery level, and disconnect.

**Do Not Disturb** (`DoNotDisturb`): a DND toggle (no touches/notifications on the
bracelet when enabled) and a schedule sub-option (From / To / Set time).

**My partner** (`Partner`): partner name, partner email, a "Share personal data"
toggle (connection and location-based data), unbond (confirm dialog), and per-partner
change color / change icon.

**Private Space settings** (`PrivateSpace`): notification toggles — General (bracelet
vibrates/lights on new message) and Secret (distinct light/vibration on a secret
photo) — a bracelet-notifications button, change passcode, unlock options (with
bracelet / with fingerprint), and quick tips.

**Unlock** (`Unlock`): unlock Private Space with bracelet double-tap and/or
fingerprint (biometric prompt).

**Bracelet notifications** (`BraceletNotifications`): General + Secret toggles
controlling whether the bracelet reacts to new messages / secret photos.

**Passcode** (`ChangePasscode` / `ResetPasscode` / `ResetPasscodeValidator` /
`ResetPasscodeError`): change passcode (enter current → create new → repeat →
finish); forgot/reset is email-based (send reset email, validate via token link).

**Help & Support** (`Help`): Get help (`https://help.bond-touch.com`), give feedback,
report a problem → `ReportProblem`, privacy policy, regulatory certification, research
program application (tally.so). Report/feedback compose via email.

**Legal** (`Legal`): company and device data (Bond Touch, Inc., Menlo Park CA; Bond
Heart model BHEART001 with FCC/IC IDs), terms of service and privacy policy links.

**Account actions:** logout (confirm), delete account (confirm; backed by
`AccountDataWiper` / `AccountWipePlatform`), manage subscription + restore purchases
(Google Play Billing, Presence+ / Bond Touch Lite subscriptions). An app-version
footer is shown.

**Data model:** settings persist to the `User` Room row (username/name, color,
vibration, email, photo, temperature via preferences), to DataStore preference
repositories (parental consent, subscriptions, tutorials, app-rate, OOBE user), and to
`BondAppPrefs` (E2E preferences, local passcode). Per-partner color/icon persist on
the `Partner` row (`bond_color`, `bond_icon`).

**Sync:** profile/user changes PUT `user` and `user/details/*`; partner settings PUT
`bonds/{id}/settings`; subscriptions verify via `billing/*`; parental consent via
`user/consent`.

---

## Profile / photos

A user's profile carries `name`, `color`, `hasImage`, `version` (`UserProfile`). The
color backs avatars when no photo is set and identifies the user across the app and
devices.

**Picking** (`ProfilePhotoPicker`): pick from gallery or capture with the camera
(`TakePictureWithUriGrant`). `ProfilePhotoPickResult`: `Photo(uri)` or `Removed`;
removal uses the sentinel URI `bond://remove`.

**Storage:** profile photos go to Firebase Storage at `images/<firebaseId>/profile`
(`uploadProfileImage(firebaseId, version, uri, altUri)`; `deleteImage`). `version` is
bumped on change for cache-busting.

**Representation** (`ProfileImageStorageInfo`): `firebaseId`, `alternativeId`,
`version`, `hasImage`, `photoUri`, plus resolved Firebase Storage references. Displayed
as avatars, map pins, People rows, and in Private Space.

**Data model:** stored on the `User` row (`photo_uri`, `has_image`, `version`); each
partner carries its own `ProfileImageStorageInfo` (`has_image`, `version` on the
`Partner` row).

**Sync:** uploaded to Firebase Storage; `has_image` / `version` propagate through
user/partner details over REST.
