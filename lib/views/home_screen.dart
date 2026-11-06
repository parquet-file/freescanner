import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../data/models/scanned_document.dart';
import '../viewmodels/library_viewmodel.dart';
import 'document_screen.dart';
import 'ocr_screen.dart';
import 'settings_screen.dart';
import 'widgets/adaptive_banner.dart';
import 'widgets/document_card.dart';
import 'widgets/empty_state.dart';

/// views/home_screen.dart — the document library.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('FreeScanner'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: library.loading && library.documents.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: library.load,
                    child: library.documents.isEmpty
                        ? ListView(
                            children: [
                              SizedBox(
                                height: MediaQuery.of(context).size.height * 0.6,
                                child: EmptyState(
                                  onScan: () => _scan(context, library),
                                ),
                              ),
                            ],
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 220,
                              childAspectRatio: 0.72,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: library.documents.length,
                            itemBuilder: (context, index) {
                              final doc = library.documents[index];
                              return DocumentCard(
                                document: doc,
                                thumbnailPath: library.displayPath(doc, 0),
                                onTap: () => _openDocument(context, doc),
                                onLongPress: () => _documentActions(context, doc),
                              );
                            },
                          ),
                  ),
          ),
          const AdaptiveBanner(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: library.scanning ? null : () => _scan(context, library),
        icon: library.scanning
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.document_scanner),
        label: Text(library.scanning ? 'Scanning…' : 'Scan'),
      ),
    );
  }

  Future<void> _scan(BuildContext context, LibraryViewModel library) async {
    final messenger = ScaffoldMessenger.of(context);
    final doc = await library.scanNewDocument();
    if (doc == null) {
      if (library.error != null) {
        messenger.showSnackBar(
          SnackBar(content: Text(library.error!)),
        );
      }
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text('Saved “${doc.title}” (${doc.pageCount} pages)'),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () => _openDocument(context, doc),
        ),
      ),
    );
  }

  void _openDocument(BuildContext context, ScannedDocument doc) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DocumentScreen(documentId: doc.id),
      ),
    );
  }

  Future<void> _documentActions(
    BuildContext context,
    ScannedDocument doc,
  ) async {
    final library = context.read<LibraryViewModel>();
    final messenger = ScaffoldMessenger.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.text_fields_outlined),
              title: const Text('Extract text (OCR)'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => OcrScreen(documentId: doc.id),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final title = await _promptTitle(context, doc.title);
                if (title != null) await library.renameDocument(doc.id, title);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              textColor: Theme.of(context).colorScheme.error,
              iconColor: Theme.of(context).colorScheme.error,
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final confirmed = await _confirmDelete(context, doc);
                if (confirmed) {
                  await library.deleteDocument(doc.id);
                  messenger.showSnackBar(
                    SnackBar(content: Text('Deleted “${doc.title}”')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _promptTitle(BuildContext context, String current) {
    final controller = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename document'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Title',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmDelete(
    BuildContext context,
    ScannedDocument doc,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text(
          '“${doc.title}” and its ${doc.pageCount} page(s) will be removed '
          'from this device. This cannot be undone.',
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
    return result ?? false;
  }
}
