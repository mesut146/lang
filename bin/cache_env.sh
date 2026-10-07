#!/bin/bash
# cache_env.sh <out_dir>: the compiler -cache keys on sources only, not on
# codegen-affecting env (drop_enabled/drop_lhs_enabled/XOPT, the baked-in
# version string, and the target selectors). Switching flags with a warm
# out dir silently reuses foreign objects (stale drops, wrong -O level,
# stale version). Stamp the flag signature
# next to the cache and wipe on mismatch. Call right after out_dir is set.
dir=$(dirname $0)
if [ -z "$1" ]; then
  echo "provide out dir" && exit 1
fi
out_dir=$1
sig="drop_enabled=${drop_enabled:-} drop_lhs_enabled=${drop_lhs_enabled:-} XOPT=${XOPT:-} version=${version:-} XTERMUX=${XTERMUX:-} ARCH=${ARCH:-} target_triple=${target_triple:-}"
stamp="$out_dir/.cache_flags"
mkdir -p "$out_dir"
if [ -f "$stamp" ]; then
  old=$(cat "$stamp")
  if [ "$old" != "$sig" ]; then
    echo "flag change, wiping cache in $out_dir"
    echo "  was: $old"
    echo "  now: $sig"
    rm -rf "$out_dir" && mkdir -p "$out_dir"
  fi
fi
echo "$sig" > "$stamp"
