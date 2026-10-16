# Bond Touch — Private Space E2E Chat Protocol (wire spec)

Reverse-engineered from `com.impossible.bondtouch` v11.2.0 (jadx static analysis only).
Goal: let a Swift client built on **LibSignalClient v0.86.5** interoperate byte for byte
with the Android app. Everything below comes from decompiled code. Items marked
**UNCERTAIN** say why.

Conventions:
- "Android Base64 DEFAULT" means `android.util.Base64` with flags `0`: standard alphabet
  (`+/`), `=` padding, **a `\n` after every 76 output characters and a trailing `\n`**.
  The decoder with flags `0` ignores whitespace. (The newline behaviour comes from the
  Android SDK, not from app code.)
- `firebaseId` means the Firebase Auth UID of the user (`FirebaseAuth.getInstance().currentUser.uid`).
- `bondId` means the bond identifier from the Bond API (`Partner.bondId`, DB column `bond_id`).
- Signal `deviceId` is always **1**.
- Decompiled sources are referenced as: `out3/` = jadx `--show-bad-code`, `out4/` = jadx
  `-m simple` (linear code, which is reliable for coroutine bodies), `out/` = the default decompile.
  All paths are under the scratchpad `re/` directory.

---

## 0. Corrections to `DATA_MODEL.md`

Code reading contradicts four statements in `DATA_MODEL.md`:

| DATA_MODEL.md says | Code says |
|---|---|
| `crypto/<firebaseId>/<secretName>` are "encrypted key-secret backups" that "let a reinstall restore the same Signal identity" | They hold **only public key material and signatures**, stored as raw unencrypted bytes. No private key is ever uploaded. See §1. |
| Chat photos live under `memories/<bondId>/<messageId>` | Chat photos live in the **`gs://bond-touch-galleries`** bucket at `<secret_gallery\|shared_gallery>/<senderFirebaseId>/<filename>`. `memories/` is only used by the legacy `PhoneNumberBondIdMigration`. See §5. |
| updatePreKeysInfo is `PUT bond/api/v3/bonds/{bondId}/signal/{deviceId}` | It is `@na6("bond/api/v3/signal/{deviceId}")` (PATCH) with body `af9`. See §4. |
| Chat `content` is always Signal ciphertext | Only Text (1) and NewSession (6) content is Signal ciphertext. Img/ImgSecret/Deletion content is plaintext. See §5. |

---

## 1. Firebase Storage key material (`crypto/…`)

**Location.** The default Firebase bucket (`google_storage_bucket` = `bond-touch.appspot.com`),
object path `crypto/<firebaseId>/<secretName>`.
**Writing.** Raw bytes are uploaded with `StorageReference.putStream(ByteArrayInputStream(bytes))`.
No metadata, encoding or encryption is applied.
**Reading.** The client streams the object to raw bytes. In `getPartnerSecret` those bytes are
Base64-encoded with DEFAULT flags and then decoded again with DEFAULT flags, which is a no-op
round-trip. The effective value is the raw object bytes.

### Secret names

Each name is `<base>_<decimal id>`. One-time keys are uploaded from a map `{id → bytes}`,
and each entry becomes `<base>_<id>`. Single objects pass `id` explicitly.

| Object name | Content (exact bytes) | Size |
|---|---|---|
| `identity_<registrationId>` | `IdentityKeyPair.publicKey.serialize()`, i.e. `IdentityKey` = `0x05` + 32-byte Curve25519 key | 33 B |
| `preKey_<preKeyId>` | `PreKeyRecord.keyPair.publicKey.serialize()` (`ECPublicKey`, `0x05` prefix) | 33 B |
| `signedPreKey_<signedPreKeyId>` | `SignedPreKeyRecord.keyPair.publicKey.serialize()` | 33 B |
| `signedPreKeySignature_<signedPreKeyId>` | `SignedPreKeyRecord.signature` = identity private key `calculateSignature(signedPreKeyPub.serialize())` (XEdDSA over the 33-byte serialized key) | 64 B |
| `kyberKey_<kyberPreKeyId>` | `KyberPreKeyRecord.keyPair.publicKey.serialize()` (`KEMPublicKey`, KYBER_1024, with the libsignal key-type prefix byte) | 1569 B (size from libsignal, not app code) |
| `kyberKeySignature_<kyberPreKeyId>` | `KyberPreKeyRecord.signature` = identity private key `calculateSignature(kemPub.serialize())` | 64 B |
| `lastResortKyberKey_<lastResortKyberPreKeyId>` | last-resort `KyberPreKeyRecord` public key `serialize()` | 1569 B |
| `lastResortKyberKeySignature_<lastResortKyberPreKeyId>` | its signature | 64 B |

