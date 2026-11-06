import 'package:flutter/material.dart';

/// views/widgets/empty_state.dart — the "no documents yet" hero.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.document_scanner_outlined,
                size: 56,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text('No documents yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Tap the Scan button to capture your first document. '
              'Edge detection, cropping and enhancement all happen on '
              'your device — no internet needed.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Scan your first document'),
            ),
          ],
        ),
      ),
    );
  }
}
