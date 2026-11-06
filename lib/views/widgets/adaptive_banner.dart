import 'package:flutter/material.dart';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:provider/provider.dart';

import '../../viewmodels/settings_viewmodel.dart';

/// views/widgets/adaptive_banner.dart — the home-screen banner slot.
///
/// Renders ABSOLUTELY NOTHING unless the backend ad switch is ON: no SDK
/// initialisation, no placeholder, no reserved height.
class AdaptiveBanner extends StatefulWidget {
  const AdaptiveBanner({super.key});

  @override
  State<AdaptiveBanner> createState() => _AdaptiveBannerState();
}

class _AdaptiveBannerState extends State<AdaptiveBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _creating = false;

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  void _reconcile(SettingsViewModel settings) {
    final allowed = settings.adsEnabled && settings.config.banner.usable;
    if (!allowed) {
      _ad?.dispose();
      _ad = null;
      _loaded = false;
      _creating = false;
      return;
    }
    if (_ad == null && !_loaded && !_creating) {
      _creating = true;
      _ad = settings.adService.createBanner(
        onLoaded: () {
          if (mounted) setState(() => _loaded = true);
        },
        onFailed: () {
          if (mounted) setState(() => _loaded = false);
        },
      );
      _creating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsViewModel>();
    _reconcile(settings);
    final ad = _ad;
    if (!settings.adsEnabled || ad == null || !_loaded) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: double.infinity,
      height: AdSize.banner.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
