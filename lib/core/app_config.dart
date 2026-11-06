/// core/app_config.dart — build-time and compile-time configuration knobs.
///
/// Both values can be overridden at build time without touching code:
///
///   flutter build apk --dart-define=BACKEND_BASE_URL=https://staging.example.com
///   flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=1234-abc.apps.googleusercontent.com
///
/// BACKEND_BASE_URL points at the মুক্তিবেগ game server (the same box that
/// runs SSC Quest / SSC Bookshelf). It serves:
///   GET  /api/freescanner/config  — the remote ad configuration
///   POST /api/freescanner/auth/google/token — optional Google sign-in sync
///
/// GOOGLE_SERVER_CLIENT_ID is the *Web* OAuth client id of the Google Cloud
/// project whose tokens the backend accepts (the backend's GOOGLE_CLIENT_ID).
/// Leave it empty to disable the optional sign-in feature — scanning, OCR and
/// exports work fully offline without it.
class AppConfig {
  AppConfig._();

  static const String appName = 'FreeScanner';

  /// Backend base URL (no trailing slash).
  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'https://game-api.muktibeg.com',
  );

  /// Google *Web* client id used to mint OpenID id_tokens for the backend.
  /// Empty ⇒ the sign-in tile is hidden.
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );

  /// Fallback ad unit ids (Google's official TEST units — safe to ship and
  /// required by AdMob policy during development). The backend config usually
  /// supplies its own ids; these are used only if the backend is unreachable.
  static const String testBannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';
  static const String testInterstitialAdUnitId =
      'ca-app-pub-3940256099942544/1033173712';
  static const String testRewardedAdUnitId =
      'ca-app-pub-3940256099942544/5224354917';

  /// The EXACT disclaimer copy required whenever Bengali OCR is selected.
  static const String bengaliOcrDisclaimer =
      'Bengali OCR is currently in Beta. Accuracy may vary and spelling '
      'errors might occur.';

  /// Remote-config refresh cadence.
  static const Duration configRefreshInterval = Duration(minutes: 15);

  /// Cap the longest side of any processed page (filters / rotation) to keep
  /// memory bounded on low-end devices while staying crisp in PDFs.
  static const int maxPageDimension = 3200;

  /// JPEG quality for processed pages and PDF embedding.
  static const int jpegQuality = 90;
}
