# Archive: the Bond Touch cloud integration

This folder holds the code Bond Touch Beyond used to talk to **Bond Touch's own servers**:

- the Bond REST API at `api.bond-touch.com`;
- the Heart API;
- Firebase Auth and Storage for Bond's `bond-touch` project;
- the Signal chat that interoperated with the original app.

It was removed from the app. Nothing here compiles: `archive/` is not in any target's
`sources:` in `project.yml` or `uitests.yml`. It is kept for reference and so the code can
be restored.

The full description of what this code did (hosts, endpoints, JSON, sign-in, sync timing,
Signal, how original-app partners were merged with iCloud ones, and quirks) is in
[`docs/BOND_TOUCH_CLOUD.md`](../../docs/BOND_TOUCH_CLOUD.md).

> This code contains Bond's Firebase Web API key (in `Sources/Legacy/BondBackend.swift`).
> That key is restricted to the official iOS app's bundle ID. The documentation never
> repeats it.

## Contents

| Path | What it is |
|---|---|
| `Sources/Legacy/BondBackend.swift` | Constants, Firebase Identity Toolkit (email-link sign-in), the Bond API request helper, the Debug dump |
| `Sources/Legacy/BondAPI.swift` | Token refresh (securetoken), JWT helpers, typed Bond API calls |
| `Sources/Legacy/HeartAPI.swift` | Bond Heart cloud API |
| `Sources/Legacy/FirebaseStorage.swift` | Firebase Storage REST client (App Check detection) |
| `Sources/Legacy/LegacyFirebaseClient.swift` | Realtime Database REST client (dead code) |
| `Sources/ViewModels/AppModel+Legacy.swift` | The sync loop and every app-side use of the above |
| `Sources/Chat/BondChat.swift`, `Sources/Chat/SignalStore.swift` | Signal-protocol chat with the original app |
| `Sources/Views/LegacyLoginView.swift` | "Bond Touch login" screen (from Debug) |
| `Sources/Views/LegacyDataView.swift` | Unused Realtime Database settings screen |
| `ThirdParty/LibSignalClient/` | Signal's LibSignalClient **v0.86.5** Swift sources, `SignalFfi` headers and licence (AGPL-3.0) |
| `scripts/fetch-libsignal-ffi.sh` | Downloads the matching prebuilt `libsignal_ffi.a` (SHA-256 pinned). The ~100 MB archive is git-ignored and never committed |
| `removed-hunks.patch` | The lines removed from files that stayed in the app |

All of these are verbatim copies of the files at their original paths in the repository,
taken at branch `bond-cloud-final`.

## How `removed-hunks.patch` was made

It is the diff, for the files that stayed, from the commit that removed the integration
back to `bond-cloud-final`:

```sh
git diff <removal commit> bond-cloud-final -- <the files that stayed>
```

So applying it re-adds the removed code, which is the inverse of the removal. It covers:

- `project.yml` (the LibSignalClient target, include paths and linker flags);
- the "Fetch libsignal_ffi" step in `.github/workflows/*.yml`;
- every Swift file that had Bond-specific code removed.

It leaves out `WhatsNew.swift` and the docs.

## Restoring

The simplest way is to check out the full working app as it was:

```sh
git checkout bond-cloud-final
```

To put the integration back into the current code, run from the repository root:

```sh
# 1. The removed files.
cp -R archive/bond-touch-cloud/Sources/. Sources/
cp -R archive/bond-touch-cloud/ThirdParty ./
cp archive/bond-touch-cloud/scripts/fetch-libsignal-ffi.sh scripts/

# 2. The removed lines in the files that stayed (use --3way if they changed since).
git apply --3way archive/bond-touch-cloud/removed-hunks.patch

# 3. AppModel+Legacy.swift defines the Touch Language / greeting functions again.
git rm Sources/ViewModels/AppModel+Meanings.swift

# 4. NetLog was moved; the restored code expects it under Sources/Legacy (either place compiles).
# 5. Build.
scripts/fetch-libsignal-ffi.sh && xcodegen generate
```

After step 1 the copies under `archive/` can stay where they are, because they never
compile.
