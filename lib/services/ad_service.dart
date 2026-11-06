import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/app_config.dart' as app_config;
import '../data/models/remote_app_config.dart';
import 'ad_policy.dart';

/// services/ad_service.dart — every AdMob surface of the app, wrapped around
/// the remote `ads_master_switch`.
///
///   * [updateConfig] is called on startup, on resume and every 15 minutes.
///     When the switch is OFF nothing below ever initialises the ad SDK —
///     the app stays 100% ad-free.
///   * When ON: a banner on the home screen, an interstitial on
///     "Save as PDF" / "Export" (rate-limited by min_gap_seconds) and an
///     opt-in rewarded ad in Settings ("Support development").
class AdService {
  AdService({@visibleForTesting Duration? stubDelay}) : _stubDelay = stubDelay;

  /// Allows tests / non-AdMob environments to skip SDK calls.
  final Duration? _stubDelay;

  RemoteAppConfig _config = RemoteAppConfig.fallback;
  AdPolicy _policy = AdPolicy(RemoteAppConfig.fallback);

  bool _initialized = false;
  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  bool _loadingInterstitial = false;
  bool _loadingRewarded = false;

  AdPolicy get policy => _policy;

  /// Ad unit ids actually used (backend id, else built-in Google TEST unit).
  String get bannerAdUnitId =>
      _config.banner.resolve(app_config.AppConfig.testBannerAdUnitId);
  String get interstitialAdUnitId =>
      _config.interstitial.resolve(app_config.AppConfig.testInterstitialAdUnitId);
  String get rewardedAdUnitId =>
      _config.rewarded.resolve(app_config.AppConfig.testRewardedAdUnitId);

  /// Called whenever the remote config (re)loads.
  Future<void> updateConfig(RemoteAppConfig config) async {
    _config = config;
    if (!config.adsEnabled) {
      // Kill switch: drop everything. The SDK stays initialised (harmless)
      // but no ad object survives.
      _disposeAd(_interstitial);
      _interstitial = null;
      _disposeAd(_rewarded);
      _rewarded = null;
      _policy = AdPolicy(config);
      return;
    }
    if (!_initialized) {
      await _initSdk();
    }
    _policy = AdPolicy(config);
    _preloadInterstitial();
    _preloadRewarded();
  }

  Future<void> _initSdk() async {
    if (_stubDelay != null) {
      await Future<void>.delayed(_stubDelay);
      _initialized = true;
      return;
    }
    await MobileAds.instance.initialize();
    _initialized = true;
  }

  bool get _useRealSdk => _stubDelay == null;

  // ---- banner --------------------------------------------------------------

  /// Builds a home-screen banner, or null when ads are off (widget then
  /// renders nothing at all).
  BannerAd? createBanner({void Function()? onLoaded, void Function()? onFailed}) {
    if (!_policy.bannerAllowed || !_useRealSdk) return null;
    return BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => onLoaded?.call(),
        onAdFailedToLoad: (ad, error) {
          debugPrint('banner failed: $error');
          ad.dispose();
          onFailed?.call();
        },
      ),
    )..load();
  }

  // ---- interstitial --------------------------------------------------------

  void _preloadInterstitial() {
    if (!_useRealSdk || _interstitial != null || _loadingInterstitial) return;
    if (!_config.adsEnabled || !_config.interstitial.usable) return;
    _loadingInterstitial = true;
    unawaited(InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitial = ad;
          _loadingInterstitial = false;
        },
        onAdFailedToLoad: (error) {
          _loadingInterstitial = false;
        },
      ),
    ));
  }

  /// Shows the export interstitial when the policy allows it.
  /// Returns true when an ad was actually presented.
  Future<bool> maybeShowInterstitial(InterstitialTrigger trigger) async {
    if (!_policy.shouldShowInterstitial(trigger)) return false;
    final ad = _interstitial;
    if (ad == null) {
      _preloadInterstitial();
      return false;
    }
    _interstitial = null;
    _policy = _policy.afterInterstitialShown();

    final dismissed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        unawaited(a.dispose());
        if (!dismissed.isCompleted) dismissed.complete();
      },
      onAdFailedToShowFullScreenContent: (a, error) {
        unawaited(a.dispose());
        if (!dismissed.isCompleted) dismissed.complete();
      },
    );
    await ad.show();
    // Let the user finish watching before the export flow continues.
    await dismissed.future.timeout(const Duration(seconds: 90), onTimeout: () {
      unawaited(ad.dispose());
    });
    _preloadInterstitial();
    return true;
  }

  // ---- rewarded ------------------------------------------------------------

  void _preloadRewarded() {
    if (!_useRealSdk || _rewarded != null || _loadingRewarded) return;
    if (!_config.adsEnabled || !_config.rewarded.usable) return;
    _loadingRewarded = true;
    unawaited(RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewarded = ad;
          _loadingRewarded = false;
        },
        onAdFailedToLoad: (error) {
          _loadingRewarded = false;
        },
      ),
    ));
  }

  /// Opt-in rewarded ad (Settings → "Support development"). [onRewardEarned]
  /// fires once the user completes the view.
  Future<bool> showRewarded({VoidCallback? onRewardEarned}) async {
    if (!_useRealSdk) return false;
    final ad = _rewarded;
    if (ad == null) {
      _preloadRewarded();
      return false;
    }
    _rewarded = null;
    final finished = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        unawaited(a.dispose());
        if (!finished.isCompleted) finished.complete();
      },
      onAdFailedToShowFullScreenContent: (a, error) {
        unawaited(a.dispose());
        if (!finished.isCompleted) finished.complete();
      },
    );
    await ad.show(
      onUserEarnedReward: (AdWithoutView shownAd, RewardItem reward) {
        onRewardEarned?.call();
      },
    );
    await finished.future.timeout(const Duration(seconds: 180), onTimeout: () {
      unawaited(ad.dispose());
    });
    _preloadRewarded();
    return true;
  }

  void dispose() {
    _disposeAd(_interstitial);
    _interstitial = null;
    _disposeAd(_rewarded);
    _rewarded = null;
  }

  /// Disposal must never throw or block the config path.
  void _disposeAd(Ad? ad) {
    if (ad != null) unawaited(ad.dispose());
  }
}
