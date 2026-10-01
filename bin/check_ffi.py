#!/usr/bin/env python3
"""FFI arity gate: every `func NAME(...)` declared in src/backend/bridge.x
that is defined in cpp_bridge/src/bridge.cpp must declare the same number
of parameters. The linker cannot catch these (C ABI passes garbage for
missing args); mismatches were the entire -g segfault saga (getStructLayout,
replaceElements, createVariantPart, createVariantMemberType, DILocation_get,
getFunction). Decls without a bridge.cpp definition (LLVM C API, etc.) are
not checked. Exit nonzero on mismatch. Called from cpp_bridge/x.sh."""
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
cpp = (root / "cpp_bridge" / "src" / "bridge.cpp").read_text()
x = (root / "src" / "backend" / "bridge.x").read_text()

cpp2 = re.sub(r"//[^\n]*", "", cpp)
cdefs = {}
for m in re.finditer(
    r"(?:^|[;}])\s*([\w:\<\>\*&][\w:\<\>\*& ]*?)\s*(\w+)\s*\(([^;{}]*?)\)\s*\{", cpp2
):
    name, params = m.group(2), re.sub(r"\s+", " ", m.group(3).strip())
    if name in ("if", "for", "while", "switch", "return", "catch", "const", "typedef"):
        continue
    n = 0 if params in ("", "void") else params.count(",") + 1
    cdefs[name] = (n, params[:100])

xdecls = {}
for m in re.finditer(r"func (\w+)\(([^)]*)\)", x):
    name, params = m.group(1), m.group(2).strip()
    n = 0 if params == "" else params.count(",") + 1
    xdecls[name] = n

bad = 0
for name in sorted(set(xdecls) & set(cdefs)):
    if xdecls[name] != cdefs[name][0]:
        print(f"FFI mismatch {name}: bridge.x declares {xdecls[name]}, bridge.cpp takes {cdefs[name][0]} ({cdefs[name][1]})")
        bad += 1
if bad:
    print(f"{bad} FFI arity mismatch(es)")
    sys.exit(1)
print(f"ffi ok ({len(set(xdecls) & set(cdefs))} shared symbols checked)")
