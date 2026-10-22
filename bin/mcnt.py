#!/usr/bin/env python3
"""Summarize a bin/mcnt.c dump (one run, all processes).

    bin/mcnt.py /tmp/alloc.txt --bin ./build/stage1

Prints totals, the per-module (caller) split, the size histogram, the top
allocation call sites inside the compiler binary (resolved with nm), and,
if the run sampled stacks (MCNT_SAMPLE_OFF), the hottest call chains.
"""
import argparse
import bisect
import collections
import re
import subprocess
import sys


def parse(path):
    blocks = []
    cur = None
    for line in open(path, errors="replace"):
        if line.startswith("MCNT t=") and "prog=" in line:
            cur = {"hdr": line.strip(), "mods": [], "sizes": [], "ips": []}
            blocks.append(cur)
        elif line.startswith("MCNT mod") and cur is not None:
            cur["mods"].append(line.strip())
        elif line.startswith("MCNT size") and cur is not None:
            cur["sizes"].append(line.strip())
        elif line.startswith("MCNT ip") and cur is not None:
            cur["ips"].append(line.strip())
    return blocks


def num(hdr, key):
    m = re.search(r"\b" + key + r"=(\d+)", hdr)
    return int(m.group(1)) if m else 0


class Symbols:
    def __init__(self, path):
        self.addrs, self.names = [], []
        if not path:
            return
        out = subprocess.run(["nm", "-n", "--defined-only", path],
                             capture_output=True, text=True).stdout
        for line in out.splitlines():
            parts = line.split(None, 2)
            if len(parts) == 3 and parts[1] in ("T", "t", "W", "w"):
                try:
                    self.addrs.append(int(parts[0], 16))
                except ValueError:
                    continue
                self.names.append(parts[2])

    def pretty(self, name):
        name = name.replace("_home_mesutdogansoy_lang_", "")
        name = re.sub(r"src_(\w+?)_([\w]+)_x_", r"src/\1/\2.x:", name)
        return name.replace("$LT", "<").replace("$GT", ">").replace("$P", "*")

    def resolve(self, off):
        if not self.addrs:
            return "?"
        i = bisect.bisect_right(self.addrs, off) - 1
        if i < 0:
            return "?"
        return self.pretty(self.names[i]) + f" +{off - self.addrs[i]}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dump")
    ap.add_argument("--bin", default=None, help="compiler binary, for symbols")
    ap.add_argument("--top", type=int, default=15)
    args = ap.parse_args()

    blocks = parse(args.dump)
    if not blocks:
        sys.exit("no MCNT blocks: was the run built with bin/mcnt.c?")
    tot = collections.Counter()
    for b in blocks:
        for k in ("malloc", "realloc", "calloc", "free", "bytes",
                  "realloc_bytes", "calloc_bytes"):
            tot[k] += num(b["hdr"], k)
    allocs = tot["malloc"] + tot["realloc"] + tot["calloc"]
    print(f"processes={len(blocks)}")
    print(f"allocations={allocs} (malloc={tot['malloc']} realloc={tot['realloc']} "
          f"calloc={tot['calloc']}) frees={tot['free']}")
    print(f"bytes={tot['bytes'] + tot['realloc_bytes'] + tot['calloc_bytes']}")

    mods = collections.Counter()
    modb = collections.Counter()
    for b in blocks:
        for m in b["mods"]:
            mm = re.match(r"MCNT mod\s+(\S+)\s+n=(\d+)\s+bytes=(\d+)\s+free=(\d+)", m)
            if mm:
                mods[mm.group(1)] += int(mm.group(2))
                modb[mm.group(1)] += int(mm.group(3))
    print("\nby module (caller):")
    for name, n in mods.most_common():
        if n:
            print(f"  {name:<24} allocs={n:<9} bytes={modb[name]}")

    sizes = collections.Counter()
    sizeb = collections.Counter()
    for b in blocks:
        for s in b["sizes"]:
            m1 = re.match(r"MCNT size\s+(\d+)\s*-\s*(\d+)\s+n=(\d+)\s+bytes=(\d+)", s)
            m2 = re.match(r"MCNT size\s+2\^(\d+)\+\s+n=(\d+)\s+bytes=(\d+)", s)
            if m1:
                k = f"{m1.group(1)}-{m1.group(2)}"
                sizes[k] += int(m1.group(3))
                sizeb[k] += int(m1.group(4))
            elif m2:
                k = f"2^{m2.group(1)}+"
                sizes[k] += int(m2.group(2))
                sizeb[k] += int(m2.group(3))
    small = sum(n for k, n in sizes.items() if "-" in k)
    print(f"\nby size class (<=511B: {small} allocs = {100 * small / allocs:.0f}%):")
    def skey(k):
        return int(k.split("-")[0]) if "-" in k else 10 ** 9
    for k in sorted(sizes, key=skey):
        print(f"  {k:<12} allocs={sizes[k]:<9} bytes={sizeb[k]}")

    ips = collections.Counter()
    for b in blocks:
        for i in b["ips"]:
            mi = re.match(r"MCNT ip off=(\S+) n=(\d+)", i)
            if mi:
                ips[int(mi.group(1), 16)] += int(mi.group(2))
    syms = Symbols(args.bin)
    print(f"\ntop allocation sites in the binary ({100 * sum(ips.values()) / allocs:.0f}% "
          f"of all allocations are attributed to sites):")
    for off, n in ips.most_common(args.top):
        print(f"  {off:#8x} n={n:<9} {100 * n / allocs:4.1f}%  {syms.resolve(off)}")

    chains = collections.Counter()
    for line in open(args.dump, errors="replace"):
        if line.startswith("MCNT bt"):
            frames = [int(x, 16) for x in line.split()[2:]]
            frames = [f for f in frames if f < 0x200000]  # main binary only
            chains[" <- ".join(syms.resolve(f) for f in frames[2:9])] += 1
    if chains:
        total = sum(chains.values())
        print(f"\ntop sampled stacks ({total} samples, 1/256 at MCNT_SAMPLE_OFF):")
        for c, n in chains.most_common(args.top):
            print(f"  {n:5d} ({100 * n / total:4.1f}%)  {c}")


if __name__ == "__main__":
    main()
