import 'package:flutter/material.dart';

import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/repositories/document_repository.dart';
import 'data/repositories/remote_config_repository.dart';
import 'services/ad_service.dart';
import 'services/auth_service.dart';
import 'viewmodels/library_viewmodel.dart';
import 'viewmodels/settings_viewmodel.dart';

/// main.dart — bootstraps the singletons (repositories + services), wires
/// them into the view models and starts the app.
///
/// Everything is local-first: no backend call blocks startup. The remote ad
/// config is fetched in the background; until it answers the app runs with
/// the cached value (default: ads OFF).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final docsDir = await getApplicationDocumentsDirectory();

  final documentRepository = DocumentRepository(baseDir: docsDir);
  final remoteConfigRepository = RemoteConfigRepository(prefs: prefs);
  final adService = AdService();
  final authService = AuthService(prefs: prefs);

  runApp(
    MultiProvider(
      providers: [
        Provider<DocumentRepository>.value(value: documentRepository),
        ChangeNotifierProvider<SettingsViewModel>(
          create: (_) => SettingsViewModel(
            remoteConfigRepository: remoteConfigRepository,
            authService: authService,
            adService: adService,
          )..init(),
        ),
        ChangeNotifierProvider<LibraryViewModel>(
          create: (_) => LibraryViewModel(
            repository: documentRepository,
          )..load(),
        ),
      ],
      child: const AppLifecycleHost(child: FreeScannerApp()),
    ),
  );
}
