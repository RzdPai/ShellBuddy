#!/usr/bin/env bash
# Builds `libsqlite3.so` — SQLite3MultipleCiphers, the cipher build this app's
# databases are encrypted with — for HarmonyOS.
#
# Unlike `sbm_ffi` this is not optional and not a matter of taste: the app opens
# its stores through `package:sqlite3`, the file is encrypted with a key from
# the vault, and a plain SQLite would report the file as corrupt rather than
# unencrypted. The defines below therefore mirror what the `sqlite3` package's
# own build hook passes when `hooks: user_defines: sqlite3: source: sqlite3mc`
# is set — see `ohos/README.md` for how that list was taken.
#
# Usage, from the repository root:
#
#   DEVECO_SDK_HOME=... ohos/tools/build-sqlite3mc.sh [path/to/amalgamation-dir]
#
# Without an argument the amalgamation is fetched from SQLite3MultipleCiphers'
# releases into `.ohos-build/sqlite3mc/`.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "$here/env.sh"

root="$(cd "$here/../.." && pwd)"
cd "$root"

SQLITE3MC_VERSION="${SQLITE3MC_VERSION:-2.3.2}"
work="$root/.ohos-build/sqlite3mc"
src="${1:-}"

if [ -z "$src" ]; then
  mkdir -p "$work"
  if [ ! -f "$work/sqlite3mc_amalgamation.c" ]; then
    echo "build-sqlite3mc: fetching $SQLITE3MC_VERSION"
    url="https://github.com/utelle/SQLite3MultipleCiphers/releases/download/v$SQLITE3MC_VERSION/sqlite3mc-amalgamation-$SQLITE3MC_VERSION.zip"
    curl -fsSL "$url" -o "$work/amalgamation.zip"
    unzip -oq "$work/amalgamation.zip" -d "$work"
    # The archive unpacks into its own versioned directory.
    found="$(find "$work" -name 'sqlite3mc_amalgamation.c' | head -1)"
    if [ -z "$found" ]; then
      echo "build-sqlite3mc: no sqlite3mc_amalgamation.c in the archive" >&2
      exit 1
    fi
    src="$(dirname "$found")"
  else
    src="$work"
  fi
fi

if [ ! -f "$src/sqlite3mc_amalgamation.c" ]; then
  echo "build-sqlite3mc: $src/sqlite3mc_amalgamation.c not found" >&2
  exit 1
fi

# The cipher suite has to be compiled in, and the same one the other platforms
# get: a database written with ChaCha20 cannot be read by a build that only has
# the AES variants compiled in.
#
# SQLITE_TEMP_STORE=2 keeps temporary tables in memory: HarmonyOS gives an app
# no writable /tmp, and the default (a file beside the database) would fail on
# a large sort rather than slow down.
defines=(
  -DSQLITE_ENABLE_FTS5
  -DSQLITE_ENABLE_RTREE
  -DSQLITE_ENABLE_COLUMN_METADATA
  -DSQLITE_ENABLE_DBSTAT_VTAB
  -DSQLITE_ENABLE_JSON1
  -DSQLITE_ENABLE_MATH_FUNCTIONS
  -DSQLITE_THREADSAFE=1
  -DSQLITE_TEMP_STORE=2
  -DSQLITE_OS_OTHER=0
  -DSQLITE3MC_ENABLE_INTEGRATED_CRYPTO=1
  -DSQLITE3MC_ENABLE_CODEC_CHACHA20=1
  -DSQLITE3MC_ENABLE_CODEC_SQLCIPHER=1
  -DSQLITE3MC_ENABLE_CODEC_SYSTEM=1
  -DSQLITE_API=__attribute__\(\(visibility\("default"\)\)\)
)

out="$OHOS_LIBS_DIR/libsqlite3.so"

echo "build-sqlite3mc: compiling from $src"
"$OHOS_CLANG" \
  $OHOS_CFLAGS \
  "${defines[@]}" \
  -shared -fPIC \
  -o "$out" \
  "$src/sqlite3mc_amalgamation.c" \
  -lm -ldl -lpthread

"$OHOS_STRIP" --strip-unneeded "$out" || true
echo "build-sqlite3mc: $out ($(du -h "$out" | cut -f1))"
