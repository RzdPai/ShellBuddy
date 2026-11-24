import 'dart:io';

import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

import 'rust_build_environment.dart';

/// Builds `crates/sbm_ffi` and hands the result to the Dart/Flutter SDK as a
/// code asset.
///
/// This replaces cargokit, which drove cargo from a CocoaPods `script_phase` on
/// Apple platforms, a CMake step on Linux and Windows, and a gradle plugin on
/// Android — four integrations, one per platform, and the Apple one had no
/// Swift Package Manager equivalent: a SwiftPM build tool plugin runs in a
/// sandbox that denies writes to the project directory, so cargo cannot write
/// `target/` or `~/.cargo` from one. That mattered because CocoaPods' registry
/// goes read-only on 2026-12-02 and Flutter's fallback to it is removed some
/// time after.
///
/// A build hook sidesteps the question rather than answering it: it is neither
/// a pod nor a Swift package, so it produces no `.podspec` and no
/// `Package.swift`, and the same file covers all five platforms.
void main(List<String> args) async {
  await build(args, (input, output) async {
    // HarmonyOS: the crate is cross-compiled by `ohos/tools/build-rust.sh`
    // instead, and loaded by name from `entry/libs/`. The builder below asks
    // `native_toolchain_*` for a target, and that package's list stops at
    // Android, iOS, macOS, Linux and Windows — there is no `ohos` for it to
    // resolve. Producing no code asset here is what makes the run a no-op
    // rather than an error; `RustLib.init` is handed an `ExternalLibrary` on
    // this platform, so nothing looks for the asset it would have made.
    // We key the skip off the pre-built library `build-rust.sh` leaves behind:
    // an env var cannot reach this process (the hook runner does not forward
    // arbitrary variables), and the target it is told is `linux` anyway.
    final prebuilt = File.fromUri(
      input.packageRoot.resolve('ohos/entry/libs/arm64-v8a/libsbm_ffi.so'),
    );
    if (Platform.environment['SBM_TARGET_OHOS'] == '1' || prebuilt.existsSync()) {
      return;
    }

    await FlutterRustBridgeNativeAssetsBuilder(
      cratePath: 'crates/sbm_ffi',
      extraCargoEnvironmentVariables: reproducibleCargoEnvironment(
        environment: Platform.environment,
        packageRoot: Directory.fromUri(input.packageRoot).path,
        isWindows: Platform.isWindows,
      ),
    ).run(input: input, output: output);
  });
}
