import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models/remote_app_config.dart';
import '../data/repositories/remote_config_repository.dart';
import '../services/ad_service.dart';
import '../services/auth_service.dart';
import '../core/app_config.dart' as app_config;

/// viewmodels/settings_viewmodel.dart — owns the remote ad configuration and
/// the (optional) signed-in account, and pushes config changes into
/// [AdService].
///
/// Config lifecycle: fetched at startup, on app resume and every 15 minutes.
/// Failures are silent — the app falls back to the cached value (offline
/// first), which defaults to ads OFF.
class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel({
    required RemoteConfigRepository remoteConfigRepository,
    required AuthService authService,
    required AdService adService,
  })  : _configRepository = remoteConfigRepository,
        _authService = authService,
        _adService = adService;

  final RemoteConfigRepository _configRepository;
  final AuthService _authService;
  final AdService _adService;

  RemoteAppConfig _config = RemoteAppConfig.fallback;
  bool _configLoading = false;
  DateTime? _lastConfigFetchAt;
  Timer? _refreshTimer;

  AuthUser? _user;
  bool _authBusy = false;

  RemoteAppConfig get config => _config;
  bool get configLoading => _configLoading;
  DateTime? get lastConfigFetchAt => _lastConfigFetchAt;
  bool get adsEnabled => _config.adsEnabled;

  AuthUser? get user => _user;
  bool get authBusy => _authBusy;
  bool get authConfigured => _authService.isConfigured;
  AdService get adService => _adService;

  void init() {
    _config = _configRepository.cached();
    _adService.updateConfig(_config);
    notifyListeners();
    unawaited(refreshConfig());
    unawaited(_restoreSession());
    _refreshTimer = Timer.periodic(
      app_config.AppConfig.configRefreshInterval,
      (_) => unawaited(refreshConfig()),
    );
  }

  Future<void> refreshConfig() async {
    if (_configLoading) return;
    _configLoading = true;
    notifyListeners();
    try {
      final fresh = await _configRepository.fetch();
      _config = fresh;
      _lastConfigFetchAt = DateTime.now();
      await _adService.updateConfig(fresh);
      debugPrint(
        'remote config: ads=${fresh.adsEnabled} '
        '(banner=${fresh.banner.enabled}, '
        'interstitial=${fresh.interstitial.enabled}, '
        'rewarded=${fresh.rewarded.enabled})',
      );
    } catch (e) {
      // Offline / backend down: keep the cached config. Ads stay in whatever
      // state the last good fetch said — never ON by accident.
      debugPrint('config fetch failed: $e');
    } finally {
      _configLoading = false;
      notifyListeners();
    }
  }

  /// Called by the WidgetsBindingObserver on app resume.
  Future<void> onAppResumed() => refreshConfig();

  Future<void> _restoreSession() async {
    if (!_authService.isConfigured) return;
    final user = await _authService.restoreSession();
    if (user != null) {
      _user = user;
      notifyListeners();
    }
  }

  Future<void> signIn() async {
    if (_authBusy) return;
    _authBusy = true;
    notifyListeners();
    try {
      _user = await _authService.signIn();
    } finally {
      _authBusy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    if (_authBusy) return;
    _authBusy = true;
    notifyListeners();
    try {
      await _authService.signOut();
      _user = null;
    } finally {
      _authBusy = false;
      notifyListeners();
    }
  }

  Future<void> deleteAccount() async {
    if (_authBusy) return;
    _authBusy = true;
    notifyListeners();
    try {
      await _authService.deleteAccount();
      _user = null;
    } finally {
      _authBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
