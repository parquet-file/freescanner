import 'package:share_plus/share_plus.dart';

/// core/share_helper.dart — one place for share-sheet calls.
Future<void> shareFile(String path, {String? text}) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(path)],
      text: text,
    ),
  );
}

Future<void> shareText(String text, {String? subject}) async {
  await SharePlus.instance.share(ShareParams(text: text, subject: subject));
}
