import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_config.dart' as app_config;
import '../models/remote_app_config.dart';

/// data/repositories/remote_config_repository.dart — fetches the remote ad
/// configuration from the backend with a short timeout, and keeps the last
/// good payload cached in SharedPreferences so the app works fully offline.
class RemoteConfigRepository {
  RemoteConfigRepository({required this.prefs, http.Client? client})
      : _client = client ?? http.Client();

  static const _cacheKey = 'freescanner.remote_config.v1';

  final SharedPreferences prefs;
  final http.Client _client;

  /// Cached config from the last successful fetch (never throws).
  RemoteAppConfig cached() {
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return RemoteAppConfig.fallback;
    try {
      return RemoteAppConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return RemoteAppConfig.fallback;
    }
  }

  /// Fetches GET `<base>/api/freescanner/config`.
  ///
  /// Throws on network/HTTP errors — callers decide whether to surface or
  /// silently fall back to [cached].
  Future<RemoteAppConfig> fetch() async {
    final uri = Uri.parse(
      '${app_config.AppConfig.backendBaseUrl}/api/freescanner/config',
    );
    final response = await _client
        .get(uri, headers: {'accept': 'application/json'})
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw http.ClientException(
        'config endpoint returned HTTP ${response.statusCode}',
        uri,
      );
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes))
        as Map<String, dynamic>;
    final config = RemoteAppConfig.fromJson(body);
    await prefs.setString(_cacheKey, jsonEncode(config.toJson()));
    return config;
  }
}
