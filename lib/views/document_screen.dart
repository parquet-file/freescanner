import 'dart:io';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../core/share_helper.dart' as share;
import '../core/utils.dart' as utils;
import '../data/models/magic_filter.dart';
import '../data/repositories/document_repository.dart';
import '../viewmodels/document_viewmodel.dart';
import '../viewmodels/settings_viewmodel.dart';
import 'ocr_screen.dart';

/// views/document_screen.dart — the page viewer/editor: swipe pages, apply
/// magic filters, rotate, reorder, delete pages, export the PDF (with the
/// backend-gated interstitial) or run OCR.
class DocumentScreen extends StatelessWidget {
  const DocumentScreen({super.key, required this.documentId});

  final String documentId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DocumentViewModel>(
      create: (context) => DocumentViewModel(
        repository: context.read<DocumentRepository>(),
        adService: context.read<SettingsViewModel>().adService,
        documentId: documentId,
      )..load(),
      child: const _DocumentView(),
    );
  }
}

class _DocumentView extends StatelessWidget {
  const _DocumentView();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DocumentViewModel>();
    final doc = vm.document;
    final theme = Theme.of(context);

    if (vm.busy && doc == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (doc == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              vm.error ?? 'This document no longer exists.',
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final page = doc.pages[utils.clampInt(vm.currentPage, 0, doc.pages.length - 1)];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(doc.title, style: theme.textTheme.titleMedium),
            Text(
              '${doc.pageCount} page(s) · ${page.filter.label}'
              '${page.rotation != 0 ? ' · ${page.rotation}°' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Reorder pages',
            icon: const Icon(Icons.swap_vert),
            onPressed: () => _reorderSheet(context, vm),
          ),
          IconButton(
            tooltip: 'Delete this page',
            icon: const Icon(Icons.delete_outline),
            onPressed: vm.deleteCurrentPage,
          ),
          PopupMenuButton<String>(
            tooltip: 'Export',
            onSelected: (value) => _onMenu(context, vm, value),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'pdf',
                child: ListTile(
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text('Save as PDF'),
                  subtitle: Text('All pages, one document'),
                ),
              ),
              PopupMenuItem(
                value: 'image',
                child: ListTile(
                  leading: Icon(Icons.image_outlined),
                  title: Text('Share this page'),
                  subtitle: Text('Current page as image'),
                ),
              ),
              PopupMenuItem(
                value: 'ocr',
                child: ListTile(
                  leading: Icon(Icons.text_fields_outlined),
                  title: Text('Extract text (OCR)'),
                  subtitle: Text('English or Bengali'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: vm.busy || vm.exporting
          ? Stack(
              children: [
                _PageViewer(vm: vm),
                Container(
                  color: Colors.black38,
                  child: Center(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 12),
                            Text(vm.exporting
                                ? 'Building PDF…'
                                : 'Enhancing page…'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : _PageViewer(vm: vm),
      bottomNavigationBar: _FilterBar(vm: vm),
    );
  }

  Future<void> _onMenu(
    BuildContext context,
    DocumentViewModel vm,
    String action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    switch (action) {
      case 'pdf':
        final path = await vm.exportPdf();
        if (path == null) {
          if (vm.error != null) {
            messenger.showSnackBar(SnackBar(content: Text(vm.error!)));
          }
          return;
        }
        await share.shareFile(path, text: 'Scanned with FreeScanner');
      case 'image':
        final path = await vm.shareCurrentPage();
        if (path != null) await share.shareFile(path);
      case 'ocr':
        if (context.mounted) {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => OcrScreen(documentId: vm.document!.id),
            ),
          );
        }
    }
  }

  Future<void> _reorderSheet(BuildContext context, DocumentViewModel vm) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          final doc = vm.document;
          if (doc == null) return const SizedBox.shrink();
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Text(
                    'Reorder pages',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                for (var i = 0; i < doc.pages.length; i++)
                  ListTile(
                    leading: CircleAvatar(child: Text('${i + 1}')),
                    title: Text('Page ${i + 1} · ${doc.pages[i].filter.label}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_upward),
                          onPressed: i > 0
                              ? () => vm.movePage(i, i - 1)
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_downward),
                          onPressed: i < doc.pages.length - 1
                              ? () => vm.movePage(i, i + 1)
                              : null,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.vm});

  final DocumentViewModel vm;

  @override
  Widget build(BuildContext context) {
    final doc = vm.document;
    if (doc == null || doc.pages.isEmpty) return const SizedBox.shrink();
    final page = doc.pages[utils.clampInt(vm.currentPage, 0, doc.pages.length - 1)];
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final filter in MagicFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(filter.label),
                      selected: page.filter == filter,
                      onSelected: vm.busy
                          ? null
                          : (_) => vm.applyFilter(filter),
                    ),
                  ),
              ],
            ),
          ),
          OverflowBar(
            alignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                onPressed: vm.busy ? null : vm.rotateCurrentPage,
                icon: const Icon(Icons.rotate_right),
                label: const Text('Rotate'),
              ),
              Text(
                'Page ${vm.currentPage + 1} of ${doc.pageCount}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Owns the PageController so swipes survive VM-driven rebuilds.
class _PageViewer extends StatefulWidget {
  const _PageViewer({required this.vm});

  final DocumentViewModel vm;

  @override
  State<_PageViewer> createState() => _PageViewerState();
}

class _PageViewerState extends State<_PageViewer> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.vm.currentPage);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.vm.document;
    if (doc == null || doc.pages.isEmpty) return const SizedBox.shrink();
    return PageView.builder(
      controller: _controller,
      itemCount: doc.pages.length,
      onPageChanged: widget.vm.setPage,
      itemBuilder: (context, index) => InteractiveViewer(
        maxScale: 5,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Image.file(
            File(widget.vm.displayPathFor(index)),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Center(
              child: Icon(Icons.broken_image_outlined, size: 64),
            ),
          ),
        ),
      ),
    );
  }
}
