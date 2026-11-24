import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

import 'bindgen_environment.dart';
import 'c_build_environment.dart';
import 'deployment_target.dart';
import 'rust_build_environment.dart';

/// Builds `rust/` and hands the library to the Dart/Flutter SDK as a code
/// asset. No pod, no Swift package, no Gradle plugin: the same file covers
/// every platform, and an app that depends on this package needs nothing else.
void main(List<String> args) async {
  await build(args, (input, output) async {
    // On HarmonyOS the crate is cross-compiled by `ohos/tools/build-rust-llm.sh`
    // into `ohos/entry/libs/<abi>/libfl_pi_llm.so`. The in-tree cargo build
    // cannot run here: `native_toolchain_core` has no `ohos` target, and trying
    // to add one makes `rustup` reach for the network (unavailable in this
    // environment). Instead we bundle the pre-built library as a code asset so
    // the app's `RustLib.init` finds it through the normal native-asset path.
    final prebuilt = File.fromUri(
      input.packageRoot.resolve(
        '../../../ohos/entry/libs/arm64-v8a/libfl_pi_llm.so',
      ),
    );
    if (prebuilt.existsSync()) {
      final bundled = input.outputDirectoryShared.resolve('libfl_pi_llm.so');
      if (!File.fromUri(bundled).existsSync()) {
        await Directory.fromUri(bundled).parent.create(recursive: true);
        await prebuilt.copy(File.fromUri(bundled).path);
      }
      output.assets.code.add(
        CodeAsset(
          name: 'fl_pi_llm',
          file: bundled,
          package: input.packageName,
          linkMode: DynamicLoadingBundled(),
        ),
      );
      return;
    }

    await FlutterRustBridgeNativeAssetsBuilder(
      cratePath: 'rust',
      extraCargoEnvironmentVariables: {
        ...reproducibleCargoEnvironment(
          environment: Platform.environment,
          packageRoot: Directory.fromUri(input.packageRoot).path,
          isWindows: Platform.isWindows,
        ),
        if (input.config.buildCodeAssets)
          ...reproducibleCEnvironment(
            environment: Platform.environment,
            outputDirectory: Directory.fromUri(input.outputDirectory).path,
            targetOS: input.config.code.targetOS,
          ),
        // Only ever non-empty for iOS and Android, the two targets
        // `rquickjs-sys` ships no bindings for. See its own file.
        ...bindgenCrossCompileEnvironment(input),
        ...deploymentTargetEnvironment(input),
      },
    ).run(input: input, output: output);
  });
}
