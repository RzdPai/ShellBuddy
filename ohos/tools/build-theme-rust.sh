#!/usr/bin/env bash
# Cross-compiles fl_lib's Rust (`packages/fl_lib/rust/ffi`, the theme package
# reader `fl_lib_ffi`) to `libfl_lib_ffi.so` for HarmonyOS.
#
# Why a second script beside `build-rust.sh`: that one builds the app's own
# crate (`crates/sbm_ffi`); the theme reader lives in fl_lib's own workspace
# (`packages/fl_lib/rust`), so it has to be driven from there. Same toolchain,
# same wrapper, same sysroot.
#
# Usage, from the repository root:
#
#   DEVECO_SDK_HOME=... ohos/tools/build-theme-rust.sh
#
# Same requirements as build-rust.sh: a nightly toolchain (Tier 3 target, std
# built from source with `-Z build-std`) and `rust-src` for it.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "$here/env.sh"

workspace="$(cd "$here/../../packages/fl_lib/rust" && pwd)"
cd "$workspace"

chmod +x "$here/ohos-clang-wrapper.sh"

toolchain="${SBM_RUST_TOOLCHAIN:-nightly}"

if ! rustup toolchain list | grep -q "^$toolchain"; then
  echo "build-theme-rust: no $toolchain toolchain (rustup toolchain install $toolchain)" >&2
  exit 1
fi

# The wrapper drops GNU-ld flags the OHOS linker rejects; see its header.
export CC_aarch64_unknown_linux_ohos="$OHOS_CLANG"
export CXX_aarch64_unknown_linux_ohos="$OHOS_CLANGXX"
export AR_aarch64_unknown_linux_ohos="$OHOS_AR"
export RANLIB_aarch64_unknown_linux_ohos="$OHOS_RANLIB"
export CFLAGS_aarch64_unknown_linux_ohos="--target=$OHOS_TRIPLE --sysroot=$OHOS_SYSROOT"
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER="$here/ohos-clang-wrapper.sh"

export RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=--sysroot=$OHOS_SYSROOT -Z unstable-options -C panic=immediate-abort"

echo "build-theme-rust: $toolchain -> $OHOS_RUST_TARGET"

cargo "+$toolchain" build \
  --release \
  --package fl_lib_ffi \
  --target "$OHOS_RUST_TARGET" \
  -Z build-std=std,panic_abort

artifact="target/$OHOS_RUST_TARGET/release/libfl_lib_ffi.so"
if [ ! -f "$artifact" ]; then
  echo "build-theme-rust: expected $artifact, found nothing" >&2
  ls -la "target/$OHOS_RUST_TARGET/release/" | head -20 >&2 || true
  exit 1
fi

"$OHOS_STRIP" --strip-unneeded "$artifact" || true
cp "$artifact" "$OHOS_LIBS_DIR/libfl_lib_ffi.so"
echo "build-theme-rust: $OHOS_LIBS_DIR/libfl_lib_ffi.so ($(du -h "$OHOS_LIBS_DIR/libfl_lib_ffi.so" | cut -f1))"
