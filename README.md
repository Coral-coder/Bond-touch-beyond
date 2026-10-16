# Bond-touch-beyond

TestFlight: commit with `*u` in the subject to upload, `*b` to archive only. See `.github/workflows/ios-testflight.yml`.

Android XAPK: Actions → Download Bond Touch XAPK → Run workflow fetches `com.impossible.bondtouch` from APKPure (default versionCode 490, armeabi-v7a, SDK 29; clear the version code for the latest) as an artifact, optionally a release. See `.github/workflows/download-xapk.yml`.
