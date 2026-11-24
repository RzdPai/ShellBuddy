// Minimal HarmonyOS (OHOS) system QR scanner bridge.
//
// `package:qr_code_dart_scan` drives a camera preview through a plugin that
// has no OHOS implementation, so its page never opens here. Scan Kit provides
// a system scan UI instead, so this package asks the native side to present it
// and hands back the raw value.
import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('serverbox.ohos/qr_scan');

/// Opens the system scan UI and returns the raw code value.
///
/// Returns null when the user cancels. Throws [PlatformException] when the
/// system scanner cannot be opened, so callers can tell the two apart.
Future<String?> scanQrCode() async {
  final value = await _channel.invokeMethod<String>('scan');
  if (value == null || value.isEmpty) return null;
  return value;
}
