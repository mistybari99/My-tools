# Android wrapper for BOS (X5): what it is, what is built, how to build it

Status: **scaffold only, not built, not run.** No APK was made and no device was tested. The PWA works without any of this.

## Why a wrapper at all
Google ML Kit (barcode, text recognition, image labels) is a native Android SDK. A plain web page cannot call it. The web app
therefore uses the best web equivalents (BarcodeDetector, ZXing, Tesseract.js; see the table in the X5 report), and an Android
wrapper can call ML Kit through a small bridge when the owner wants the Google engines.

## What is in the repository
| Path | What it is |
|---|---|
| `android/capacitor.config.json` | Capacitor config. `webDir` is `../web`, so the wrapper loads the same app. HTTPS scheme, no cleartext. |
| `android/package.json` | Pinned versions: `@capacitor/core|android|cli` 8.5.2 and `@capacitor-mlkit/barcode-scanning|text-recognition|image-labeling` 8.2.1 (published 2026-09; @capacitor 8.5.3 was too new to pin). |
| `android/.gitignore` | Keeps `node_modules`, the generated native project (`android/android`), APK/AAB and keystores out of git. |
| `web/scan_native.js` | The JS bridge `window.BOS_SCAN_NATIVE`: `available()`, `barcodeScan()`, `textFromImage()`, `labelsFromImage()`. In a browser it reports `not_native` and does nothing. |
| `web/scan.js` | Chooses the engine: inside the wrapper the native scanner is preferred (`caps().native`), in the browser the web engines are used. |

The bridge calls only: `BarcodeScanner.scan`, `TextRecognition.processImage({path})`, `ImageLabeling.processImage({path, confidenceThreshold})`.
These names come from the published `@capacitor-mlkit/*` 8.2.1 type definitions. They are not exercised by any test in this repository.

## Steps for the owner or a developer (not executed here)
Prerequisites: Node 20 or newer, Android Studio with an SDK, Java 17, a Google account for the Play Console (for Play Store only).

1. `cd android && npm install`
2. Set your own app id in `capacitor.config.json` (`appId`), for example `com.yourcompany.bos`. The placeholder `com.example.bos` must be changed before any release.
3. `npx cap add android` (creates `android/android`, which is ignored by git)
4. `npx cap sync android` (copies `web/` into the wrapper, including `web/vendor/`)
5. Add the camera and internet permissions to `android/android/app/src/main/AndroidManifest.xml` if the plugin install did not add them (`CAMERA`, `INTERNET`). Check the plugin README for any extra manifest entry.
6. `npx cap open android`, let Gradle sync, then Build > Generate Signed App Bundle (or APK) with your own keystore. Keep the keystore out of git.
7. Install on a test phone, then run Settings > Camera & Recognition > Run self-test. Record the result in `docs/BUILD-LOG.md`.

## Alternatives to a Capacitor APK (honest comparison)
- **Chrome WebAPK / "Install app"**: no APK, uses the PWA as-is. It can use the browser's BarcodeDetector if the phone's Chrome has it; it cannot use ML Kit. This is the cheapest path.
- **Trusted Web Activity (TWA)**: a thin Android shell that opens the PWA full screen. Same engines as Chrome (no ML Kit). Needs Digital Asset Links on the site.
- **Capacitor (this folder)**: only route that can call ML Kit. Needs a build machine and a Play account for distribution. Each ML Kit plugin adds Google Play services requirements; test on the lowest phone the business uses.
- **Play Store vs side-loading**: side-loading an APK avoids the Play account; Play distribution needs a developer account and review. Both need the owner to decide.

## Not decided here
- The app id, the signing key, who holds it, and whether the APK is distributed through the Play Store.
- Whether ML Kit models download on Wi-Fi only (Play services controls the model download; check the plugin notes on the target phone).
- Whether this wrapper is needed at all: the web engines may be enough once tested on the owner's phones (see the X5 report).
