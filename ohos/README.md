# ServerBox on HarmonyOS

This fork tracks [lollipopkit/flutter_server_box](https://github.com/lollipopkit/flutter_server_box)
and adds a HarmonyOS NEXT target. It currently carries **no** upstream changes
of its own — every commit here is upstream's — plus the files under this
directory.

## Where it stands

| | |
|---|---|
| Upstream baseline | `v1.0.1816+1816`, commit `fdfd372` (2026-10-28) |
| Upstream requirement | Flutter ≥ 3.47.0, Dart ≥ 3.11.0 |
| HarmonyOS toolchain | Flutter `3.47.8-ohos-1.0.0`, DevEco Studio 26.0.0, OpenHarmony SDK API 26 |
| HAP identity | `com.rzdpai.shell`, aarch64 |
| Signing | none — the CI produces an unsigned HAP |

**The app does not run on HarmonyOS yet.** The scaffolding, the platform
branch and three of the four native libraries are in place; the blocker is
described under [Known gaps](#known-gaps), and it is one thing, not a list.

The fork was previously a snapshot of upstream from 2025-06 (`v1189`) that had
never been worked on: no `ohos/` directory, no `ohos` string anywhere in the
tree. The 646 upstream commits between then and now are merged in.

## What is here

```
ohos/
  AppScope/            bundle name, icon, app label
  entry/               the HAP: EntryAbility, module.json5, resources
  build-profile.json5  API 26, HarmonyOS runtime
  patches/             changes applied to submodules at build time
  tools/               cross-compilation: env, Rust, sqlite3mc, fl_tty
```

Three changes outside this directory:

| File | Why |
|---|---|
| `lib/main.dart` | `RustLib.init` is handed an `ExternalLibrary` on HarmonyOS; plugins are registered before `Paths.init` |
| `lib/core/service/ohos_plugins.dart` | `path_provider`, `shared_preferences` and `url_launcher` have no registrant entry pointing at their HarmonyOS implementations |
| `hook/build.dart` | returns early when `SBM_TARGET_OHOS=1`, because the builder cannot resolve an `ohos` target |

Four packages had to be replaced or added in `pubspec.yaml`; each carries a
comment saying why.

## Why the native code is built outside the build hooks

Upstream compiles everything through [native assets](https://dart.dev/tools/hooks):
`crates/sbm_ffi` through `flutter_rust_bridge_hooks`, `sqlite3mc` through the
`sqlite3` package's own hook, `fl_tty` and `fl_pi_llm` through their own. All of
them resolve a target through `code_assets`, whose platform enum is

```
android, ios, linux, macos, windows
```

There is no `ohos`. On a HarmonyOS build, reading `targetOS` does not answer
"unknown" — it throws, in the hook, before any of the packages get a chance to
disagree with each other. So:

* `sbm_ffi` — **worked around.** `flutter_rust_bridge` lets a caller pass an
  `ExternalLibrary`, so `main.dart` opens `libsbm_ffi.so` by name and the hook
  produces nothing. The crate is cross-compiled by `ohos/tools/build-rust.sh`
  and ships in `entry/libs/arm64-v8a/`. This part is sound: the Dart side never
  looks for an asset.
* `sqlite3mc`, `fl_tty` — **built, not loadable.** Both packages reach their
  library through `@Native` / `@DefaultAsset`, a compile-time binding with no
  runtime override. The `.so` files the scripts produce are correct and land in
  the right place; nothing in the app can call into them until the asset is
  resolved. See below.
* `fl_pi_llm` — the Agent tab. Not compiled here; `LlmHost.init` already
  catches its own failure and the rest of the app carries on without it.

## Known gaps

### 1. `code_assets` has no `ohos` target (blocker)

The app's stores are SQLite databases opened through `package:sqlite3`, and
`sqlite3` 3.6.0 binds its symbols at compile time to a native-asset id. There is
no `open.overrideFor` any more; 3.6.0 removed the runtime loader entirely.

Consequences, in order of what a user sees: `Stores.init` throws, `_initApp`
catches it, and the rescue window shows `LaunchFailedPage`. Not a white screen
(the failure path upstream is good), but not an app either.

Three ways forward, in the order worth trying:

1. **Find out whether this SDK resolves code assets at all.** Build a
   ten-line Flutter project with one `@Native` function against
   `3.47.8-ohos-1.0.0` and see whether the asset is found. The community's
   0day work points `flutter_tools` at a forked `code_assets` and `hooks_runner`
   (`fluttertpc_dart_native`), which suggests the support exists but is not in
   every published tag. Everything else here is downstream of that answer.
2. **If it does:** each hook needs a guard for the `ohos` case and a compiler
   override, so `CBuilder` invokes the OpenHarmony clang instead of looking for
   `aarch64-linux-gnu-gcc`. The `.so` files are already built by the scripts in
   `ohos/tools/`; the hooks would hand them over as code assets rather than
   compiling anything.
3. **If it does not:** `sqlite3` has to go back to a version with a runtime
   loader, which means `drift` and every call site move too — a fork of the
   data layer, not a build flag. Worth pricing before choosing it.

### 2. Plugins with no HarmonyOS implementation

`flutter_displaymode`, `window_manager`, `desktop_drop`, `sentry_flutter`,
`flutter_local_notifications`, `watch_connectivity`, `icloud_storage_plus`.
Most call sites are already behind `isAndroid` / `isDesktop` checks and are
inert on HarmonyOS. The ones that are not are worth a pass once the app starts:

* `TermSessionManager.init` — session notifications
* `Sentry.init` — the crash sink
* `file_picker` on the SFTP upload path (a `file_picker_ohos` exists on pub.dev,
  but at `1.0.1` it predates the current platform interface)

### 3. `flutter_secure_storage`

Upstream uses a fork (`lollipopkit/flutter_secure_storage`, branch `serverbox`).
The only HarmonyOS implementation on pub.dev is `flutter_secure_storage_ohos`
1.0.0, which is a Dart 2 package — `sdk: <3.0.0` — and a whole replacement of
`FlutterSecureStorage` rather than an implementation of the platform interface.
It cannot be used as-is.

The vault is what encrypts the database key, so this matters as much as gap 1
does for a first launch. The realistic route is an ArkTS side for the existing
method channel (`plugins.it_nomads.com/flutter_secure_storage`) over
`@ohos.data.preferences` or HUKS, with no Dart change at all.

### 4. Background keep-alive

A terminal session that outlives the foreground needs
`ohos.permission.KEEP_BACKGROUND_RUNNING` and a `backgroundModes` entry on the
ability. Neither is declared: which mode is right (`dataTransfer` is the
closest fit) is a question for AppGallery review, not for this file.

## Building

```
export DEVECO_SDK_HOME=/path/to/DevEco-Studio/sdk
source ohos/tools/env.sh

ohos/tools/build-rust.sh          # libsbm_ffi.so  (nightly + rust-src needed)
ohos/tools/build-sqlite3mc.sh     # libsqlite3.so  (fetches the amalgamation)
ohos/tools/build-fl-tty.sh        # libfl_tty.so   (needs submodules)

git -C packages/fl_lib apply ohos/patches/0001-fl_lib-harmonyos-platform.patch

flutter pub get
flutter build hap --release --no-codesign
```

The output is `build/ohos/hap/entry-default-unsigned.hap`. An emulator will
install it; a phone will not, because signing needs a certificate bound to an
AppGallery Connect account.

CI does the same thing — `.github/workflows/ohos.yml`. It needs one repository
variable, `OHOS_SDK_URL`, pointing at a tarball of DevEco's `sdk/` directory;
Huawei's download page wants an account, so no runner can fetch it unattended.

## The patch in `patches/`

`0001-fl_lib-harmonyos-platform.patch` adds `Pfs.ohos` to `fl_lib`'s platform
enum, maps `Platform.operatingSystem == 'ohos'` onto it, and puts it in
`isMobile` — without that last part the app reads HarmonyOS as "not mobile, not
desktop" and takes desktop branches that call `window_manager`.

It lives here rather than in a commit to `fl_lib` because `fl_lib` is a
submodule: a local edit would show as a dirty tree and be thrown away by the
next `git submodule update`. If this fork is to be maintained for long, the
patch should become a branch on a fork of `fl_lib` and the submodule URL
pointed at it — at which point this file can go away.

## AGC "source file" check (Web-only `.js` assets)

AppGallery Connect's pre-submission source-file check flags **any `.js` inside
the HAP as source code**, even when it is an inert runtime resource. Two
transitive dependencies declare Web-only assets that Flutter collects into
`flutter_assets/rawfile` unconditionally, on every platform:

- `wakelock_plus` → `no_sleep.js` (a Web wake-lock script)
- `flutter_local_notifications_web` → `notifications_service_worker.js`

Neither is ever loaded on HarmonyOS. Deleting them from `rawfile` does not
help: the `flutter-hvigor-plugin` copy step wipes and re-copies `flutter_assets`
from `build/ohos/intermediates/flutter/...` on every build.

Fix (applied here, reproducible on CI): local forks in `third_party/` with the
`flutter.assets` declaration removed, pinned via `dependency_overrides` in the
root `pubspec.yaml`. The plugin APIs are untouched; only the asset collection
changes, so the two `.js` files never enter the HAP. If either package is
upgraded, re-apply: copy the new version into `third_party/`, drop its
`assets:` entry, and keep the override.

## Supported device types

`ohos/entry/src/main/module.json5` declares `deviceTypes: ["phone", "tablet",
"2in1"]` (mirrored in `entry/src/ohosTest/module.json5`). Upstream ServerBox is
multi-form-factor; on HarmonyOS the meaningful form factors for an SSH/remote
desktop tool are phone, tablet and 2in1 (PC). `tv` / `car` / `wearable` are
intentionally omitted. The release `app_gallery` provisioning profile carries
no device whitelist, so widening the declaration does not conflict with signing.

## Store-build feature gates (AI hidden / Beta marks off)

Two submission-time gates live in one place so they are trivial to restore:

- `lib/data/res/review_flags.dart` — `ReviewFlags.hideAi`. While `true`,
  every user-facing AI/Agent entry is hidden: the Agent home tab (dropped from
  the default order, from "more", from the tab-setting page and from stored
  orders), the settings' AI section (menu node + search), the terminal's
  "Ask AI" toolbar/item buttons, the selection tooltip action, and the
  floating Agent window. Providers, tools, chats and all code stay intact —
  AOT folds the gated branches out of the binary.
- `lib/data/model/app/feature.dart` — `Feature._showBetaMarks = false` turns
  off every Beta mark app-wide (tabs, cards, settings, warnings), since all of
  them ask `Feature.beta`.

**To restore once the AI qualification is approved:** set `hideAi = false`
and `_showBetaMarks = true`, then rebuild. No other file needs touching.

## QR scan on camera-less 2in1 / PC

`QrScanOhosPlugin.ets` used to call `res.originalValue` unguarded. On 2in1/PC
devices with no camera, `scanBarcode.startScanForResult` resolves with `null`,
which surfaced as "Cannot read property originalValue of null" (phone/tablet
were fine). The plugin now:

- probes `camera.getCameraManager(ctx).getSupportedCameras()` first;
- with a camera (incl. camera-equipped 2in1) uses the system scan UI;
- without one (or if the scan resolves empty/fails) falls back to
  `photoAccessHelper.PhotoViewPicker` + `detectBarcode.decode({uri})`;
- null-guards every result, so picker cancellation maps to "cancel" and no
  path can dereference null. No CAMERA permission is needed (system picker /
  system scanner own the camera). Both flows compile into `ets/modules.abc`.
