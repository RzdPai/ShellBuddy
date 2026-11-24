// Minimal HarmonyOS (OHOS) file picker.
//
// `package:file_picker` has no endorsed OHOS implementation, so
// `FilePicker.pickFile()` silently does nothing there. This package bridges
// the gap: the native side opens the system DocumentViewPicker, copies the
// picked document into the app cache directory (picker results are URIs that
// dart:io cannot open directly) and hands back a plain file path.
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('serverbox.ohos/file_picker');

/// Opens the system file picker and returns the picked file, or null when the
/// user cancelled.
///
/// The returned [PlatformFile.path] is always a real path inside the app
/// cache, readable with dart:io — safe for SFTP transfer workers running in
/// isolates.
Future<PlatformFile?> pickFile() async {
  final res = await _channel.invokeMethod<dynamic>('pickFile');
  if (res == null) return null;
  final map = Map<Object?, Object?>.from(res as Map);
  final path = map['path']! as String;
  final name =
      (map['name'] as String?) ?? path.split(Platform.pathSeparator).last;
  return _OhosPickedFile(
    path: path,
    name: name,
    size: map['size'] as int?,
  );
}

/// Opens the system folder picker. Returns the picked URI string, or null on
/// cancel. Note: the URI is not guaranteed to be dart:io readable.
Future<String?> pickDirectory() async {
  return _channel.invokeMethod<String>('pickDirectory');
}

/// [PlatformFile] is abstract in file_picker 12, so back it with a plain
/// cache file.
final class _OhosPickedFile extends PlatformFile {
  _OhosPickedFile({required this.path, required this.name, int? size})
      : _size = size;

  /// Real local path inside the app cache (dart:io readable).
  final String path;

  @override
  final String name;

  /// Size reported by the picker, used to skip a stat round trip.
  final int? _size;

  @override
  Uri get uri => Uri.file(path);

  @override
  XFile get xFile => XFile(path);

  @override
  int? lengthSync() => _size ?? File(path).lengthSync();

  @override
  Future<int> length() async => _size ?? await File(path).length();

  @override
  Future<Uint8List> readAsBytes() => File(path).readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() =>
      File(path).openRead().map(Uint8List.fromList);
}
