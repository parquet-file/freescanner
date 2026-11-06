import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'core/app_theme.dart';
import 'viewmodels/settings_viewmodel.dart';
import 'views/home_screen.dart';

/// app.dart — the MaterialApp shell.
class FreeScannerApp extends StatelessWidget {
  const FreeScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FreeScanner',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}

/// Sits directly under the providers. Refreshes the remote ad config every
/// time the app returns to the foreground (same behaviour as SSC Bookshelf:
/// launch + resume + every 15 minutes).
class AppLifecycleHost extends StatefulWidget {
  const AppLifecycleHost({super.key, required this.child});

  final Widget child;

  @override
  State<AppLifecycleHost> createState() => _AppLifecycleHostState();
}

class _AppLifecycleHostState extends State<AppLifecycleHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Unawaited on purpose — the resume must never block the UI.
      context.read<SettingsViewModel>().onAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
