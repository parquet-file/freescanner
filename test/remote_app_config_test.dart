import 'package:flutter_test/flutter_test.dart';

import 'package:freescanner/core/app_config.dart' as app_config;
import 'package:freescanner/data/models/remote_app_config.dart';

void main() {
  group('RemoteAppConfig.fromJson', () {
    test('parses the full backend envelope', () {
      final cfg = RemoteAppConfig.fromJson(<String, dynamic>{
        'ok': true,
        'config': <String, dynamic>{
          'ads_master_switch': true,
          'isAdEnabled': true,
          'ad_units': <String, dynamic>{
            'banner': <String, dynamic>{
              'enabled': true,
              'id': 'ca-app-pub-1/banner',
            },
            'interstitial': <String, dynamic>{
              'enabled': true,
              'id': 'ca-app-pub-1/inter',
            },
            'rewarded': <String, dynamic>{
              'enabled': false,
              'id': 'ca-app-pub-1/reward',
            },
          },
          'interstitial': <String, dynamic>{
            'on_export_pdf': false,
            'on_export_image': true,
            'min_gap_seconds': 45,
          },
          'policies': <String, dynamic>{
            'privacy': 'https://example.com/privacy',
            'delete_account': 'https://example.com/delete',
          },
          'contact_email': 'support@example.com',
          'min_app_version': '1.2.0',
          'config_version': '2026-11-06',
        },
      });

      expect(cfg.adsEnabled, isTrue);
      expect(cfg.banner.id, 'ca-app-pub-1/banner');
      expect(cfg.interstitial.id, 'ca-app-pub-1/inter');
      expect(cfg.rewarded.enabled, isFalse);
      expect(cfg.interstitialOnExportPdf, isFalse);
      expect(cfg.interstitialOnExportImage, isTrue);
      expect(cfg.interstitialMinGapSeconds, 45);
      expect(cfg.privacyUrl, 'https://example.com/privacy');
      expect(cfg.deleteAccountUrl, 'https://example.com/delete');
      expect(cfg.contactEmail, 'support@example.com');
      expect(cfg.minAppVersion, '1.2.0');
      expect(cfg.configVersion, '2026-11-06');
    });

    test('ads_master_switch=false keeps the app ad-free (the shipped default)',
        () {
      final cfg = RemoteAppConfig.fromJson(<String, dynamic>{
        'ok': true,
        'config': <String, dynamic>{
          'ads_master_switch': false,
          'isAdEnabled': false,
        },
      });
      expect(cfg.adsEnabled, isFalse);
    });

    test('accepts the minimal {"isAdEnabled": false} endpoint shape', () {
      final cfg = RemoteAppConfig.fromJson(<String, dynamic>{
        'isAdEnabled': true,
      });
      expect(cfg.adsEnabled, isTrue);
      // Everything else falls back to safe defaults.
      expect(cfg.interstitialMinGapSeconds, 90);
      expect(cfg.interstitialOnExportPdf, isTrue);
    });

    test('garbage input never enables ads', () {
      final cfg = RemoteAppConfig.fromJson(<String, dynamic>{
        'ads_master_switch': 'yes please',
        'ad_units': 'broken',
        'interstitial': 42,
      });
      expect(cfg.adsEnabled, isFalse);
      expect(cfg.banner.enabled, isTrue); // unit default enabled-but-gated
      expect(cfg.banner.id, isEmpty); // no id ⇒ usable == false
      expect(cfg.banner.usable, isFalse);
    });

    test('ads_master_switch wins over the isAdEnabled alias', () {
      final cfg = RemoteAppConfig.fromJson(<String, dynamic>{
        'ads_master_switch': false,
        'isAdEnabled': true,
      });
      expect(cfg.adsEnabled, isFalse);
    });

    test('fallback is fully ad-free with Google TEST units', () {
      final fallback = RemoteAppConfig.fallback;
      expect(fallback.adsEnabled, isFalse);
      expect(fallback.banner.id, app_config.AppConfig.testBannerAdUnitId);
      expect(
        fallback.interstitial.id,
        app_config.AppConfig.testInterstitialAdUnitId,
      );
      expect(fallback.rewarded.id, app_config.AppConfig.testRewardedAdUnitId);
    });

    test('toJson round-trips through fromJson', () {
      final original = RemoteAppConfig.fromJson(<String, dynamic>{
        'config': <String, dynamic>{
          'ads_master_switch': true,
          'ad_units': <String, dynamic>{
            'banner': <String, dynamic>{'enabled': true, 'id': 'x/banner'},
          },
          'interstitial': <String, dynamic>{'min_gap_seconds': 30},
        },
      });
      final copy = RemoteAppConfig.fromJson(original.toJson());
      expect(copy.adsEnabled, original.adsEnabled);
      expect(copy.banner.id, 'x/banner');
      expect(copy.interstitialMinGapSeconds, 30);
    });
  });
}
