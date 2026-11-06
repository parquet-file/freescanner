# FreeScanner — Document Scanner & OCR

A **100% free, on-device** document scanner for Android (Flutter). Scan
documents with Google's ML Kit Document Scanner (automatic edge detection,
cropping, perspective correction), apply CamScanner-style magic filters,
extract text with **offline OCR (English via ML Kit, Bengali via Tesseract)**
and export multi-page PDFs — all without any cloud processing.

| | |
|---|---|
| **Package id** | `com.muktibeg.freescanner` |
| **Status** | v1.0.0 — CI builds APK + AAB on every push, publishes Releases on `v*` tags |
| **Backend** | [gameserver](https://github.com/atomicmass-wave/gameserver) — remote ad switch + optional Google sign-in (`/api/freescanner/*`) |

---

## Features

- **Document scanning** — `google_mlkit_document_scanner`: automatic edge
  detection, cropping, perspective correction, built-in cleanup modes,
  multi-page sessions (up to 10 pages) and gallery import.
- **Magic filters** — Original · Magic Color (per-channel auto-levels +
  saturation) · B&W (adaptive threshold via integral image — great for text)
  · Lighten · Sharp Color. Filters + rotation are rendered to a derived JPEG;
  the original scan is never modified.
- **OCR, fully offline**
  - **English** — `google_mlkit_text_recognition` (Latin): high accuracy,
    on-device.
  - **Bengali** — `flutter_tesseract_ocr` with bundled `ben+eng` traineddata.
    *Beta*: selecting Bengali always shows the disclaimer
    *"Bengali OCR is currently in Beta. Accuracy may vary and spelling errors
    might occur."* before any recognition runs.
- **Local storage & export** — documents live in app-private storage
  (`meta.json` + JPEGs + OCR text files). Export as multi-page PDF (page
  sized to each scan's aspect ratio, capped at A4) or share single pages.
- **Monetization (remote-controlled)** — Google AdMob banner (home), export
  interstitial (rate-limited) and an opt-in rewarded ad. **Everything is off
  by default** — see [Ad logic](#ad-logic--the-backend-switch).
- **Optional Google sign-in** — same architecture as SSC Quest / SSC
  Bookshelf (Google id_token → backend JWT). FreeScanner is local-first:
  sign-in is never required for any feature.

## Repository layout

```
lib/
  core/            constants (backend URL, ad ids, disclaimer text), theme, helpers
  data/
    models/        RemoteAppConfig, MagicFilter, ScannedPage/Document (pure)
    repositories/  DocumentRepository (filesystem), RemoteConfigRepository (http+cache)
  services/        scanner, OCR engines, filter math, PDF, AdMob, auth
  viewmodels/      Settings, Library, Document, OCR (Provider / MVVM)
  views/           Home, Document editor, OCR screen, Settings, widgets
android/           full Android project (AGP 9.1.0 · Kotlin 2.4.0 · compileSdk 36)
assets/tessdata/   eng + ben traineddata (bundled, offline)
test/              unit tests (config parser, ad policy, filter math, models)
.github/workflows/build.yml   CI: analyze → test → APK → AAB → Release
```

## CI: building the APK / AAB

Every push to `main` (and every PR) runs
[`build.yml`](.github/workflows/build.yml):

1. `flutter analyze` + `flutter test`
2. `flutter build apk --release` → uploaded as artifact `freescanner-apk`
3. `flutter build appbundle --release` → uploaded as artifact `freescanner-aab`

Pushing a **tag** `v*` (e.g. `v1.0.1`) additionally creates a **GitHub
Release** with both binaries attached and their SHA-256 checksums:

```bash
git tag v1.0.0 && git push origin v1.0.0
```

### Release signing in CI

Without secrets the builds are **debug-signed** (installable for testing, not
uploadable to Play). To sign with your upload keystore:

```bash
# 1. Generate a keystore (once — keep it safe & secret forever):
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA \
  -keysize 2048 -validity 10000 -alias freescanner

# 2. Add four repository secrets (Settings → Secrets and variables → Actions):
#    ANDROID_KEYSTORE_BASE64     base64 -w0 upload-keystore.jks
#    ANDROID_KEYSTORE_PASSWORD   <keystore password>
#    ANDROID_KEY_ALIAS           freescanner
#    ANDROID_KEY_PASSWORD        <key password>
```

From then on every APK/AAB (and GitHub Release) is signed with that key.
Local builds can alternatively use `android/key.properties` (gitignored) —
see the comments in `android/app/build.gradle.kts`.

## Ad logic — the backend switch

The app fetches `GET https://game-api.muktibeg.com/api/freescanner/config`
at launch, on resume and every 15 minutes (offline → last cached value,
default **ads OFF**):

```json
{
  "ok": true,
  "config": {
    "ads_master_switch": false,
    "isAdEnabled": false,
    "ad_units": { "banner": {…}, "interstitial": {…}, "rewarded": {…} },
    "interstitial": { "on_export_pdf": true, "on_export_image": true,
                      "min_gap_seconds": 90 },
    "policies": { "privacy": "…", "delete_account": "…" }
  }
}
```

- `ads_master_switch` / `isAdEnabled` **false (default)** → the app never
  initialises the AdMob SDK; no banner, no interstitial, no rewarded ad.
- Flip it to `true` in `freescanner_config.js` in the gameserver repo and
  redeploy → on the next config fetch the app shows the banner, an
  interstitial on **Save as PDF / Export** (respecting `min_gap_seconds`)
  and the opt-in rewarded ad in Settings.
- A minimal `GET /api/freescanner/ads` endpoint also exists that returns
  exactly `{"isAdEnabled": false}`.

> **AdMob setup (before shipping ads to production):** the manifest currently
> carries Google's TEST app id and the config carries TEST ad-unit ids —
> fine for development, NOT for production monetization. Create a FreeScanner
> app + ad units in your AdMob console, then (1) replace the
> `com.google.android.gms.ads.APPLICATION_ID` meta-data in
> `android/app/src/main/AndroidManifest.xml` with your real app id
> (`ca-app-pub-…~…`) and (2) replace the ids in `freescanner_config.js`.
> Google requires real ids in production; test ids must never ship.

## Optional Google sign-in

Build with your Web OAuth client id (the same `GOOGLE_CLIENT_ID` the
gameserver verifies):

```bash
flutter build apk --release \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=<id>.apps.googleusercontent.com
```

Flow: Google Sign-In → OpenID `id_token` → `POST /api/freescanner/auth/google/token`
→ app-scoped JWT (stored locally, re-validated against `GET /api/freescanner/user`)
→ `POST /api/freescanner/account/delete` for the Play-compliance deletion
path. The backend stores only the account identity — scans and OCR results
never leave the device. Without the dart-define the sign-in tile is simply
hidden.

## Local development

```bash
flutter pub get
flutter test          # unit tests (no device needed)
flutter run           # debug on a connected device/emulator
flutter build apk --release
flutter build appbundle --release
```

Requirements: Flutter **3.38.1+** (CI pins 3.47.9), Java 17+ (CI uses 21),
Android SDK 36. The Gradle wrapper is injected by the Flutter tool on first
build (it is intentionally gitignored, matching the Flutter template).

### Backend for local testing

Point the app at a local gameserver:

```bash
flutter run --dart-define=BACKEND_BASE_URL=http://10.0.2.2:8080
```

## License / privacy notes

- No analytics, no crash-reporting SDKs, no tracking. The only network calls
  are the remote ad config, the optional sign-in exchange, and (when enabled)
  AdMob.
- Scans, filters, OCR text and PDFs stay in app-private storage and are
  removable by deleting documents in-app (or uninstalling).
