# Handoff — x language toolchain (ownership focus)

Date: 2026-10-17. Main: `3d50cfb`. Releases published: v1.11 – v1.15.

## Design contract (user-approved, do not relitigate without asking)

Ownership only — no Rust-like borrows:
- The compiler manages frees: every owned buffer freed exactly once. No
  double-free, no dangling. Leaks are the safe direction (sound, silent).
- Borrows (`&x`) are free and untracked. Borrowing never consumes.
- Use-after-move MUST error (ownership problem, not borrow problem).
- Match arms must agree: if any arm moves data out, the scrutinee is
  consumed on all paths; post-use errors.
- Move-out-of-pointer-to-drop is invalid unless healed: `take(p.s)` /
  `*p` on drop types must reassign the same place before scope end
  (`p.s = ...`, `*p = ...`). Checked at every scope end + return.
  `return *o` can never heal, so it always errors.
- `ptr::deref` is the only legal route to read through a pointer into a
  binding; its results are plain bindings the user owns (unsafe, user
  responsibility — analyzer tracks nothing special).
- `Box<T>` carries `#drop`; `*boxed` follows the same heal rule.
- `move_ptr_field` flag and `check_ptr_field` left untouched (legacy).

## What's in the tree (main = 0968605)

- Drops on by default; auto-drop owns all locals (`src/parser/ownership.x`,
  `own_*.x`, backend emitters).
