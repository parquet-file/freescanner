import 'package:flutter_test/flutter_test.dart';

import 'package:freescanner/data/models/remote_app_config.dart';
import 'package:freescanner/services/ad_policy.dart';

RemoteAppConfig _config({
  required bool adsEnabled,
  bool interstitialEnabled = true,
  bool onExportPdf = true,
  bool onExportImage = true,
  int gap = 90,
}) =>
    RemoteAppConfig.fromJson(<String, dynamic>{
      'config': <String, dynamic>{
        'ads_master_switch': adsEnabled,
        'ad_units': <String, dynamic>{
          'banner': <String, dynamic>{
            'enabled': true,
            'id': 'ca-app-pub-1/banner',
          },
          'interstitial': <String, dynamic>{
            'enabled': interstitialEnabled,
            'id': 'ca-app-pub-1/inter',
          },
          'rewarded': <String, dynamic>{
            'enabled': true,
            'id': 'ca-app-pub-1/reward',
          },
        },
        'interstitial': <String, dynamic>{
          'on_export_pdf': onExportPdf,
          'on_export_image': onExportImage,
          'min_gap_seconds': gap,
        },
      },
    });

void main() {
  // Frozen clock: 2026-11-06 10:00 UTC.
  final now = DateTime.utc(2026, 11, 6, 10);

  group('AdPolicy banner / rewarded', () {
    test('master switch off blocks everything', () {
      final policy = AdPolicy(_config(adsEnabled: false));
      expect(policy.bannerAllowed, isFalse);
      expect(policy.rewardedAllowed, isFalse);
      expect(
        policy.shouldShowInterstitial(InterstitialTrigger.exportPdf),
        isFalse,
      );
    });

    test('master switch on allows banner and rewarded', () {
      final policy = AdPolicy(_config(adsEnabled: true), now: () => now);
      expect(policy.bannerAllowed, isTrue);
      expect(policy.rewardedAllowed, isTrue);
    });
  });

  group('AdPolicy interstitial gating', () {
    test('shows on export-pdf when everything is enabled', () {
      final policy = AdPolicy(_config(adsEnabled: true), now: () => now);
      expect(
        policy.shouldShowInterstitial(InterstitialTrigger.exportPdf),
        isTrue,
      );
    });

    test('per-trigger switch is honoured', () {
      final policy = AdPolicy(
        _config(adsEnabled: true, onExportPdf: false),
        now: () => now,
      );
      expect(
        policy.shouldShowInterstitial(InterstitialTrigger.exportPdf),
        isFalse,
      );
      expect(
        policy.shouldShowInterstitial(InterstitialTrigger.exportImage),
        isTrue,
      );
    });

    test('unit disabled blocks the ad', () {
      final policy = AdPolicy(
        _config(adsEnabled: true, interstitialEnabled: false),
        now: () => now,
      );
      expect(
        policy.shouldShowInterstitial(InterstitialTrigger.exportPdf),
        isFalse,
      );
    });

    test('min gap enforces spacing between interstitials', () {
      final shownAt = now.subtract(const Duration(seconds: 30));
      final tooSoon = AdPolicy(
        _config(adsEnabled: true, gap: 90),
        now: () => now,
        lastInterstitialAt: shownAt,
      );
      expect(
        tooSoon.shouldShowInterstitial(InterstitialTrigger.exportPdf),
        isFalse,
      );

      final longAgo = AdPolicy(
        _config(adsEnabled: true, gap: 90),
        now: () => now,
        lastInterstitialAt: now.subtract(const Duration(seconds: 91)),
      );
      expect(
        longAgo.shouldShowInterstitial(InterstitialTrigger.exportPdf),
        isTrue,
      );
    });

    test('afterInterstitialShown records the timestamp', () {
      final policy = AdPolicy(
        _config(adsEnabled: true),
        now: () => now,
      );
      final next = policy.afterInterstitialShown();
      expect(next.lastInterstitialAt, now);
      // And the fresh policy is now inside the gap window.
      expect(
        next.shouldShowInterstitial(InterstitialTrigger.exportPdf),
        isFalse,
      );
    });
  });

  group('AdPolicy without any ad unit id', () {
    test('empty interstitial id never shows', () {
      final cfg = RemoteAppConfig.fromJson(<String, dynamic>{
        'ads_master_switch': true,
        'ad_units': <String, dynamic>{
          'interstitial': <String, dynamic>{'enabled': true, 'id': ''},
        },
      });
      final policy = AdPolicy(cfg, now: () => now);
      expect(
        policy.shouldShowInterstitial(InterstitialTrigger.exportPdf),
        isFalse,
      );
    });
  });
}
