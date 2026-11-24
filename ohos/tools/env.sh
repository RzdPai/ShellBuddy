#!/usr/bin/env bash
# HarmonyOS cross-compilation environment, shared by the scripts beside it.
#
# Source this file; do not run it. Everything it defines is exported, so a
# `bash -c` inside a build stage sees the same toolchain.
#
#   DEVECO_SDK_HOME=/path/to/DevEco-Studio/sdk source ohos/tools/env.sh
#
# DevEco Studio's command-line tools lay the SDK out the same way the IDE does:
#
#   $DEVECO_SDK_HOME/
#     default/openharmony/
#       native/llvm/bin/clang        the compiler everything here uses
#       native/sysroot/              headers and libc for the target
#       native/llvm/bin/llvm-ar      archiver
#       toolchains/                  hdc and friends
#
# `HOS_SDK_HOME` is accepted as a fallback name: older guides export that one,
# and failing on a name rather than on a missing directory helps nobody.

set -euo pipefail

: "${DEVECO_SDK_HOME:=${HOS_SDK_HOME:-}}"
if [ -z "${DEVECO_SDK_HOME:-}" ]; then
  echo "env.sh: set DEVECO_SDK_HOME (or HOS_SDK_HOME) to DevEco Studio's sdk directory" >&2
  echo "        e.g. /Applications/DevEco-Studio.app/Contents/sdk" >&2
  exit 1
fi

export DEVECO_SDK_HOME
export OHOS_NATIVE="$DEVECO_SDK_HOME/default/openharmony/native"
export OHOS_LLVM="$OHOS_NATIVE/llvm"
export OHOS_SYSROOT="$OHOS_NATIVE/sysroot"
export OHOS_CLANG="$OHOS_LLVM/bin/clang"
export OHOS_CLANGXX="$OHOS_LLVM/bin/clang++"
export OHOS_AR="$OHOS_LLVM/bin/llvm-ar"
export OHOS_RANLIB="$OHOS_LLVM/bin/llvm-ranlib"
export OHOS_STRIP="$OHOS_LLVM/bin/llvm-strip"

if [ ! -x "$OHOS_CLANG" ]; then
  echo "env.sh: no compiler at $OHOS_CLANG" >&2
  echo "        checked under DEVECO_SDK_HOME=$DEVECO_SDK_HOME" >&2
  exit 1
fi

# `aarch64-linux-ohos` is the triple clang wants; the Rust target spells the
# vendor segment out (`aarch64-unknown-linux-ohos`). They are not
# interchangeable and each tool is given its own.
export OHOS_TRIPLE="aarch64-linux-ohos"
export OHOS_RUST_TARGET="aarch64-unknown-linux-ohos"

# Where a built .so has to land for `flutter build hap` to put it in the HAP.
# hvigor packages `entry/libs/<abi>/` as-is, so the ABI directory name is
# HarmonyOS's, not Rust's.
export OHOS_ABI="arm64-v8a"
export OHOS_LIBS_DIR="${OHOS_LIBS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/ohos/entry/libs/$OHOS_ABI}"

# The API level the sysroot was built for. It is a floor for the whole app:
# build-profile.json5 asks for 26 as well.
export OHOS_API="${OHOS_API:-26}"

export CC="$OHOS_CLANG"
export CXX="$OHOS_CLANGXX"
export AR="$OHOS_AR"
export RANLIB="$OHOS_RANLIB"

# Flags every native build here shares. `--sysroot` is not optional: without it
# clang links against the host's libc and the resulting .so fails to load on the
# device with a version error that names none of this.
export OHOS_CFLAGS="--target=$OHOS_TRIPLE --sysroot=$OHOS_SYSROOT -fPIC -O2 -D__OHOS__ -DOHOS"
export OHOS_LDFLAGS="--target=$OHOS_TRIPLE --sysroot=$OHOS_SYSROOT -shared -fPIC"

mkdir -p "$OHOS_LIBS_DIR"

echo "env.sh: DEVECO_SDK_HOME=$DEVECO_SDK_HOME"
echo "env.sh: clang=$OHOS_CLANG"
echo "env.sh: sysroot=$OHOS_SYSROOT"
echo "env.sh: libs -> $OHOS_LIBS_DIR"
