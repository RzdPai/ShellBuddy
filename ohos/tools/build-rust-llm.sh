#!/usr/bin/env bash
# Cross-compiles `packages/fl_pi_llm/fl_pi_llm/rust` (the pi-durable / pi-ai
# LLM bridge on QuickJS) to `libfl_pi_llm.so` for HarmonyOS.
#
# Same situation as build-rust.sh for fl_lib: `native_toolchain_core` has no
# `ohos` target, so the in-tree hook cannot resolve one and would otherwise
# hang on `rustup` (no network). We build the crate here with the nightly
# toolchain and `-Z build-std` (the `aarch64-unknown-linux-ohos` target ships
# no prebuilt std), using the OHOS LLVM as the C/C++ and linker toolchain so
# rquickjs's bundled QuickJS and sqlite3mc-src compile for the target.
#
# Usage, from the repository root:
#   DEVECO_SDK_HOME=... ohos/tools/build-rust-llm.sh

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "$here/env.sh"

root="$(cd "$here/../.." && pwd)"
cd "$root"

chmod +x "$here/ohos-clang-wrapper.sh"

toolchain="${SBM_RUST_TOOLCHAIN:-nightly}"

if ! rustup toolchain list | grep -q "^$toolchain"; then
  echo "build-rust-llm: no $toolchain toolchain (rustup toolchain install $toolchain)" >&2
  exit 1
fi

# C/C++ toolchain for the C parts (QuickJS, SQLite3 Multiple Ciphers).
export CC_aarch64_unknown_linux_ohos="$OHOS_CLANG"
export CXX_aarch64_unknown_linux_ohos="$OHOS_CLANGXX"
export AR_aarch64_unknown_linux_ohos="$OHOS_AR"
export RANLIB_aarch64_unknown_linux_ohos="$OHOS_RANLIB"
export CFLAGS_aarch64_unknown_linux_ohos="--target=$OHOS_TRIPLE --sysroot=$OHOS_SYSROOT"
export CXXFLAGS_aarch64_unknown_linux_ohos="--target=$OHOS_TRIPLE --sysroot=$OHOS_SYSROOT"
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER="$here/ohos-clang-wrapper.sh"

# rquickjs-sys generates its bindings with `bindgen` on this target, which needs
# libclang (the OHOS LLVM ships one) and the target's sysroot to parse QuickJS's
# C headers.
export LIBCLANG_PATH="$OHOS_LLVM/lib"
export BINDGEN_EXTRA_CLANG_ARGS="--target=$OHOS_TRIPLE --sysroot=$OHOS_SYSROOT -I$OHOS_SYSROOT/usr/include -I$OHOS_SYSROOT/usr/include/$OHOS_TRIPLE"

# Build std from source for the Tier-3 target; immediate-abort panic path.
export RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=--sysroot=$OHOS_SYSROOT -Z unstable-options -C panic=immediate-abort"

crate_dir="$root/packages/fl_pi_llm/fl_pi_llm/rust"
cd "$crate_dir"

echo "build-rust-llm: $toolchain -> $OHOS_RUST_TARGET"

cargo "+$toolchain" build \
  --release \
  --target "$OHOS_RUST_TARGET" \
  -Z build-std=std,panic_abort

artifact="target/$OHOS_RUST_TARGET/release/libfl_pi_llm.so"
if [ ! -f "$artifact" ]; then
  echo "build-rust-llm: expected $artifact, found nothing" >&2
  ls -la "target/$OHOS_RUST_TARGET/release/" | head -20 >&2 || true
  exit 1
fi

"$OHOS_STRIP" --strip-unneeded "$artifact" || true
cp "$artifact" "$OHOS_LIBS_DIR/libfl_pi_llm.so"
echo "build-rust-llm: $OHOS_LIBS_DIR/libfl_pi_llm.so ($(du -h "$OHOS_LIBS_DIR/libfl_pi_llm.so" | cut -f1))"