The identity object is keyed by the **registrationId**, not by any key id.

**Public or private.** Every object is public. Private keys (identity, pre-keys, signed
pre-key, Kyber) exist only locally: in the identity prefs `E2E_ENCRYPTION`/`IdentityPrivateKey`
and in the local Room `CryptoDatabase`. **No private-key backup exists** and nothing is encrypted
with PBKDF2 or AES for Firebase. The app's only PBKDF2/AES-GCM code is `LocalCipher`, which is
local at-rest encryption: `PBKDF2withHmacSHA1And8BIT`, 10 iterations, AES-GCM, with key, salt and
IV coming from `LocalCipherInfo`. It is never applied to Signal key material on the wire.

### Alternative path when downloading partner secrets

`getPartnerSecret(primaryId, alternativeId, secretName)` first downloads
`crypto/<primaryId>/<secretName>`. On `StorageException` code `-13010` (object not found) it
retries `crypto/<alternativeId>/<secretName>` **with the same secret name**. When called from
session creation:
- `primaryId` = `Partner.firebaseId`, or `""` when null.
- `alternativeId` = `Partner.phoneNumber`. This is a legacy layout from before the
  phone-number→bondId migration.

Secret names have no alternatives.

**Evidence.**
- `out3/.../helpers/FirebaseCryptoStorageHelper.java:8-12`: the path is `"crypto/" + id + "/" + name`.
- `FirebaseCryptoStorageHelper.a` (`getStream`) and `.c` (`putStream`), lines 19-100.
- `out3/.../crypto/E2ECipher.java`:
  - `l()` uploadSecret, 1584-1640: name is `str + "_" + i`.
  - `m()` uploadSecrets, 1647-1690.
  - `g()` getPartnerSecret, 1092-1160, including the -13010 fallback.
- `out/.../crypto/E2ECipher$uploadSecrets$2$1$1.java`: name is `prefix + "_" + key`.
- `out/.../crypto/E2ECipher$sendSignalInfo$2.java`: AnonymousClass1-8 upload names and payloads.
- `out/.../crypto/E2ECipher$getPartnerSecrets$2$*$1.java`: download names, via `wk5.j(id, prefix)` = `prefix + id`.
- `out/.../crypto/LocalCipher.java`: local-only cipher.

---

## 2. Building the partner PreKeyBundle

Implemented in `E2ECipher.createSession(bondId, partnerFirebaseIdOrEmpty, partnerPhone)`:

1. Call `GET bond/api/v3/bonds/{bondId}/signal/1` and receive `j68 {registrationId, signedPreKeyId,
   nextPreKeyId, lastPreKeyId, nextKyberPreKeyId, lastKyberPreKeyId}`.
   - HTTP 404, or `registrationId == -1`, means the partner is not ready (`InvalidParameterException`).
   - `nextKyberPreKeyId == -1` means "No Kyber keys" and maps to `PartnerAppNeedsUpdate`.
2. Download these six objects in parallel. Each uses the fallback from §1.
   - `identity_<registrationId>`
   - `preKey_<nextPreKeyId>`
   - `signedPreKey_<signedPreKeyId>`
   - `signedPreKeySignature_<signedPreKeyId>`
   - `kyberKey_<nextKyberPreKeyId>`
   - `kyberKeySignature_<nextKyberPreKeyId>`

   Any `-13010` that survives the fallback means "Partner key material not fully published yet",
   which maps to `PartnerNotReady`.
3. Build the bundle:
   `PreKeyBundle(registrationId = j68.registrationId, deviceId = 1, preKeyId = j68.nextPreKeyId,
   preKey = ECPublicKey(preKey bytes), signedPreKeyId = j68.signedPreKeyId,
   signedPreKey = ECPublicKey(...), signedPreKeySignature = raw 64 B,
   identityKey = IdentityKey(bytes, 0), kyberPreKeyId = j68.nextKyberPreKeyId,
   kyberPreKey = KEMPublicKey(bytes), kyberPreKeySignature = raw)`.
   The **last-resort** Kyber key is never fetched by the initiator, and `lastPreKeyId` is not used.
4. Call `SessionBuilder(sessionStore, preKeyStore, signedPreKeyStore, identityStore,
   SignalProtocolAddress(bondId, 1)).process(bundle)`.

Swift equivalent:
- Use `PreKeyBundle(registrationId:deviceId:1, prekeyId:, prekey:, signedPrekeyId:, signedPrekey:,
  signedPrekeySignature:, identity:, kyberPrekeyId:, kyberPrekey:, kyberPrekeySignature:)`.
- Then call `processPreKeyBundle(_, for: ProtocolAddress(name: bondId, deviceId: 1), …)`.
- **UNCERTAIN:** the server probably advances `nextPreKeyId`/`nextKyberPreKeyId` when it hands
  out a bundle. Server code is not available. The client only PATCHes the `last…` ids (§4).

