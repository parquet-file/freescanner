/// data/models/remote_app_config.dart — the remote-control payload from the
/// backend (GET /api/freescanner/config), plus a tolerant parser and safe
/// fallback defaults.
///
/// The backend serves (see the gameserver repo, freescanner_config.js):
///
///     {
///       "ok": true,
///       "config": {
///         "ads_master_switch": false,      // ← THE kill switch
///         "isAdEnabled": false,            // alias, same value
///         "ad_units": {
///           "banner":      { "enabled": true, "id": "ca-app-pub-…" },
///           "interstitial":{ "enabled": true, "id": "ca-app-pub-…" },
///           "rewarded":    { "enabled": true, "id": "ca-app-pub-…" }
///         },
///         "interstitial": {
///           "on_export_pdf": true,
///           "on_export_image": true,
///           "min_gap_seconds": 90
///         },
///         "policies": { "privacy": "https://…", "delete_account": "https://…" },
///         "contact_email": "support@muktibeg.com",
///         "min_app_version": "1.0.0"
///       }
///     }
///
/// The parser also accepts the raw config object without the {ok, config}
/// envelope, and the minimal {"isAdEnabled": false} shape, so the backend can
/// serve any of them without an app update.
library;

import '../../core/app_config.dart' as app_config;

class AdUnitConfig {
  const AdUnitConfig({required this.enabled, required this.id});

  final bool enabled;
  final String id;

  /// Renders ads only when the switch is on AND a real unit id exists.
  bool get usable => enabled && id.isNotEmpty;

  factory AdUnitConfig.fromJson(Map<String, dynamic> json) {
    return AdUnitConfig(
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      id: json['id'] is String ? (json['id'] as String).trim() : '',
    );
  }

  /// The unit to use: backend id when present, otherwise the built-in
  /// Google TEST unit (never an empty string — AdMob needs an id).
  String resolve(String testId) => id.isNotEmpty ? id : testId;
}

class RemoteAppConfig {
  const RemoteAppConfig({
    required this.adsEnabled,
    required this.banner,
    required this.interstitial,
    required this.rewarded,
    required this.interstitialOnExportPdf,
    required this.interstitialOnExportImage,
    required this.interstitialMinGapSeconds,
    required this.privacyUrl,
    required this.deleteAccountUrl,
    required this.contactEmail,
    required this.minAppVersion,
    this.configVersion,
  });

  /// ads_master_switch / isAdEnabled — false by default (ad-free app).
  final bool adsEnabled;

  final AdUnitConfig banner;
  final AdUnitConfig interstitial;
  final AdUnitConfig rewarded;

  final bool interstitialOnExportPdf;
  final bool interstitialOnExportImage;
  final int interstitialMinGapSeconds;

  final String privacyUrl;
  final String deleteAccountUrl;
  final String contactEmail;
  final String minAppVersion;
  final String? configVersion;

  /// The offline default: everything off, test ids on standby.
  static RemoteAppConfig get fallback => const RemoteAppConfig(
        adsEnabled: false,
        banner: AdUnitConfig(enabled: true, id: app_config.AppConfig.testBannerAdUnitId),
        interstitial: AdUnitConfig(
            enabled: true, id: app_config.AppConfig.testInterstitialAdUnitId),
        rewarded:
            AdUnitConfig(enabled: true, id: app_config.AppConfig.testRewardedAdUnitId),
        interstitialOnExportPdf: true,
        interstitialOnExportImage: true,
        interstitialMinGapSeconds: 90,
        privacyUrl: '',
        deleteAccountUrl: '',
        contactEmail: '',
        minAppVersion: '1.0.0',
      );

  /// Tolerant parser: accepts {ok, config:{…}}, the bare config {…},
  /// or the minimal {"isAdEnabled": bool} document.
  static RemoteAppConfig fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> cfg = json;
    if (json['config'] is Map<String, dynamic>) {
      cfg = json['config'] as Map<String, dynamic>;
    }

    Map<String, dynamic> units(String key) =>
        cfg[key] is Map<String, dynamic> ? cfg[key] as Map<String, dynamic> : {};
    final adUnits = units('ad_units');
    Map<String, dynamic> unit(String name) =>
        adUnits[name] is Map<String, dynamic>
            ? adUnits[name] as Map<String, dynamic>
            : <String, dynamic>{};

    Map<String, dynamic> interCfg =
        cfg['interstitial'] is Map<String, dynamic>
            ? cfg['interstitial'] as Map<String, dynamic>
            : <String, dynamic>{};

    Map<String, dynamic> policies =
        cfg['policies'] is Map<String, dynamic>
            ? cfg['policies'] as Map<String, dynamic>
            : <String, dynamic>{};

    // The switch: explicit ads_master_switch wins, then isAdEnabled alias.
    final bool adsEnabled;
    if (cfg['ads_master_switch'] is bool) {
      adsEnabled = cfg['ads_master_switch'] as bool;
    } else if (cfg['isAdEnabled'] is bool) {
      adsEnabled = cfg['isAdEnabled'] as bool;
    } else {
      adsEnabled = false;
    }

    int gap(dynamic v, int def) {
      final n = v is num ? v.toInt() : def;
      return n < 0 ? 0 : n;
    }

    final fallbackConfig = fallback;

    return RemoteAppConfig(
      adsEnabled: adsEnabled,
      banner: AdUnitConfig.fromJson(unit('banner')),
      interstitial: AdUnitConfig.fromJson(unit('interstitial')),
      rewarded: AdUnitConfig.fromJson(unit('rewarded')),
      interstitialOnExportPdf:
          interCfg['on_export_pdf'] is bool ? interCfg['on_export_pdf'] as bool : true,
      interstitialOnExportImage: interCfg['on_export_image'] is bool
          ? interCfg['on_export_image'] as bool
          : true,
      interstitialMinGapSeconds:
          gap(interCfg['min_gap_seconds'], fallbackConfig.interstitialMinGapSeconds),
      privacyUrl: policies['privacy'] is String ? policies['privacy'] as String : '',
      deleteAccountUrl:
          policies['delete_account'] is String ? policies['delete_account'] as String : '',
      contactEmail: cfg['contact_email'] is String ? cfg['contact_email'] as String : '',
      minAppVersion:
          cfg['min_app_version'] is String ? cfg['min_app_version'] as String : '1.0.0',
      configVersion: cfg['config_version'] is String
          ? cfg['config_version'] as String
          : null,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'ads_master_switch': adsEnabled,
        'isAdEnabled': adsEnabled,
        'ad_units': {
          'banner': {'enabled': banner.enabled, 'id': banner.id},
          'interstitial': {'enabled': interstitial.enabled, 'id': interstitial.id},
          'rewarded': {'enabled': rewarded.enabled, 'id': rewarded.id},
        },
        'interstitial': {
          'on_export_pdf': interstitialOnExportPdf,
          'on_export_image': interstitialOnExportImage,
          'min_gap_seconds': interstitialMinGapSeconds,
        },
        'policies': {'privacy': privacyUrl, 'delete_account': deleteAccountUrl},
        'contact_email': contactEmail,
        'min_app_version': minAppVersion,
      };
}
