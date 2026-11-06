import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';

import '../core/app_config.dart' as app_config;
import '../core/share_helper.dart' as share;
import '../data/models/scanned_document.dart';
import '../data/repositories/document_repository.dart';
import '../viewmodels/ocr_viewmodel.dart';
import '../core/utils.dart' as utils;

/// views/ocr_screen.dart — text extraction with the language picker.
///
/// CRITICAL UX RULE (product spec): whenever the user selects Bengali as the
/// OCR language, the beta disclaimer is shown IMMEDIATELY, before any
/// recognition runs:
///
///     "Bengali OCR is currently in Beta. Accuracy may vary and spelling
///      errors might occur."
///
/// The user must acknowledge (Continue) before Bengali OCR can start.
class OcrScreen extends StatelessWidget {
  const OcrScreen({super.key, required this.documentId});

  final String documentId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ScannedDocument?>(
      future: context.read<DocumentRepository>().getDocument(documentId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: const Text('Extract text')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final doc = snapshot.data;
        if (doc == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Extract text')),
            body: const Center(child: Text('This document no longer exists.')),
          );
        }
        return ChangeNotifierProvider<OcrViewModel>(
          create: (context) => OcrViewModel(
            repository: context.read<DocumentRepository>(),
            document: doc,
          )..loadSaved(),
          child: const _OcrView(),
        );
      },
    );
  }
}

class _OcrView extends StatelessWidget {
  const _OcrView();

  Future<void> _selectLanguage(
    BuildContext context,
    OcrViewModel vm,
    OcrLanguage language,
  ) async {
    if (language == vm.language) return;
    if (language.requiresDisclaimer) {
      // THE Bengali OCR beta disclaimer — shown the instant Bengali is
      // selected, exactly per spec.
      final acknowledged = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.science_outlined),
          title: const Text('Bengali OCR — Beta'),
          content: const Text(app_config.AppConfig.bengaliOcrDisclaimer),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
      if (acknowledged != true) return;
    }
    vm.setLanguage(language);
    await vm.loadSaved();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<OcrViewModel>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Extract text — ${vm.document.title}'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                for (final language in OcrLanguage.values) ...[
                  ChoiceChip(
                    label: Text(language.label),
                    selected: vm.language == language,
                    onSelected: (_) => _selectLanguage(context, vm, language),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              vm.language == OcrLanguage.bengali
                  ? 'Tesseract on-device engine · beta quality'
                  : 'Google ML Kit on-device engine · high accuracy',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: vm.running
                        ? null
                        : () => vm.run(allPages: false),
                    icon: const Icon(Icons.text_fields),
                    label: Text(vm.document.pageCount > 1
                        ? 'Scan this page'
                        : 'Extract text'),
                  ),
                ),
                if (vm.document.pageCount > 1) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: vm.running
                          ? null
                          : () => vm.run(allPages: true),
                      icon: const Icon(Icons.library_books_outlined),
                      label: const Text('All pages'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: theme.dividerColor),
          Expanded(
            child: vm.running
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Reading the page…'),
                      ],
                    ),
                  )
                : vm.error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            vm.error!,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      )
                    : vm.text.isEmpty
                        ? Center(
                            child: Text(
                              'No text yet.\nTap “Extract text” to recognize '
                              '${vm.language == OcrLanguage.bengali ? 'Bangla and English' : 'English'} '
                              'text on this device.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : Scrollbar(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: SelectableText(
                                vm.text,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
          ),
        ],
      ),
      bottomNavigationBar: vm.text.isEmpty
          ? null
          : SafeArea(
              child: OverflowBar(
                alignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: vm.text),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied to clipboard')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy'),
                  ),
                  TextButton.icon(
                    onPressed: () => share.shareText(
                      vm.text,
                      subject: 'FreeScanner — ${vm.document.title}',
                    ),
                    icon: const Icon(Icons.share),
                    label: const Text('Share'),
                  ),
                  Text(
                    vm.lastRunAt != null
                        ? utils.prettyDateTime(vm.lastRunAt!)
                        : '',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