**Evidence.**
- `out3/.../crypto/E2ECipher$createSession$sessionResult$1.java:56-102`:
  - line 72: address `(str, 1)`, where `str` = bondId.
  - line 91: the bundle.
- `out3/.../crypto/E2ECipher$getPartnerSecrets$2.java`: six parallel jobs and argument order.
- `out4/.../repository/ChatMessageRepository$createSessionIfNeeded$2.java`: the call is
  `e2ECipher.b(bondId, partner.l ?: "", partner.b)`.
- `out/.../models/Partner.java:102-124`: `b` = phoneNumber, `k` = bondId, `l` = firebaseId.

---

## 3. SignalProtocolAddress

| Party | name | deviceId |
|---|---|---|
| Partner (SessionBuilder, SessionCipher, identity store, session store) | **`bondId`** | 1 |
| Self | No self address is constructed. Local identity comes from `IdentityKeyStore.getIdentityKeyPair()` / `getLocalRegistrationId()`. | 1 (published in URLs) |

The identity store keys partner identities by `address.name` (= bondId), via
`CryptoStoreRepository.j(name)`. A `CryptoDatabase` migration rewrote rows previously keyed by
phone number to bondId.

**Evidence.**
- `out4/.../repository/ChatMessageRepository$getE2ESessionCipher$2.java`: `SignalProtocolAddress(str, 1)`, where `str` is the bondId used for `PartnerDao.e`.
- `out4/defpackage/a41.java` case 5: `SELECT * FROM Partner WHERE bond_id = ? LIMIT 1`.
- `out/.../database/CryptoDatabase$Companion$MIGRATION_1_2$1.java`.

---

## 4. Key generation, publication and replenishment

Local state lives in SharedPreferences `E2E_ENCRYPTION`:

| Key | Meaning |
|---|---|
| `NeedKeyGenerationWithKyber` | boolean, default `true` |
| `RegistrationId` | int |
| `IdentityPublicKey` / `IdentityPrivateKey` | bytes |
| `PreKeyLastId` | int |
| `KyberPreKeyLastId` | int |
| `SignedPreKeyId` | int |
| `PreKeyLastCheckTs` | long |
| `KeyVerifyLastCheckTs` | long |
| `IdentityOwnerUid` | string |

### `initKeysIfNeeded`

This runs when the Private Space opens (`PrivateSpaceSessionPartnerViewModel.prepareSessionIfNeeded`)
and from self-heal. If `NeedKeyGenerationWithKyber == false` it returns at once. Otherwise it runs
`generateAndStoreKeys`, then `sendSignalInfo`, and on success sets the flag to `false`.

### `generateAndStoreKeys`

1. Call `GET bond/api/v3/signal/1` (self). On 404 use `j68(-1,-1,-1,-1,-1,-1)`. Any other error aborts.
2. Identity: if `RegistrationId != 0` **and** `IdentityOwnerUid` is empty or equal to the current
   Firebase UID, reuse the stored identity and registrationId. Otherwise:
   - `registrationId = KeyHelper.generateRegistrationId(true)`, uniform in `1 … 2147483646`
     (extended range, **not** ≤ 16380).
   - `IdentityKeyPair.generate()`.
   - Store both.

   Then set `IdentityOwnerUid` = the current UID.
3. Starting ids:
   - `preStart = max(last, next, PreKeyLastId, 0) + 1`, using the server values `lastPreKeyId`/`nextPreKeyId`.
   - `kyberStart = max(lastKyber, nextKyber, KyberPreKeyLastId, 0) + 1`.
   - Abort if `preStart-1+15 ≥ 0xFFFFFF` or `kyberStart-1+16 ≥ 0xFFFFFF` (`Medium.MAX_VALUE` = 16777215).
4. **15 EC one-time pre-keys**:
   - ids `(preStart + i) mod 0xFFFFFF` for `i = 0…14`.
   - `PreKeyRecord(id, ECKeyPair.generate())`.
   - Holder: `next = preStart`, `last = preStart + 14`.
5. **15 Kyber one-time pre-keys**:
   - ids `(kyberStart + i) mod 0xFFFFFF`.
   - `KEMKeyPair.generate(KYBER_1024)`, signature = `identityPriv.calculateSignature(kemPub.serialize())`.
   - Holder: `next = kyberStart`, `last = kyberStart + 14`.
6. **Last-resort Kyber key**: id = `kyberStart + 15`, KYBER_1024, signed the same way, saved with
   `storeLastResortKyberPreKey`.
