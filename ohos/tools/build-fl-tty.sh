#!/usr/bin/env bash
# Builds `libfl_tty.so` — the pty behind the terminal tab — for HarmonyOS.
#
# The C is POSIX and nothing in it is platform-specific beyond `forkpty`, which
# the HarmonyOS libc has: the source is the same file Android and Linux use
# (`src/flutter_pty.c`, which pulls in `flutter_pty_unix.c`).
#
# What does not work is the build. `packages/fl_tty/hook/build.dart` asks
# `CBuilder` for a library, and `CBuilder` resolves its target through
# `code_assets`' OS enum, which has no `ohos`. Same wall as `sbm_ffi` and
# `sqlite3`, same way round it: compile it here, ship it in `entry/libs/`.
#
# Usage, from the repository root:
#
#   DEVECO_SDK_HOME=... ohos/tools/build-fl-tty.sh

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "$here/env.sh"

root="$(cd "$here/../.." && pwd)"
pkg="$root/packages/fl_tty"

if [ ! -f "$pkg/src/flutter_pty.c" ]; then
  echo "build-fl-tty: $pkg/src/flutter_pty.c missing — run 'git submodule update --init'" >&2
  exit 1
fi

out="$OHOS_LIBS_DIR/libfl_tty.so"

echo "build-fl-tty: compiling"
# `DART_SHARED_LIB` is what `dart_api_dl.c` needs to link as part of this
# library rather than against it; the hook passes the same define.
"$OHOS_CLANG" \
  $OHOS_CFLAGS \
  -I"$pkg/src" \
  -DDART_SHARED_LIB \
  -shared -fPIC \
  -o "$out" \
  "$pkg/src/flutter_pty.c" \
  -lpthread

"$OHOS_STRIP" --strip-unneeded "$out" || true
echo "build-fl-tty: $out ($(du -h "$out" | cut -f1))"

cat <<'NOTE'

build-fl-tty: the .so is built, but `package:fl_tty` reaches it through
`@DefaultAsset('package:fl_tty/fl_tty')` — a native-asset binding, not a
`DynamicLibrary.open` — so on this platform it is only loadable once
`code_assets` resolves an `ohos` target. See "Known gaps" in ohos/README.md:
the library alone does not make the terminal work.
NOTE
