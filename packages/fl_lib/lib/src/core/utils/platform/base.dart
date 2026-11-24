import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
// file_picker 12 has no endorsed OHOS implementation, so `FilePicker.pickFile`
// does nothing there. The bridge opens the system DocumentViewPicker and
// copies the result into the app cache, yielding a plain dart:io path.
import 'package:file_picker_ohos/file_picker_ohos.dart' as ohos_picker;
import 'package:fl_lib/src/core/ext/ctx/l10n.dart';
import 'package:fl_lib/src/core/ext/datetime.dart';
import 'package:fl_lib/src/core/ext/string.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:share_plus/share_plus.dart';
// share_plus has no endorsed OHOS implementation, so `SharePlus.instance.share`
// does nothing there. This opens the system share sheet via a sendData Want.
import 'package:share_ohos/share_ohos.dart' as ohos_share;

/// Platforms
enum Pfs {
  android,
  ios,
  ohos,
  linux,
  macos,
  windows,
  web,
  fuchsia,
  unknown;

  /// The current platform
  static final type = () {
    if (kIsWeb) {
      return web;
    }
    return switch (Platform.operatingSystem) {
      'android' => android,
      'ios' => ios,
      // HarmonyOS NEXT. Not `linux`: `Platform.operatingSystem` answers
      // `ohos` there even though the kernel is Linux, and treating it as
      // Linux pulls in desktop paths that do not exist on the device.
      'ohos' => ohos,
      'linux' => linux,
      'macos' => macos,
      'windows' => windows,
      'fuchsia' => fuchsia,
      // If the platform is not recognized, return unknown
      _ => unknown,
    };
  }();

  @override
  String toString() => switch (this) {
    macos => 'macOS',
    ios => 'iOS',
    ohos => 'HarmonyOS',
    final val => val.name.capitalize,
  };

  static final String seperator = isWindows ? '\\' : '/';

  /// Whether macOS is confining this process to a container.
  ///
  /// The container id is in the environment of a sandboxed app and absent
  /// otherwise, which is the cheapest reliable answer — verified both ways.
  /// Asked of the running process rather than baked in at build time, so one
  /// binary is honest in either build.
  ///
  /// False everywhere else: no other platform this ships on has two builds of
  /// itself that differ in what the process may do.
  static final bool isMacSandboxed =
      isMacOS && Platform.environment.containsKey('APP_SANDBOX_CONTAINER_ID');

  /// Available only on desktop,
  /// return null on mobile
  static final String? homeDir = () {
    final envVars = Platform.environment;
    if (isMacOS || isLinux) {
      return envVars['HOME'];
    } else if (isWindows) {
      return envVars['UserProfile'];
    }
    return null;
  }();

  /// Share files.
  /// Open share sheet on mobile, reveal in file explorer on desktop.
  static Future<ShareResult?> sharePaths({required List<String> paths, String? title}) async {
    if (isDesktop) {
      /// Open the paths
      for (final path in paths) {
        final file = File(path);
        if (!await file.exists()) {
          Logger.root.warning('File not found: $path');
          continue;
        }
        await revealPath(path);
      }
      return null;
    }

    // OHOS: no share_plus implementation — open the system share sheet.
    if (isOhos) {
      final ok = await ohos_share.shareFiles(paths);
      return ok
          ? const ShareResult('', ShareResultStatus.success)
          : null;
    }

    title ??= libL10n.share;
    final files = paths.map((path) => XFile(path)).toList();
    final params = ShareParams(title: title, files: files);
    return SharePlus.instance.share(params);
  }

  /// Share string data with a file name.
  static Future<ShareResult> shareStr(String data, {String? title}) async {
    // OHOS: no share_plus implementation — write to a temp file and share it.
    if (isOhos) {
      final ok = await ohos_share.shareText(data, title: title);
      return ok
          ? const ShareResult('', ShareResultStatus.success)
          : const ShareResult('', ShareResultStatus.unavailable);
    }
    title ??= libL10n.share;
    final params = ShareParams(text: data, title: title);
    return SharePlus.instance.share(params);
  }

  /// Share bytes data.
  static Future<ShareResult> shareBytes({
    required Uint8List bytes,
    String? title,
    String? fileName,
    String mime = 'application/octet-stream',
  }) async {
    title;
    // OHOS: no share_plus implementation — write to a temp file and share it.
    if (isOhos) {
      final ok = await ohos_share.shareBytes(
        bytes,
        title: title,
        fileName: fileName,
        mime: mime,
      );
      return ok
          ? const ShareResult('', ShareResultStatus.success)
          : const ShareResult('', ShareResultStatus.unavailable);
    }
    final xfile = XFile.fromData(bytes, mimeType: mime, name: fileName ?? 'shared_file_${DateTimeX.timestamp}.bin');
    final params = ShareParams(files: [xfile], title: title ?? libL10n.share);
    return SharePlus.instance.share(params);
  }

  /// Pick a file and return the [PlatformFile] object.
  static Future<PlatformFile?> pickFile() async {
    if (isOhos) return ohos_picker.pickFile();
    return FilePicker.pickFile(type: FileType.any);
  }

  /// Pick a file and return the file path.
  static Future<String?> pickFilePath() async {
    final picked = await pickFile();
    return picked?.path;
  }

  /// Pick a file and return the file String.
  static Future<String?> pickFileString() async {
    final picked = await pickFile();
    if (picked == null) return null;

    switch (Pfs.type) {
      case Pfs.web:
        // Read on demand since file_picker 12; there is no eagerly filled
        // `bytes` to reach for any more.
        return utf8.decode(await picked.readAsBytes());
      default:
        final path = picked.path;
        if (path == null) return null;
        return await File(path).readAsString();
    }
  }

  /// Copy the data to the clipboard.
  static void copy(dynamic data) => switch (data.runtimeType) {
    const (String) => Clipboard.setData(ClipboardData(text: data)),
    final val => throw UnimplementedError('Not supported type: $val(${val.runtimeType})'),
  };

  /// Paste the data from the clipboard.
  static Future<String?> paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  /// Reveal file / dir in file app.
  ///
  /// **Only available on desktop**
  static Future<void> revealPath(String path) async {
    try {
      switch (type) {
        case Pfs.macos:
          await Process.run('open', ['--reveal', path]);
          break;
        case Pfs.windows:
          await Process.run('explorer', ['/select,', path.replaceAll('"', '""')]);
          break;
        case Pfs.linux:
          await Process.run('xdg-open', [path]);
          break;
        default:
          throw UnimplementedError('Unsupported platform: $type');
      }
    } catch (e) {
      Logger.root.warning('reveal path: $path', e);
    }
  }
}

final isAndroid = Pfs.type == Pfs.android;
final isIOS = Pfs.type == Pfs.ios;
final isOhos = Pfs.type == Pfs.ohos;
final isLinux = Pfs.type == Pfs.linux;
final isMacOS = Pfs.type == Pfs.macos;
final isWindows = Pfs.type == Pfs.windows;
final isWeb = Pfs.type == Pfs.web;
/// Phone and tablet, so HarmonyOS counts: the pages it opens, the plugins it
/// may call and the layout it picks are the mobile ones, not the desktop ones.
final isMobile =
    Pfs.type == Pfs.ios || Pfs.type == Pfs.android || Pfs.type == Pfs.ohos;
final isDesktop = Pfs.type == Pfs.linux || Pfs.type == Pfs.macos || Pfs.type == Pfs.windows;