7. **Signed pre-key**: id = `SecureRandom.nextInt(0xFFFFFF)` (so `0 … 16777214`; it can be 0).
   `ECKeyPair.generate()`, signature = `identityPriv.calculateSignature(spkPub.serialize())`.
8. Save prefs: `SignedPreKeyId`, `PreKeyLastId = preStart + 14`, `KyberPreKeyLastId = kyberStart + 15`.

### `sendSignalInfo`

1. Run eight uploads concurrently and wait for all of them. All are under `crypto/<ownUid>/`:
   - `identity_<regId>`
   - `preKey_<id>` ×15
   - `kyberKey_<id>` ×15
   - `kyberKeySignature_<id>` ×15
   - `lastResortKyberKey_<id>`
   - `lastResortKyberKeySignature_<id>`
   - `signedPreKey_<spkId>`
   - `signedPreKeySignature_<spkId>`
2. Then call **`updateSignalInfo`**, `@pa6` (PUT) `bond/api/v3/signal/1`, with body `ze9`:
   ```json
   {"registrationId": R, "signedPreKeyId": S,
    "nextPreKeyId": preStart, "lastPreKeyId": preStart+14,
    "nextKyberPreKeyId": kyberStart, "lastKyberPreKeyId": kyberStart+14,
    "lastResortKyberPreKeyId": kyberStart+15}
   ```

### `checkPreKeys` (replenish)

Runs on app foreground (`AppForegroundCoordinator.checkE2eMaintenance`). It only runs when
`NeedKeyGenerationWithKyber == false` and the identity owner matches.

1. Call `GET bond/api/v3/signal/1`.
2. Replenish when `next + 2 > last` for EC **or** for Kyber, meaning fewer than 3 remain.
3. Generate a new batch of 15 EC **and** 15 Kyber one-time keys.
   - EC start = `max(lastPreKeyId, nextPreKeyId, PreKeyLastId, 0) + 1`.
   - Kyber start = `max(lastKyber, nextKyber, KyberPreKeyLastId, 0) + 1`.
4. Upload them sequentially as `preKey_*`, then `kyberKey_*`, then `kyberKeySignature_*`.
5. Call **`updatePreKeysInfo`**, `@na6` (PATCH) `bond/api/v3/signal/1`, with body
   `af9 {"registrationId": R, "lastPreKeyId": newEcLast, "lastKyberPreKeyId": newKyberLast}`.
   The response is `j68`.
6. On success set `PreKeyLastId = newEcLast`, `KyberPreKeyLastId = newKyberLast`, `PreKeyLastCheckTs = now`.

The signed pre-key and last-resort key are **never rotated** except by full regeneration.

### `verifyOwnPublishedKeys` (self-heal)

1. Call `GET bond/api/v3/signal/1`. If `registrationId != -1`, download own:
   - `identity_<reg>`
   - `signedPreKey_<spk>`
   - `signedPreKeySignature_<spk>`
   - `kyberKey_<nextKyber>`
   - `kyberKeySignature_<nextKyber>`
2. The set is consistent when every object exists, the identity equals the local identity, and
   both signatures verify against that identity.
3. If not, set `NeedKeyGenerationWithKyber = true` and run `initKeysIfNeeded`. This is a full
   re-publish that keeps the identity when the owner matches.

**Evidence.**
- `out4/.../crypto/E2ECipher.java`:
  - `d()` generateAndStoreKeys.
  - `i()` initKeysIfNeeded.
  - `a()` checkPreKeys: condition `next+2 <= last` and the `va7.E` = max.
- `out3/.../crypto/E2ECipher.java`:
  - `e()` 1012-1036 (Kyber batch).
  - `f()` 1038-1052 (EC batch).
  - `k()` 1504-1575: `ze9(reg, spkId, pre.next, pre.last, kyber.next, kyber.last, lastResort.id)`.
  - `j()` 1296-1493 and `n()` 1756-1946 (verify and self-heal).
- `out/.../crypto/E2ECipher$sendSignalInfo$2.java`.
- `out4/.../crypto/E2ECipher$initKeysIfNeeded$2$job$2.java`.
- `out/defpackage/gs.java`:
  - `@pa6 updateSignalInfo`.
  - `@na6("bond/api/v3/signal/{deviceId}") updatePreKeysInfo(af9) → j68`.
- `out/defpackage/af9.java`, `ze9.java`, `j68.java`.
- `out/org/signal/libsignal/protocol/util/KeyHelper.java:8-11`.
- `out4/.../helpers/BondAppPrefs.java` (E2ePreferences).

---

## 5. Message content formats

Wire DTOs (Gson):
- `h41 {type:int, content:String}` is POSTed and answered by `i41 {id:String, timestamp:long}`.
  The client strips `"` characters from `id`.
- `e41 {id, type, content, timestamp}` is received.

