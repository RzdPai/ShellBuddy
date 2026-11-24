import 'package:fl_lib/fl_lib.dart';
import 'package:path_provider_ohos/path_provider_ohos.dart';
import 'package:shared_preferences_ohos/shared_preferences_ohos.dart';
import 'package:url_launcher_ohos/url_launcher_ohos.dart';

/// Points the plugins below at their HarmonyOS implementations.
///
/// The usual way this happens is the registrant Flutter generates from the
/// plugins' own `pubspec.yaml`: `path_provider` declares
/// `ohos: default_package: path_provider_ohos`, and the tool writes the
/// `registerWith` call. It cannot here. The package that would carry that line
/// is `path_provider` itself, and it is published from flutter/packages, whose
/// manifest knows Android, iOS, Linux, macOS and Windows and has nowhere to put
/// an `ohos` entry — the OpenHarmony side ships as a *separate* package that
/// says `implements: path_provider`, and an implementation nobody points at is
/// never asked for anything.
///
/// So the call is made here instead, once, before anything uses a path, a
/// preference or a link. The native halves are ordinary plugins with an `ohos`
/// block of their own and the registrant does register those; only the Dart
/// side of the binding is missing.
///
/// A no-op on every other platform: [isOhos] is false there, and none of the
/// three packages is reachable from code that runs.
void registerOhosPlugins() {
  if (!isOhos) return;
  PathProviderOhos.registerWith();
  SharedPreferencesOhos.registerWith();
  UrlLauncherOhos.registerWith();
}
