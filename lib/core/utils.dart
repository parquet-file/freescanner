/// core/utils.dart — small helpers (ids, timestamps, human sizes).
library;

import 'dart:math';

/// int-typed clamp (num.clamp returns num, which cannot index lists).
int clampInt(int value, int min, int max) =>
    value < min ? min : (value > max ? max : value);

/// Random id suffix for document ids (letters + digits).
String randomIdSuffix([int length = 8]) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final rnd = Random();
  final buffer = StringBuffer();
  for (var i = 0; i < length; i++) {
    buffer.write(chars[rnd.nextInt(chars.length)]);
  }
  return buffer.toString();
}

/// Filesystem-safe timestamp: 20261106-142530
String fileTimestamp([DateTime? when]) {
  final t = when ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}'
      '${two(t.second)}';
}

/// "6 Nov 2026, 2:25 PM" style label for lists.
String prettyDateTime(DateTime t) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hour12 = t.hour == 0
      ? 12
      : (t.hour > 12 ? t.hour - 12 : t.hour);
  final amPm = t.hour >= 12 ? 'PM' : 'AM';
  return '${t.day} ${months[t.month - 1]} ${t.year}, '
      '$hour12:${t.minute.toString().padLeft(2, '0')} $amPm';
}

/// Human-readable byte size.
String prettyBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