- Named-scrutinee consume marks + arm-end rollback (inspect-only arms
  don't leak) + merge of escaped marks (`end_match`, if-let paths).
- Explicit-drop suppression set (manual `x.drop()` never double-fires;
  reassignment clears the record).
- `parse_obj` / lambda-call sites clone instead of moving payloads out.
- Manual drops: 164 dead-after temps + 27 reassign temps + 2 anonymous
  temps stripped; `impl Drop` for String/Protos/Context deleted
  (derived glue owns); 6 remain, all load-bearing (`impl Drop for Own`
  for `Logger::exit`, Drop-derive codegen string). See doc/ownership.txt.
- Drop-on-assign via `drop_lhs` (struct path; hardened to never panic on
  untracked places); drop-then-reassign manuals all stripped.
- `#[returns_alias(p)]` closes the extern-alias hole (owner consumed at
  call, post-uses error).
- B2: side-effect-only manual `Drop` bodies gain derived field frees.
- Regression tests: `tests/own/12match_scrutinee`–`19wrap`,
  `tests/fail/` (moves, ptr-moves, alias, bad placeholder),
  `tests/normal/37-ptr-move`, `38-ptr-cond-heal`. (Old `17call_temp`
  removed: its getter is illegal under the design.)
- `get_line` past EOF returns empty (error paths hung on snippet
  buffers before this; pinned by `format_bad_placeholder`).
- CI (`.github/workflows/main.yml`): tag-driven releases bootstrap from
  previous release; `MALLOC_CHECK_=3` on the x86_64 suite gate (turns
  silent heap corruption loud; musl/bionic ignore it).

## Resolved since (in tree)

- Builder divergence: CLOSED 2026-10-13. Same sources built by 1.05,
  v1.14 and v1.11 produce identical ownership verdicts on all of
  `tests/own/*`, `tests/fail/*`, 37/38 and a borrow-flow probe, plus
  identical `own_verbose` traces (1.05 vs v1.14). The old `vh`-for-borrows
  divergence no longer reproduces; `visit_ref` (`src/resolver/resolver.x:2442`)
  propagates `vh` through `&` deterministically on all lineages.
  Strict-triangle validation stays mandatory regardless.

- Temp-derived owners: closed by construction, not provenance. Since
  `return *o` on drop types is rejected, legal callees cannot hand out
  owned aliases of borrows (only `ptr::deref`/extern can, both explicit
  user responsibility). No borrow-marking of call args exists anymore.
- Conditional heals: `if(c){ take(p.s); } p.s = x;` compiles via record
  bubbling to parent scopes; jumps/returns still check locally.
- `Box<T>` deref follows the same heal rule (`#drop` attribute).
- v1.15 cut from here (heal/bubble/strip/alias/B2/tests/heap-gate batch).

- Discarded macro results + if-let temporaries (2026-10-17, b0e399e):
  the emitter registers a format()/`?` macro block's result temp as an
  owned object (track_result_temp) and drop_obj uses the resolved result
  type recorded on FormatInfo (the macro call's own RType is a bare,
  decl-less String, so drop glue cannot resolve it); if-let drops its
  owned scrutinee on the non-matching path (ElseScrutinee); Box::unwrap
  frees its cell. Tests: tests/own/20qmark_discard, 21iflet_temp;
  tests/leak/* plus the `bin/test.sh leak` valgrind gate (wired into
  `all`). Validated by previous-release (v1.15) bootstrap + full suite
  (MALLOC_CHECK_=3, wiped dirs: normal 63/0, fmt/leak/opt pass).

- Elided `Drop::drop(arg)` argument (2026-10-17, db58ca6): a call whose
  argument type has no drop glue was emitted as nothing at all, so the
  argument expression was skipped too. But `Box<T>::drop` is literally
  `Drop::drop(self.unwrap())` and `unwrap` frees the cell, so every
  `Box<T>`/`Ptr<T>` with a glue-less payload (prims, plain structs)
  leaked its cell -- a regression from b0e399e, which moved the `free`
  from `Box::drop` into `unwrap`. Internal instance: `Ptr<ElseScrutinee>`
  in `Emitter::visit_iflet` (24B per temp-scrutinee if-let). Fix:
  `self.visit(mc.args.get(0))` in both elision branches. Test:
  tests/leak/box_nondrop.x (Box<i32> + Box<Plain>; fails pre-fix).

- Compiler-internal leak crumbs (2026-10-17, CLOSED -- bootstrap
  artifact, not source): the ~38KB Type::clone/format records first
  opened after b0e399e are NOT source leaks. Codegen for the compiler's
  own modules (e.g. `Box<ElseScrutinee>::drop`, an elided `Drop::drop`)
  is produced by the *previous* compiler, so a new compiler built by a
  pre-fix release still leaks internally although its source is fixed.
  Measured on the same source: v1.15 -> S1 = 11 definite records (7
  artifacts, incl. the 24B ElseScrutinee); S1 -> S2 = 4 (LLVM-internal
  only); S2 -> S3 byte-identical. Rule: measure compiler-internal leaks
  only on a binary whose objects were generated by an already-fixed
  compiler (two bootstrap rounds), never on a prev-release-bootstrapped
  one. The user-program leak gate (`bin/test.sh leak`) was always valid.

- Per-field B2 + empty-string OOB (2026-10-17, on `own-leak-b2`): the
  B2 "manual Drop touches self -> no derived frees" rule was an
  over-approximation; it now scans per field (name a field -> suppress
  only that field; bare self/lambda -> suppress all), which never frees
  less than before. This fixes `Mutex<T>`, whose drop names only
  `self.lock`, leaking `val` (400B in `20_worker`, whose todo queue is
  `Mutex<List<Job>>`). Separately, `str::real_len` did
  `self.get(self.len()-1)` = buf[-1] for an empty string (1-byte OOB
  read, hit inside the compiler too when a HashMap key compared against
  an empty String); it now returns 0 early. Tests: `tests/own/22b2partial`
  (drop-count; failed pre-fix) and `tests/leak/{mutex_payload,empty_streq}.x`
  (valgrind gate; 10B+40B leak and an invalid read pre-fix). Also noted:
  valgrind had to be reinstalled this session, and the big `src/backend`
  valgrind compile SIGBUSes (environment), so use the `src/std` module
  compile for compiler-internal measurements.

## Known open holes (documented, not yet solved)

Ownership residuals: none open as of db58ca6 (see doc/ownership.txt
ledger). Open: language features (doc/todo).

## Validation protocol (mandatory before merging to main)

1. Develop on a worktree/branch, never on main.
2. Strict build: `./bin/stage1.sh <prev-release-toolchain> <ver>`
   must exit 0 (previous release is the reference builder since
   2026-10-13; 1.05 retired -- it predates drop_lhs and cannot compile
   current sources, e.g. borrow payloads off field bases). Surfaces
   analyzer fallout as precise errors.
3. Full suite: `bin/test.sh <compiler> all` → `normal pass=63 xpass=0`
   (+ by-design `big_literal` XFAIL), `fmt: pass`, `leak: pass`,
   `opt: pass`.
4. Heap suite: same with `MALLOC_CHECK_=3`.
5. Self-host is subsumed by (2) -- same command. Keep the name for
   the gate: the binary from (2) must run the suite, not just build.
6. New ownership behavior needs a regression test that FAILS pre-fix
   (A-tracker counts in `tests/own/`, or `should-fail:` in `tests/fail/`);
   heap-only (raw malloc) leaks instead need a `tests/leak/*.x` case and
   the valgrind `bin/test.sh leak` gate (exit-code based; never grep the
   valgrind summary). Prove the pre-fix failure by stashing the fix,
   rebuilding, and watching the gate go red.
7. Commit early/often and push branches (uncommitted work in /tmp has
   been wiped by restarts multiple times).

## Environment gotchas

- `bin/stage1.sh` does `rm -rf build/` at start: keep logs outside
  `build/`, never run two builds sharing it, binaries vanish (rebuild).
- `-cache` keys on sources only, not on the compiler -- so changing the
  bootstrap reuses stale objects. `rm -rf build/stage2_out` whenever the
  bootstrap changes (incl. stash/pop: a popped source keeps its old mtime
  and the object looks fresh). Compiler-internal valgrind leaks are only
  meaningful on a binary whose objects were generated by an already-fixed
  compiler (two bootstrap rounds), never on a prev-release build.
- `/tmp` is wiped on restarts: toolchains there must be re-downloaded
  (`gh release download`); repo-root `x-toolchain-1.05-x86_64`,
  `build/tmp` (LLVM), `cpp_bridge` lib survive.
- Pod memory limit is 16GB (`oom_kill` counter provable); full-module
  builds flakily OOM — retry (cache resumes), never parallel builds.
- `test.txt` (untracked) regenerates itself; leave it.
- `20_worker` is timing-sensitive; validate with repeated runs.
- Method-call turbofish works, including runtime (`to_list<i32>(41)`
  probed green on v1.15).
- Do not release/publish without asking. Next release (v1.16) bootstraps
  from v1.15 — re-prove before touching the workflow.
- `pkill -f` matches its own command line: kill hung compilers by exact
  PID from a pidfile, never by pattern.
- Always verify `build/stage2` freshness (`-v` + timestamp) before
  trusting probe results; a stale binary once cost a full debug cycle.
- Hang diagnosis ladder (all needed for the `{:` format hang): own_verbose
  traces → file-appended markers (never `print`, buffering eats tails)
  → `strace -f` as parent (works where gdb attach is blocked by
  ptrace_scope) → error-path audit. Flat RSS + no syscalls = pure spin.
- Unparsable `{...}` placeholders must fail loud, never hang (pinned by
  `format_bad_placeholder`; root cause was `get_line` past EOF).
