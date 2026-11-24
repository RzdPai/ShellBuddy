import 'dart:io';

import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

import 'rust_build_environment.dart';

/// Builds `rust/ffi` (theme packages and the theme store, `fl_theme`) and
/// hands the library to the Dart/Flutter SDK as a code asset: no pod, Swift
/// package or Gradle plugin, and an app on fl_lib needs nothing else.
void main(List<String> args) async {
  await build(args, (input, output) async {
    // On HarmonyOS the crate is cross-compiled by `ohos/tools/build-rust.sh`
    // into `ohos/entry/libs/<abi>/libsbm_ffi.so`; hvigor bundles that into the
    // HAP and `main.dart` loads it by name. Driving the in-tree cargo build here
    // would pull in `rustup` (no network in CI/sandbox) for nothing, so skip the
    // hook. We cannot rely on an env var reaching this process — the native
    // assets hook runner does not forward arbitrary variables — so we key off
    // the pre-built library that `build-rust.sh` leaves behind. `SBM_TARGET_OHOS`
    // is still honoured when it does arrive.
    final prebuilt = File.fromUri(
      input.packageRoot.resolve('../../ohos/entry/libs/arm64-v8a/libsbm_ffi.so'),
    );
    if (Platform.environment['SBM_TARGET_OHOS'] == '1' || prebuilt.existsSync()) {
      return;
    }

    await FlutterRustBridgeNativeAssetsBuilder(
      cratePath: 'rust/ffi',
      extraCargoEnvironmentVariables: reproducibleCargoEnvironment(
        environment: Platform.environment,
        packageRoot: Directory.fromUri(input.packageRoot).path,
        isWindows: Platform.isWindows,
      ),
    ).run(input: input, output: output);
  });
}