`type` values come from `f41`: Text=1, Img=2, ImgSecret=3, Deletion=4, Screenshot=5, NewSession=6,
Extra=99, with `@SerializedName("1")` and so on. On receive, unknown values map to Text in
`f41.from`. The outgoing `h41.type` is a JSON number.

### Signal ciphertext envelope (used by Text, NewSession and image blobs)

```
envelope = [1 byte CiphertextMessage.getType()] || CiphertextMessage.serialize()
           type 3 = PreKeySignalMessage (PREKEY_TYPE), type 2 = SignalMessage (WHISPER_TYPE)
```

On decrypt, byte 0 equal to 3 means `PreKeySignalMessage(rest)`. **Any other value** means
`SignalMessage(rest)`.

Per content type:

| Type | `content` on the wire | Plaintext inside Signal |
|---|---|---|
| **Text (1)** | Android Base64 DEFAULT of `envelope`, sent as a String (it contains `\n` line breaks) | UTF-8 bytes of the message text. No JSON, no framing. |
| **NewSession (6)** | Android Base64 DEFAULT of `envelope` | UTF-8 of `String.format(Locale.getDefault(), "PreKeySignalMessage::NEW_SESSION::%d", System.currentTimeMillis())`. The digits are locale-formatted (**UNCERTAIN**: non-ASCII digits are possible in some locales). The receiver decrypts it and discards it. |
| **Img (2) / ImgSecret (3)** | **Plain filename** of the uploaded blob, for example `20261016_101530_123456789.tmp` (from `File.createTempFile("yyyyMMdd_HHmmss_", null)`). **Not Signal-encrypted.** | n/a. The image bytes themselves are Signal-encrypted, see below. |
| **Deletion (4)** | Plain **server id** of the message to delete. Not encrypted. | n/a |
| **Screenshot (5)** | No sender found in this build. Receive-only. | n/a |

### Image blobs

**Sending** (`sendImageChatMessageToServer` → `sendImageToRemoteStorage`):
1. Read the local file, which is local-AES-GCM encrypted, and decrypt it with `LocalCipher.f`.
   This yields the original image file bytes: JPEG at quality 70, or PNG when the bitmap has
   alpha (`ImageChooser.b`).
2. Signal-encrypt with the partner session: `blob = envelope` as above. **This is raw bytes, not Base64.**
3. Upload `blob` with `putBytes` to bucket **`gs://bond-touch-galleries`** at
   `<gallery>/<senderOwnFirebaseUid>/<filename>`.
   - `<gallery>` = `secret_gallery` for ImgSecret (3), `shared_gallery` for Img (2).
   - `<filename>` = last path segment of the local file URI.
4. POST `h41(type, filename)`, where `filename` is the last path segment returned by the upload.

**Receiving** (`downloadImages`):
1. Validate `content` with `ChatMessageRepository.k`. It must be non-blank, contain no `\`, no
   ISO control characters and no `..` segment, and the resolved path must stay under
   `<gallery>/<id>/`.
2. Download `<gallery>/<partnerFirebaseId>/<content>`. On `-13010`, retry
   `<gallery>/<partnerPhoneNumber>/<content>`.
3. Signal-decrypt the blob with the envelope rule.
4. Re-encrypt locally with `LocalCipher.d` and save the file.

If decryption fails, the app logs "Unable to decipher message. Deleting it from DB".

**Evidence.**
- `out4/.../repository/ChatMessageRepository$sendChatMessage$2.java`:
  - lines 69-73: `Base64.encode(cipher, 0)` → `h41`.
  - line 103: UTF-8 plaintext.
- `out/.../repository/ChatMessageRepository$getE2ECipheredBytes$2.java:55-58`.
- `out3/.../crypto/E2ECipherKt.java`.
- `out3/.../repository/ChatMessageRepository.java:74-86`: receive is `Base64.decode(content, 0)`, then decrypt, then UTF-8.
- `out4/.../repository/ChatMessageRepository$createSessionIfNeeded$2.java:50`.
- `out4/.../repository/ChatMessageRepository$sendImageToRemoteStorage$2.java`.
- `out4/.../repository/ChatMessageRepository$sendImageChatMessageToServer$2.java`.
- `out4/.../repository/ChatMessageRepository$sendImageMessage$2.java`.
- `out4/.../helpers/FirebaseGalleryStorageHelper*.java`: upload returns the substring after the last `/`.
- `out/.../helpers/GalleryStorageInfo.java:22-78`: primary and alternative refs via `p33.d()`.
- `out/defpackage/p33.java:41-53`: `gs://bond-touch-galleries`.
- `out4/.../helpers/GalleryType.java`: b=Secret `secret_gallery`, c=Shared `shared_gallery`.
- `out/.../helpers/FirebaseGalleryStorageHelperKt.java`.
- `out/.../helpers/ImageChooser.java:19-80`.
- `out4/.../repository/ChatMessageRepository$downloadImages$2.java` (around lines 395-480 and 720-760).
- `out4/.../repository/ChatMessageRepository$deleteImage$2.java`: `h41(Deletion, serverId)`.
- `out/defpackage/f41.java`.

