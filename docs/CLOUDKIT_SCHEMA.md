# CloudKit schema (Production)

TestFlight and App Store builds use CloudKit's **Production** environment. Unlike
Development, Production never creates record types on its own — so **iCloud does nothing
until this schema is deployed to Production**. That is why the first real iCloud action
(inviting a partner) spins or fails even though the app is signed in.

Container: `iCloud.com.lightwave.beyond`
Console: https://icloud.developer.apple.com/dashboard/

To unblock the **invite** you only need the `Bond` record type (below). The rest are
needed for touches, messages, presence and photos once a partner is actually on iCloud.

## Record types and fields

Field types as shown in the CloudKit console. Every type also has the built-in system
fields (recordName, createdTimestamp, …) — you don't add those.

### Bond  (the shared root record — required for invites)
| Field | Type |
|---|---|
| ownerName | String |

### Touch
| Field | Type |
|---|---|
| senderID | String |
| pattern | Int64 (List) |
| generation | Int64 |
| colorRGB | Int64 |
| endColorRGB | Int64 |
| sentAt | Date/Time |

### Heartbeat
| Field | Type |
|---|---|
| senderID | String |
| bpm | Int64 |
| sentAt | Date/Time |

### Message
| Field | Type |
|---|---|
| senderID | String |
| kind | String |
| text | String |
| colorRGB | Int64 |
| sentAt | Date/Time |
| image | Asset |

### Presence
| Field | Type |
|---|---|
| senderID | String |
| online | Int64 |
| lat | Double |
| lng | Double |
| sentAt | Date/Time |

### Profile
| Field | Type |
|---|---|
| senderID | String |
| name | String |
| colorRGB | Int64 |
| photo | Asset |
| sentAt | Date/Time |

## Deploying

1. Open the console and select container `iCloud.com.lightwave.beyond`.
2. In **Development**, Schema → Record Types → add each type and its fields above.
   (CloudKit's Development environment is where types are defined; they're then promoted
   to Production.)
3. Schema → **Deploy Schema Changes…** → target **Production** → Deploy.

Sharing uses the built-in `cloudkit.share` type, which already exists — no need to add it.
