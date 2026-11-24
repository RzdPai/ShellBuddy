#!/usr/bin/env bash
# A linker driver that drops the GNU-ld flags the OHOS linker will not take.
#
# Cargo hands the linker whatever `cc`-style flags the target's crates ask for,
# and several crates in this tree ask in GNU terms: `ring`'s build script passes
# `-Wl,--version-script=...`, `-Wl,-z,relro`, `-Wl,--gc-sections` and
# `-Bstatic`, because on Linux that is what a hardened shared library looks
# like. OHOS links with lld, which understands some of that and rejects the
# rest — and rejects it with a message about the *object file* rather than the
# flag, which is what makes this cost an afternoon.
#
# Dropping them is safe in the direction that matters: each is a hardening or
# symbol-visibility hint. A library linked without them still loads; a library
# linked with them does not exist.
#
# Invoked by cargo as the target linker (`CARGO_TARGET_<TRIPLE>_LINKER`), so it
# is called with the compiler's own arguments and has to end in a real clang
# invocation.

set -euo pipefail

: "${OHOS_CLANG:?run through ohos/tools/env.sh}"
: "${OHOS_TRIPLE:?run through ohos/tools/env.sh}"

filtered=()
skip_value=0
for arg in "$@"; do
  if [ "$skip_value" = 1 ]; then
    skip_value=0
    continue
  fi
  case "$arg" in
    # Takes the next argument as its value.
    -z) skip_value=1 ;;
    -z*) ;;
    -Xlinker) skip_value=1 ;;
    # Self-contained, unsupported by lld on this target.
    --version-script=*|--dynamic-list=*|--as-needed|--no-as-needed) ;;
    --gc-sections|--no-gc-sections|--eh-frame-hdr) ;;
    -Bstatic|-Bdynamic|-Bgroup) ;;
    --hash-style=*|--build-id=*|--sort-section=*) ;;
    # Everything else, including -Wl, forms clang understands, goes through.
    *) filtered+=("$arg") ;;
  esac
done

exec "$OHOS_CLANG" --target="$OHOS_TRIPLE" "${filtered[@]}"
