#!/bin/bash
#async sampling profiler for x-built binaries: LD_PRELOAD backtrace sampler,
#offline symbolize + top-function report. No root/ptrace/perf required.
#usage: SPROF_DIR=/tmp/opencode bin/sprof.sh <binary> <args...>
dir=$(dirname $0)
so=/tmp/opencode/libsprof.so
if [ ! -f "$so" ]; then
  gcc -shared -fPIC -O2 -o "$so" "$dir/sprof.c" || exit 1
fi
bin=$1; shift
[ -x "$bin" ] || { echo "usage: $0 <binary> <args...>"; exit 1; }
export SPROF_DIR=${SPROF_DIR:-/tmp/opencode}
mkdir -p "$SPROF_DIR"
rm -f "$SPROF_DIR"/prof.*.bin
LD_PRELOAD="$so" "$bin" "$@"
child=$?
#the long-lived (largest) dump is the profiled process; linker children
#inherit LD_PRELOAD but exit fast and leave tiny files.
prof=$(ls -S "$SPROF_DIR"/prof.*.bin 2>/dev/null | head -1)
[ -n "$prof" ] || { echo "no profile captured"; exit $child; }
grep -v -- '---' "$prof" > "$SPROF_DIR/addrs.txt"
addr2line -e "$bin" -f -C < "$SPROF_DIR/addrs.txt" > "$SPROF_DIR/syms.txt" 2>/dev/null
python3 - "$SPROF_DIR/syms.txt" <<'EOF'
import sys
from collections import Counter
c = Counter()
fn = None
for line in open(sys.argv[1]):
    line = line.strip()
    if fn is None:
        fn = line
    else:
        c[fn] += 1
        fn = None
tot = sum(c.values())
for f, n in c.most_common(30):
    print(f"{n:6d} {100*n/tot:5.1f}%  {f[:100]}")
print(f"samples: {tot} frames from {sys.argv[1]}")
EOF
exit $child