---

## 6. Flows

### 6.1 Session setup

`PrivateSpaceSessionPartnerViewModel.prepareSessionIfNeeded(bondId)`:
1. Run `initKeysIfNeeded`.
2. If `CryptoStoreRepository.hasSession(bondId)`, the flow is done.
3. Otherwise call `createSessionIfNeeded`:
   - `createSession` (§2).
   - Immediately **send a NewSession (6) message** through the normal send path. Its first
     ciphertext is therefore a PreKeySignalMessage.
   - Then `syncChat`.
4. `PartnerNotReady` schedules a retry (`schedulePartnerReadyRetry`). `PartnerAppNeedsUpdate`
   is shown to the user.

The NewSession message is not stored locally (`saveChatMessage` skips type 6) and is not
counted in analytics.

### 6.2 Sending text (`sendChatMessage(type, bondId, text)`)

1. Require that the partner exists and is BONDED.
2. Insert a local row: status 0, `message` = `LocalCipher.e(text)` (local only).
3. Signal-encrypt the UTF-8 text with `SessionCipher(…, SignalProtocolAddress(bondId,1))`.
4. Base64 DEFAULT the envelope.
5. `POST bond/api/v3/bonds/{bondId}/chatmessages` with body `{"type":1,"content":"<b64>"}`.
6. The response `{id, timestamp}` is used by `updateMessageAsSent` to store the server id and
   server timestamp.

On failure the local status becomes `-1` and `PrivateSpaceMessagesSyncWorker` is scheduled.
Before sending, the UI also calls `updateUserDetailsChatInfo(bondId, connected=true, typing=false)`.

**UNCERTAIN:** the retry path `sendFailedChatMessages` posts `h41(1, chatMessage.message)`
**without Signal-encrypting it again**. The local `message` column holds
`LocalCipher.e(text)`, so unless the list was decrypted upstream, the peer receives an
undecryptable payload and silently drops it.

### 6.3 Receiving (`syncChat`, `GET bond/api/v3/bonds/chat` → `ej3`)

For each `dj3 {bondId, chatMessages, chatMissingMessages, info}`, in this order:

1. **Ack**: take the `chatMessages` entry with the greatest `timestamp`. If its id is non-empty,
   send `PUT bond/api/v3/bonds/{bondId}/chatmessages/{id}/acknowledge`. This happens **before**
   decryption.
2. **saveReceivedChatMessages**:
   - Build `SessionCipher(address bondId/1)`.
   - For Text/Img/ImgSecret entries, in list order: Text gets `Base64.decode` → envelope decrypt
     → UTF-8. A failure returns null and **the message is dropped silently**, with no session
     reset and no retry request. Img and ImgSecret keep the raw filename. Rows are inserted with
     `is_received = 1`, `timestamp = serverTimestamp = e41.timestamp`.
   - Then every **NewSession** entry is decrypted and discarded. This happens *after* the text
     entries in the same batch.
   - **Deletion** entries run `UPDATE ChatMessage SET type=4, message='' WHERE server_id IN (<e41.id of the Deletion entries>)`.
   - **Screenshot** entries run `UPDATE … screenshotDetected=1 WHERE server_id IN (<e41.id>)`.
   - **UNCERTAIN:** the receiver matches on the Deletion/Screenshot DTO's own `id`, while the
     sender puts the target id in `content`. The server presumably rewrites the id.
3. Download pending images (§5).
4. Update notifications and notify the bracelet.
5. **Bookmarks**: rows whose `server_id` is in `info.bookmarked` get `bookmarkStatus = 1`; all others get 0.
6. **`info.lastDeliveredId`**: own sent rows with status 1 and `server_timestamp ≤` the timestamp of that id become status 2 (delivered).
7. **`info.lastSeenId`**: own sent rows with status 1 or 2 and `server_timestamp ≤` that row's become status 3 (seen).
8. **`info.needsRestore` non-null**: the partner asked for a restore, so run `sendMissingChatMessages` (6.4).
9. When `chatMissingMessages` is non-empty **and** a session exists: run `handleReceivedMissingChatMessages` (6.4).
10. `checkMissingBookmarks`: if `info.bookmarked` contains server ids that are not in the local DB, send `POST bond/api/v3/bonds/{bondId}/chat/restore` (`sendNeedsRestore`).

