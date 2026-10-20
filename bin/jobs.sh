#!/bin/bash
# default worker count for parallel per-file compilation (-j).
# Each worker is a full compilation (parser + resolver + emitter + LLVM
# module), so the count is capped: a 64-core host should not start 64 of them.
# XJOBS overrides the default; XJOBS=1 forces the serial path.
if [ ! -z "$XJOBS" ]; then
  echo "$XJOBS"
  exit 0
fi
n=$(nproc 2>/dev/null || echo 4)
if [ "$n" -gt 8 ]; then
  n=8
fi
if [ "$n" -lt 1 ]; then
  n=1
fi
echo "$n"
