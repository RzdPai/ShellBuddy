#!/usr/bin/env bash
# Cross-compiles `crates/sbm_ffi` to `libsbm_ffi.so` for HarmonyOS.
#
# Why here and not through the build hook: `hook/build.dart` drives
# `flutter_rust_bridge_hooks`, which resolves a target through
# `native_toolchain_core`. That package enumerates Android, iOS, Linux, macOS
# and Windows. `ohos` is not among them, so there is no target for the builder
# to resolve and the hook is skipped (`SBM_TARGET_OHOS=1`); this script is what
# runs instead, and `main.dart` loads the result by name.
#
# Usage, from the repository root:
#
#   DEVECO_SDK_HOME=... ohos/tools/build-rust.sh
#
# Requirements beyond the SDK:
#   - a nightly toolchain: `aarch64-unknown-linux-ohos` is a Tier 3 target and
#     ships no prebuilt std, so it is built from source with `-Z build-std`
#   - `rust-src` for that toolchain: `rustup component add rust-src --toolchain <nightly>`

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "$here/env.sh"

root="$(cd "$here/../.." && pwd)"
cd "$root"

chmod +x "$here/ohos-clang-wrapper.sh"

toolchain="${SBM_RUST_TOOLCHAIN:-nightly}"

if ! rustup toolchain list | grep -q "^$toolchain"; then
  echo "build-rust: no $toolchain toolchain (rustup toolchain install $toolchain)" >&2
  exit 1
fi

# `ring` compiles C and assembly, so it needs the same compiler the rest of this
# uses, addressed by the name cargo gives it: the target triple with dashes
# turned into underscores. Without these it picks the host cc, and the failure
# is an x86-64 object in an arm64 link.
export CC_aarch64_unknown_linux_ohos="$OHOS_CLANG"
export CXX_aarch64_unknown_linux_ohos="$OHOS_CLANGXX"
export AR_aarch64_unknown_linux_ohos="$OHOS_AR"
export RANLIB_aarch64_unknown_linux_ohos="$OHOS_RANLIB"
export CFLAGS_aarch64_unknown_linux_ohos="--target=$OHOS_TRIPLE --sysroot=$OHOS_SYSROOT"
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER="$here/ohos-clang-wrapper.sh"

# The sysroot has to reach the linker explicitly: the wrapper passes the target
# triple, but nothing else knows where this SDK's libc is.
# `panic=immediate-abort` (the smallest possible panic path) used to be a
# `-Z build-std-features` name; recent nightlies turned it into a real panic
# strategy gated behind `-Z unstable-options`, so spell it as a codegen flag.
export RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=--sysroot=$OHOS_SYSROOT -Z unstable-options -C panic=immediate-abort"

echo "build-rust: $toolchain -> $OHOS_RUST_TARGET"

cargo "+$toolchain" build \
  --release \
  --package sbm_ffi \
  --target "$OHOS_RUST_TARGET" \
  -Z build-std=std,panic_abort

# The lib name comes from Cargo's `[lib] name`, which is `sbm_ffi`.
artifact="target/$OHOS_RUST_TARGET/release/libsbm_ffi.so"
if [ ! -f "$artifact" ]; then
  echo "build-rust: expected $artifact, found nothing" >&2
  ls -la "target/$OHOS_RUST_TARGET/release/" | head -20 >&2 || true
  exit 1
fi

"$OHOS_STRIP" --strip-unneeded "$artifact" || true
cp "$artifact" "$OHOS_LIBS_DIR/libsbm_ffi.so"
echo "build-rust: $OHOS_LIBS_DIR/libsbm_ffi.so ($(du -h "$OHOS_LIBS_DIR/libsbm_ffi.so" | cut -f1))"
