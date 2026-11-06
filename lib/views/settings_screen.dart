import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart' as app_config;
import '../services/auth_service.dart';
import '../viewmodels/settings_viewmodel.dart';

/// views/settings_screen.dart — account (optional Google sign-in synced with
/// the backend), the ad switch status, "support development" rewarded ad and
/// about/policies.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _openUrl(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.isAbsolute) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Link unavailable in this build.')),
      );
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsViewModel>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ---- Account -----------------------------------------------------
          _SectionHeader('Account (optional)'),
          if (!settings.authConfigured)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                'Sign-in is disabled in this build. Everything in FreeScanner '
                'works offline without an account.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else if (settings.user == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: FilledButton.tonalIcon(
                onPressed: settings.authBusy ? null : () => _signIn(context, settings),
                icon: settings.authBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: const Text('Sign in with Google'),
              ),
            )
          else
            _AccountTile(
              user: settings.user!,
              onSignOut: () => _signOut(context, settings),
              onDelete: () => _deleteAccount(context, settings),
            ),
          const Divider(),

          // ---- Ads ---------------------------------------------------------
          _SectionHeader('Ads'),
          ListTile(
            leading: Icon(
              settings.adsEnabled
                  ? Icons.campaign_outlined
                  : Icons.block_outlined,
            ),
            title: Text(settings.adsEnabled ? 'Ads enabled' : 'Ad-free'),
            subtitle: Text(
              settings.adsEnabled
                  ? 'Controlled by the remote server switch. Banner on the '
                    'home screen, interstitial on export (rate-limited).'
                  : 'The remote switch is OFF — no ads are shown anywhere. '
                    'Flip ads_master_switch in the backend config to enable.',
            ),
            trailing: settings.configLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          if (settings.adsEnabled && settings.config.rewarded.usable)
            ListTile(
              leading: const Icon(Icons.favorite_outline),
              title: const Text('Support development'),
              subtitle: const Text('Watch a short rewarded ad. Thank you!'),
              onTap: () => settings.adService.showRewarded(
                onRewardEarned: () {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Thanks for your support! 💙')),
                    );
                  }
                },
              ),
            ),
          const Divider(),

          // ---- OCR engines -------------------------------------------------
          _SectionHeader('OCR engines'),
          const ListTile(
            leading: Icon(Icons.spellcheck_outlined),
            title: Text('English — ML Kit'),
            subtitle: Text('On-device, offline, high accuracy.'),
          ),
          ListTile(
            leading: const Icon(Icons.translate_outlined),
            title: const Text('Bengali — Tesseract (Beta)'),
            subtitle: const Text(app_config.AppConfig.bengaliOcrDisclaimer),
          ),
          const Divider(),

          // ---- About -------------------------------------------------------
          _SectionHeader('About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('FreeScanner'),
            subtitle: Text('Version $_appVersion · on-device scanning, '
                '100% free, no cloud processing.'),
          ),
          if (settings.config.privacyUrl.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy policy'),
              onTap: () => _openUrl(context, settings.config.privacyUrl),
            ),
          if (settings.config.deleteAccountUrl.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.no_accounts_outlined),
              title: const Text('Delete account'),
              subtitle: const Text('Opens the web deletion flow.'),
              onTap: () =>
                  _openUrl(context, settings.config.deleteAccountUrl),
            ),
          if (settings.config.contactEmail.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.mail_outline),
              title: Text(settings.config.contactEmail),
              subtitle: const Text('Support'),
              onTap: () =>
                  _openUrl(context, 'mailto:${settings.config.contactEmail}'),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String get _appVersion => const String.fromEnvironment(
        'APP_VERSION',
        defaultValue: '1.0.0',
      );

  Future<void> _signIn(
    BuildContext context,
    SettingsViewModel settings,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await settings.signIn();
      if (context.mounted) {
        final user = settings.user;
        if (user != null) {
          messenger.showSnackBar(
            SnackBar(content: Text('Signed in as ${user.displayName ?? user.email}')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _signOut(
    BuildContext context,
    SettingsViewModel settings,
  ) async {
    await settings.signOut();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signed out')),
      );
    }
  }

  Future<void> _deleteAccount(
    BuildContext context,
    SettingsViewModel settings,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'Your account session will be deleted from the server. Documents '
          'on this device are NOT affected — FreeScanner stores scans only '
          'on your device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await settings.deleteAccount();
    if (context.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Account deleted')),
      );
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.user,
    required this.onSignOut,
    required this.onDelete,
  });

  final AuthUser user;
  final VoidCallback onSignOut;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        ListTile(
          leading: CircleAvatar(
            backgroundImage:
                user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
            child: user.photoUrl == null
                ? Text((user.displayName ?? user.email)[0].toUpperCase())
                : null,
          ),
          title: Text(user.displayName ?? user.email),
          subtitle: Text(user.email),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: onSignOut, child: const Text('Sign out')),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onDelete,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: const Text('Delete account'),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ],
    );
  }
}
