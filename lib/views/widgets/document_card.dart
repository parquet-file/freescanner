import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/utils.dart' as utils;
import '../../data/models/scanned_document.dart';

/// views/widgets/document_card.dart — one card in the library grid.
class DocumentCard extends StatelessWidget {
  const DocumentCard({
    super.key,
    required this.document,
    required this.thumbnailPath,
    required this.onTap,
    required this.onLongPress,
  });

  final ScannedDocument document;
  final String thumbnailPath;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = File(thumbnailPath);
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: theme.colorScheme.surfaceContainerHighest,
                child: file.existsSync()
                    ? Image.file(
                        file,
                        fit: BoxFit.cover,
                        cacheWidth: 512,
                        errorBuilder: (_, _, _) => const _BrokenThumbnail(),
                      )
                    : const _BrokenThumbnail(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${document.pageCount} page'
                    '${document.pageCount == 1 ? '' : 's'} · '
                    '${utils.prettyDateTime(document.updatedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrokenThumbnail extends StatelessWidget {
  const _BrokenThumbnail();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.description_outlined,
        size: 48,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