**Seen.** When the user views the chat, the app sends
`PUT bond/api/v3/bonds/{bondId}/chatmessages/{serverId}/seen` for the latest received message and
marks local received rows up to that timestamp as status 3.

Local status values: 0 = pending, 1 = sent, 2 = delivered, 3 = seen, -1 = failed.

### 6.4 Restore (bookmarked photos only)

**Partner side (helper).** When `needsRestore` is set:
1. Load the local rows whose `server_id` is in `info.bookmarked`.
2. For bookmarked ids missing locally, send `DELETE …/chatmessages/{id}/bookmark`.
3. For each local row, **re-upload** the image: decrypt it locally, Signal-encrypt it again with
   the current session, and upload it under a new filename in the helper's own gallery path.
4. Send `PUT bond/api/v3/bonds/{bondId}/chat/restore/messages` with body `ji7 {messages: [j41]}`:
   ```json
   {"messages":[{"id":"<original serverId>","type":"<f41>","isSent":<!isReceived>,"content":"<new filename>","timestamp":<serverTimestamp>}]}
   ```
   `type` is serialized as the enum `@SerializedName` string, for example `"2"`.

**Requester side.** For each `k41 {id,type,content,timestamp,isSent}` in `chatMissingMessages`:
1. Text is Signal-decrypted, images keep the filename.
2. Insert with `is_received = !isSent` and `bookmarkStatus` = (id ∈ bookmarked).
3. Send `DELETE bond/api/v3/bonds/{bondId}/chat/restore/messages`.
4. Download the images.

**UNCERTAIN:** whether the server flips `isSent` between helper and requester. As decompiled, a
photo the helper sent would appear on the requester as `is_received = 0`.

### 6.5 Typing and presence

