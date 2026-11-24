// Minimal HarmonyOS (OHOS) system share bridge.
//
// `package:share_plus` has no endorsed OHOS implementation, so
// `SharePlus.instance.share()` silently does nothing there. This package opens
// the system share sheet by sending a `sendData` Want carrying the files'
// sandbox URIs, granting the receiving app temporary read permission.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('serverbox.ohos/share');

/// Shares one or more local files through the system share sheet.
///
/// [paths] must be real, dart:io-readable paths inside the app sandbox.
Future<bool> shareFiles(List<String> paths) async {
  if (paths.isEmpty) return false;
  try {
    final res = await _channel.invokeMethod<bool>('shareFiles', {'paths': paths});
    return res ?? false;
  } catch (e) {
    return false;
  }
}

/// Shares arbitrary text by writing it to a temp file, then sharing that.
Future<bool> shareText(String text, {String? title}) async {
  final dir = Directory.systemTemp;
  final file = File(
    '${dir.path}/serverbox_share_${DateTime.now().microsecondsSinceEpoch}.txt',
  );
  await file.writeAsString(text);
  return shareFiles([file.path]);
}

/// Shares bytes by writing them to a temp file, then sharing that.
Future<bool> shareBytes(
  Uint8List bytes, {
  String? title,
  String? fileName,
  String mime = 'application/octet-stream',
}) async {
  final dir = Directory.systemTemp;
  final name =
      fileName ?? 'serverbox_share_${DateTime.now().microsecondsSinceEpoch}.bin';
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes);
  return shareFiles([file.path]);
}
