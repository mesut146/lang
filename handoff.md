# Handoff — x language toolchain (ownership focus)

Date: 2026-10-13. Main: `f3aa0b3`. Releases published: v1.11, v1.12, v1.13, v1.14.

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
- `doc/move_ptr_field.txt` (untracked): the `take(p.s); p.s = ...`
  debate note that motivated the heal rule.

## What's in the tree (main = f3aa0b3)

- Drops on by default; auto-drop owns all locals (`src/parser/ownership.x`,
  `own_*.x`, backend emitters).
- Named-scrutinee consume marks + arm-end rollback (inspect-only arms
  don't leak) + merge of escaped marks (`end_match`, if-let paths).
- Explicit-drop suppression set (manual `x.drop()` never double-fires;
  reassignment clears the record).
- `parse_obj` / lambda-call sites clone instead of moving payloads out.
- ~760 redundant manual `.drop()` calls stripped (560 plain locals +
  temp drops as bare calls). KEPT deliberately: Drop-glue internals
  (sole owners), loop bodies (per-iteration frees), field drops that
  heal by reassign, `no_drop`/`Drop::drop` forms, intentional test drops.
- Regression tests: `tests/own/12match_scrutinee`–`16inspect_use`,
  `tests/fail/deref_move_drop`, `tests/fail/field_move_drop`,
  `tests/normal/37-ptr-move`. (Old `17call_temp` removed: its getter is
  illegal under the design.)
- CI (`.github/workflows/main.yml`): tag-driven releases bootstrap from
  previous release; `MALLOC_CHECK_=3` on the x86_64 suite gate (turns
  silent heap corruption loud; musl/bionic ignore it).

## Known open holes (documented, not yet solved)

1. Temp-derived owners via calls: `if let V(s) = get(&o)` where `get`
   returns an alias is only safe today if `get` can't legally exist
   (it can't return `*o` anymore). True call-effect provenance (or
   `#[returns_alias]` annotations) is future work. See
   `consume_match_temp` LIMITATION comment.
2. Outer `let a = take_it(&o)` chains: silent double on heap types.
   Needs (1).
3. Conditional heals still error (unconditional-in-scope rule).
4. `v1.11`/`v1.12`-built analyzers diverge from `1.05`-built ones on
   corner logic (e.g. `vh` for borrows) — never root-caused; contained
   by validating every change through the strict triangle below.

## Validation protocol (mandatory before merging to main)

1. Develop on a worktree/branch, never on main.
2. Strict build: `./bin/stage2.sh ./x-toolchain-1.05-x86_64/bin/x <ver>`
   must exit 0 (surfaces use-after-move fallout as precise errors).
3. Full suite: `bin/test.sh <compiler> all` → `normal pass=55 xpass=0`
   (+ by-design `big_literal` XFAIL), `fmt: pass`, `opt: pass`.
4. Heap suite: same with `MALLOC_CHECK_=3`.
5. Self-host: `bin/stage1.sh <prev-release-toolchain>` must exit 0.
6. New ownership behavior needs a regression test that FAILS pre-fix
   (A-tracker counts in `tests/own/`, or `should-fail:` in `tests/fail/`).
7. Commit early/often and push branches (uncommitted work in /tmp has
   been wiped by restarts multiple times).

## Environment gotchas

- `bin/stage1.sh` does `rm -rf build/` at start: keep logs outside
  `build/`, never run two builds sharing it, binaries vanish (rebuild).
- `/tmp` is wiped on restarts: toolchains there must be re-downloaded
  (`gh release download`); repo-root `x-toolchain-1.05-x86_64`,
  `build/tmp` (LLVM), `cpp_bridge` lib survive.
- Pod memory limit is 16GB (`oom_kill` counter provable); full-module
  builds flakily OOM — retry (cache resumes), never parallel builds.
- `test.txt` (untracked) regenerates itself; leave it.
- `20_worker` is timing-sensitive; validate with repeated runs.
- Method-call turbofish on `*self` receivers doesn't resolve; use
  static `Type::method::<T>()` style.
- Do not release/publish without asking. Next release (v1.15) needs no
  bootstrap override (v1.14 builds main cleanly — but re-prove before
  touching the workflow).