`PUT bond/api/v3/user/details/chatinfo` with body `jh9 {"connected": bool, "typingInfo": {"<bondId>": bool}}`.
- On a keystroke the app sends `(connected=true, typing=true)`, then after 2500 ms sends `(true, false)`.
- It sends nothing unless `LocationPreferences.e()` returns true (that getter's name is not known).
- The response DTO `eh9` has the same two fields.

**Evidence.**
- `out4/.../viewmodels/PrivateSpaceSessionPartnerViewModel$prepareSessionIfNeeded$1.java`.
- `out4/.../repository/ChatMessageRepository$createSessionIfNeeded$2.java`.
- `out4/.../repository/ChatMessageRepository.java` `u()` (syncChat):
  - line 368: ack.
  - line 385: save.
  - lines 505/522/542: delivered/seen/restore.
  - lines 595/628.
- `out4/.../repository/ChatMessageRepository$saveReceivedChatMessages$2.java:121-193`.
- `ChatMessageRepository$sendAckChatMessage$2.java`.
- `ChatMessageRepository$markReceivedMessagesAsSeen$2.java`.
- `ChatMessageRepository$sendMissingChatMessages$2.java`.
- `ChatMessageRepository$handleReceivedMissingChatMessages$2.java`.
- `ChatMessageRepository$checkMissingBookmarks$2.java`.
- `ChatMessageRepository$sendTextChatMessageToServer$2.java`.
- `ChatMessageRepository$sendFailedChatMessages$2.java:53-67`.
- `ChatMessageRepository$saveChatMessage$2.java`.
- `out4/defpackage/y.java:562` and `out/defpackage/c41.java:27` (delivered/seen SQL).
- `out/.../repository/UserDetailsRepository.java:451-516`.
- `out/.../viewmodels/ChatMessageViewModel$onTyping$1.java`.
- `out/.../viewmodels/ChatMessageViewModel$resetUnsetTypingJob$1.java` (`em0.n(2500)`).

---

## 7. Identity trust policy

`PrivateSpaceIdentityKeyStore.isTrustedIdentity(address, key, direction)`:
- `direction != SENDING` → **always trusted**, so receiving never fails on identity.
- `SENDING`:
  - No stored identity for `address.name` → trusted.
  - Stored key ≠ key → **untrusted**.
  - Stored key equal but `verified == 2` → **untrusted** ("Needs unverified approval").
  - Otherwise trusted.

`saveIdentity(address, key)`:
- No record → insert `(bondId, base64(key.serialize()), firstUse=true, now, verified=0)` and
  return `NEW_OR_UNCHANGED`.
- Same key → `NEW_OR_UNCHANGED`.
- Different key → replace with `verified = 2` if the old `verified` was 1 or 2, else 0, and
  return `REPLACED_EXISTING`.

What this means in practice:
- When the partner reinstalls with a new identity, the first message received from them
  (a PreKeySignalMessage) overwrites the stored identity. With `verified == 0` this happens
  silently and sending keeps working.
- If the stored identity differs at the moment the local side calls `SessionBuilder.process`
  (sending direction), the build fails with `UntrustedIdentityException` →
  `CreateSessionResult.Error`.
- No code was found that sets `verified = 1`.

**Evidence.**
- `out4/.../crypto/PrivateSpaceIdentityKeyStore$isTrustedIdentity$1$1.java`.
- `out3/.../crypto/PrivateSpaceIdentityKeyStore$saveIdentity$1$1.java`.
- `out4/.../crypto/PrivateSpaceIdentityKeyStore$saveIdentity$1$1.java`.
- `out/.../models/PrivateSpaceIdentityKey.java:15-27,88-103`.

---

## 8. Other interop details

- **REST verbs**: `@oa6` = POST, `@xg3` = GET, `@pa6` = PUT, `@na6` = PATCH, `@ev1` = DELETE.
  **UNCERTAIN:** the annotation→verb mapping is inferred from naming and usage. The Retrofit
  parser that maps them was not decompiled.
  - `getSelfSignalInfo`: GET `bond/api/v3/signal/{deviceId}` → `j68`.
  - `getOtherSignalInfo`: GET `bond/api/v3/bonds/{bondId}/signal/{deviceId}` → `j68`.
  - `updateSignalInfo`: `@pa6 bond/api/v3/signal/{deviceId}` (ze9) → empty.
  - `updatePreKeysInfo`: `@na6 bond/api/v3/signal/{deviceId}` (af9) → j68.
  - `sendChatMessage`: `@oa6 bond/api/v3/bonds/{bondId}/chatmessages`.
  - `ackChatMessage`, `markChatMessageAsSeen`, `bookmarkChatMessage`: `@pa6 …/chatmessages/{messageId}/{acknowledge|seen|bookmark}`.
  - `removeBookmarkChatMessage`: `@ev1 …/bookmark`.
  - `syncChat`: `@xg3 bond/api/v3/bonds/chat`.
  - Restore: `@oa6 …/chat/restore`, `@pa6 …/chat/restore/messages` (ji7), `@ev1 …/chat/restore/messages`.
  - Source: `out/defpackage/gs.java:123-290`.
- **Firebase auth**: uploads to `crypto/<uid>/…` and `<gallery>/<uid>/…` require a Firebase Auth
  session whose UID is the user's `firebaseId`. The Bond API offers
  `GET bond/api/v3/user/token/custom` (custom token).
- **Timestamps**: all are Unix epoch **milliseconds**. Local time comes from `f74.Q0().X0()`.
  Queries compare server timestamps against local `now − 259200000` (72 h), which implies
  server timestamps are also milliseconds. **UNCERTAIN**: inferred, not read from server code.
- **Registration id range**: up to 2^31−2 (`generateRegistrationId(true)`). Swift must accept
  `UInt32` values above 16380.
- **libsignal on Android**: bundles `libsignal_jni.so` with SPQR (`spqr`, "Signal PQ Ratchet V1"
  strings, `SignalMessage.getPqRatchet()`). JNI `SessionBuilder_ProcessPreKeyBundle` has no
  `usePqRatchet` argument. **UNCERTAIN**: the exact libsignal version is not embedded. Use
  LibSignalClient defaults; libsignal negotiates the PQ ratchet down when one side lacks it.
- **Kyber** is mandatory. A bundle without `nextKyberPreKeyId` is rejected (`PartnerAppNeedsUpdate`).
- **Local retention**: the chat UI shows messages from the last 72 h (`ChatMessageRepository.l()`).
  `deleteExpiredMessages` / `PrivateSpaceMessagesDeleteWorker` purge older rows. This is local only.
- **Undecryptable messages** are dropped without any protocol-level signal. The app has no
  session-reset message; NewSession (6) is only sent when this device builds a new session
  (§6.1).

---

## UNCERTAIN items (summary)

1. Whether the server advances `nextPreKeyId`/`nextKyberPreKeyId` per bundle fetch (§2).
2. Deletion/Screenshot: the sender puts the target id in `content`, but the receiver uses the
   DTO `id`. The server presumably rewrites it (§6.3).
3. The `sendFailedChatMessages` retry posts the local `message` column as `content` without
   Signal-encrypting it again (§6.2).
4. Restore `isSent` semantics between helper and requester (§6.4).
5. HTTP verb mapping of the obfuscated Retrofit annotations (§8).
6. Timestamp unit (ms) is inferred (§8).
7. NewSession plaintext digits are formatted with `Locale.getDefault()` (§5).
8. The exact libsignal version on Android (§8).
9. The KEM public key size (1569 B) and signature size (64 B) come from libsignal, not app code (§1).
10. No Screenshot (5) sender exists in this build. The `LocationPreferences.e()` gate on typing info is unnamed (§6.5).
