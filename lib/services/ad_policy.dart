import '../data/models/remote_app_config.dart';

/// services/ad_policy.dart — pure decisions about IF and WHEN an ad may show.
/// Kept free of any plugin imports so it is fully unit-testable.
///
/// Rules (per the product spec):
///   * The backend `ads_master_switch` / `isAdEnabled` is THE kill switch.
///     false ⇒ no banner, no interstitial, no rewarded — the app is ad-free.
///   * Interstitials fire on "Save as PDF" / "Export" taps only, never while
///     scanning or editing, and never more often than once per
///     `min_gap_seconds` (AdMob policy safety valve).
class AdPolicy {
  const AdPolicy(this.config, {DateTime Function()? now, this.lastInterstitialAt})
      : _now = now;

  final RemoteAppConfig config;

  /// Injectable clock for tests.
  final DateTime Function()? _now;

  /// Last interstitial shown in this session (null ⇒ none yet).
  final DateTime? lastInterstitialAt;

  DateTime get _currentTime => _now?.call() ?? DateTime.now();

  /// Banner on the home screen.
  bool get bannerAllowed =>
      config.adsEnabled && config.banner.usable;

  /// Rewarded "support the developer" ad.
  bool get rewardedAllowed =>
      config.adsEnabled && config.rewarded.usable;

  /// Whether the given interstitial trigger is enabled at all.
  bool triggerEnabled(InterstitialTrigger trigger) {
    switch (trigger) {
      case InterstitialTrigger.exportPdf:
        return config.interstitialOnExportPdf;
      case InterstitialTrigger.exportImage:
        return config.interstitialOnExportImage;
    }
  }

  /// Full interstitial gate: master switch + unit + trigger + min gap.
  bool shouldShowInterstitial(InterstitialTrigger trigger) {
    if (!config.adsEnabled || !config.interstitial.usable) return false;
    if (!triggerEnabled(trigger)) return false;
    final last = lastInterstitialAt;
    if (last == null) return true;
    return _currentTime.difference(last).inSeconds >=
        config.interstitialMinGapSeconds;
  }

  /// The policy that applies after showing an interstitial now.
  AdPolicy afterInterstitialShown() =>
      AdPolicy(config, now: _now, lastInterstitialAt: _currentTime);
}

enum InterstitialTrigger {
  exportPdf('export_pdf'),
  exportImage('export_image');

  const InterstitialTrigger(this.key);
  final String key;
}
