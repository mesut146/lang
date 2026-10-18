# Handoff — x language toolchain (ownership focus)

Date: 2026-10-18. Main: `4311e77` (v1.16 released at `9ca614c`; next release v1.17 bootstraps from v1.16). Releases: v1.11 – v1.16.

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

## What's in the tree (main = 4311e77)

- Drops on by default; auto-drop owns all locals (`src/parser/ownership.x`,
  `own_*.x`, backend emitters).
- Named-scrutinee consume marks + arm-end rollback (inspect-only arms
  don't leak) + merge of escaped marks (`end_match`, if-let paths).
- Explicit-drop suppression set (manual `x.drop()` never double-fires;
  reassignment clears the record).
- `parse_obj` / lambda-call sites clone instead of moving payloads out.
- Manual drops: 164 dead-after temps + 27 reassign temps + 2 anonymous
  temps stripped; `impl Drop` for String/Protos/Context deleted
  (derived glue owns). The last 27 explicit drops outside `impl Drop`
  bodies were stripped 2026-10-18 (fs/ops/printer/map/option/hashmap/
  formatter): auto-drop owns locals+params on every exit path, and
  drop-on-assign owns `p.f=x`/`*p=x`. The only remaining manual drop is
  the type-erased `Any` glue (`release_compile_args`), which cannot be
  auto-dropped. See doc/ownership.txt.
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

- Parallel compile + Any drop glue (2026-10-17, on `own-leak-jobs`): two
  pre-existing `-j` bugs (both in v1.15), both fixed. (a) every `-j`
  build failed: the job runner closed each child with `eat_close`
  (pclose) without draining its stdout, and glibc pclose closes the read
  end before waitpid, so the child -- always printing "compiling ..." --
  died with SIGPIPE -> "failed to compile" + exit(1). A bare C
  `popen("echo hi","r"); pclose(f)` reproduces (rc=13); every other
  Process::run site already used `read_close()`. (b) the job arg then
  leaked: `CompileArgs` (owns `file: String`) is boxed into an `Any`,
  whose auto-drop is type-erased, so the file clone leaked per job
  (valgrind `-j 4` parent: 81 B / 3 blocks at `String::clone <-
  compile_dir_thread`; 0 after). Fix for (b): `Any` now carries a per-T
  `drop_f: func(i8*) => void`; the language cannot materialize T's glue
  at a generic site (generic fn/method refs and generic lambdas are all
  rejected -- verified), so the constructing site hands it in:
  `Any::new<T>(v, glue)`, `Worker::add_arg_heap<T>`, and the compiler's
  `release_compile_args`. `Any::new<T>(v)` keeps a no-op glue
  (`drop2<T>` still manual). Tests: `inc_all` now also builds
  `tests/incremental_test` with `-j 4` (fails pre-fix);
  `tests/own/23jobarg.x` (A-tracker: boxed arg drops once) and
  `tests/leak/any_payload.x` (valgrind: payload String freed) fail to
  compile pre-fix. Triangle S1!=S2 (v1.15 codegen differs), S2==S3;
  full suite green on S1 and S3 (`normal pass=63 xpass=0`, fmt/leak/opt
  pass); the `-j 4` parent and the `src/std` module compile are
  valgrind-clean (LLVM-internal roots only).

- Manual-drop sweep (2026-10-18, on `own-strip-manual-drops`): the
  hand-written `Drop::drop` / `.drop()` calls left outside `impl Drop`
  bodies (and `Any::drop2`) were removed -- 27 sites in 7 files -- now
  that drop-on-assign has matured. Two families: (a) "free a
  local/param before returning" (fs 8, ops 6, printer 4, map
  get_pair_or 2, hashmap 2, formatter 1); (b) "drop-old +
  std::no_drop(place) + assign" (map add 2, option set/reset 2).
  Removal is a no-op: owned locals *and* owned params drop on every
  exit path -- early `return`, and `return` from inside a loop
  (IR-proven: `String__drop_String` right before each `ret`) -- and
  drop-on-assign fires for `p.f = x` / `*p = x` on concrete, generic
  and enum places (IR-proven). The one place form it did not cover at
  the time -- the explicit deref member `ptr::deref!(p).f = x`
  (untracked -> leak) -- was closed right after (next entry); none of
  the swept sites used it. The `Any` glue in
  `backend/compiler.x` (`release_compile_args`) stays -- type-erased,
  cannot be auto-dropped. Regression: tests/own/24ptrassign.x (pins
  pointer-field, pointer-deref, Map::add same-key, get_pair_or hit).
  Full suite green on S1 and S3 (`normal pass=63 xpass=0`, fmt/leak/opt
  pass); triangle S1==S2==S3 byte-identical (source-level change,
  codegen logic untouched).

- `ptr::deref!` member place (2026-10-18, same branch): the sweep entry
  above noted `ptr::deref!(p).f = x` as the one shape drop-on-assign
  did not cover -- `Rhs::new` types a field place only when its scope
  has a `vh`, and the deref macro's RType has none, so `drop_lhs` saw
  `EXPR` and skipped it (leak). Fix: `Rhs::new` now sees through a
  `ptr::deref!` scope, so `ptr::deref!(X).f` is `FIELD{X, f}` -- the
  same place as `X.f`. `drop_lhs` and `do_move` share the key, so a
  live value drops on assign and a moved-out one is skipped (the heal
  assign drops nothing). Bare `ptr::deref!(p)` stays EXPR/untracked.
  Regression: tests/own/24ptrassign.x `deref_macro` (leaked pre-fix) +
  `deref_macro_move`. Full suite green on F1 and F3 (`normal pass=63
  xpass=0`, fmt/leak/opt pass); triangle F1==F2==F3 byte-identical.

- Field of an owned temporary (2026-10-18, same branch): `f().field = v`
  leaked the overwritten value -- `drop_lhs` bailed on any `Rhs::EXPR`
  place (verified: probe `mk().s = format(..)` leaked the `String` built
  in `mk`; valgrind 10 bytes definitely lost, no drop before the field
  store). Fix: `drop_lhs` now recognizes a field of a registered temp
  *object* -- an owned temporary the engine already drops at scope end.
  `place_root` descends nested field accesses to the base and
  `drop_temp_field` matches it against the scope's objects (mirrors
  is_temp_scrutinee's walk); the field is live by construction, so the
  old value drops at the assign while the temporary's own drop later
  frees only the new value (exactly once). Other untracked bases (bare
  `ptr::deref!` of an untracked place, extern results) keep the silent
  no-op. Regression: tests/own/25tempassign.x (direct + nested; fails
  pre-fix: assertion 0 != 1). Full suite green on FIX1/FIX3
  (`normal pass=63 xpass=0`, fmt/leak/opt pass); triangle FIX1==FIX2==
  FIX3 byte-identical.

- for-each `continue` + trailing `return` codegen (2026-10-18, same
  session): the for-each desugar ends its `while(true)` body with the
  opaque `std::internal_block!(id)`; `Exit::get_exit_type` reads a
  `MacroCall` as NONE, so a body ending in `return`/`break`/`continue`/
  `panic` looked fall-through and `visit_while` emitted the loop
  back-edge after the already-terminated block -> "Module verification
  failed! Terminator found in the middle of a basic block". (Hit while
  compiling the literal first draft of the temp-field fix above, which
  used `continue` in a for-in body.) Fix: `Emitter::body_exit`
  (`src/backend/stmt_emitter.x`) sees through the placeholder -- when a
  loop body's last statement is that macro, it takes the exit of the
  mapped block from the resolver's `block_map`; `visit_while` and
  `visit_for` use it to decide the back-edge. `continue`/`break`/plain
  bodies are unchanged. Regression: tests/normal/39-foreach-continue.x
  (continue with and without a trailing return; failed pre-fix at
  compile). Full suite green on N1/N3 (`normal pass=64 xpass=0`,
  fmt/leak/opt pass); triangle N1==N2==N3 byte-identical.

- Arrays and tuples as owners (2026-10-18, same session): an array or
  tuple value whose element type needs dropping crashed the compiler:
  `Emitter::drop_force` called `get_drop_proto`, which does
  `get_decl(rt).unwrap()` -- an array/tuple has no decl, so `None`
  ("unwrap on None", option.x:26). Reported with `let x =
  [String::new("a"), String::new("b")];`. Fix: `drop_force`
  (`src/backend/emitter.x`) drops aggregate elements element-wise and
  recurses; the element count is a compile-time constant, so the loop is
  unrolled (straight-line, no new blocks). The literal emitters
  (`src/backend/expr_emitter.x`) also mark each element source moved
  (`do_move`, mirroring `set_fields`) -- without that every source temp
  was dropped a second time (valgrind: same allocation freed twice).
  Two adjacent holes the feature exposed were closed too: a repeated
  array with a drop element type is a clean error in
  `Resolver::visit_array` (`[e; n]` copies one value into n slots = n
  aliases freed n times), and a move out of an index place is refused in
  `Own::do_move` (`send(arr[0])`; index places are untracked). `Own::
  check_partial` learned tuples instead of panicking in `get_decl`, so
  partial tuple moves follow the struct rule (move every drop element,
  or error). Regression: tests/own/26arrtuple.x (pre-fix it does not
  compile) + tests/fail/array_elem_move.x and
  tests/fail/array_repeated_drop.x. Full suite green on F1/F3 (`normal
  pass=66 xpass=0`, own/fmt/leak/opt pass); triangle F1==F2==F3
  byte-identical. Array-element overwrites stay untracked (leak), as
  before; the aggregate-*field* gap that note listed is closed by the
  next entry.

- Aggregate fields as owners (2026-10-18, same branch): closes the
  "still open" note above. `derive.x` emits `Drop::drop(self.f)` for an
  array/tuple field (`is_struct` is true for both) and a decl-less type
  has no impl to resolve -- "get_impl type not covered: [String; 2]".
  Fix: `Resolver::visit_call` returns void for an array/tuple argument
  of `Drop::drop` (skips impl resolution); `Emitter::visit_call`'s
  `Drop::drop` case then drops the argument's elements in place via
  `drop_force` on the argument's address and records the argument moved
  (`do_move`), exactly like the normal arg path. The move mark matters
  for enum variant fields: the generated drop binds the payload to a
  local that the engine auto-drops at arm end -- without the mark the
  payload is freed twice (valgrind: same allocation freed twice);
  `own_visitor.x` mirrors the mark so else-path/arm-merge re-analysis
  agrees. Also fixed: `Resolver::is_cyclic` panicked on a *tuple* field
  (`get_decl(tuple).unwrap()`, "unwrap on None") -- it now recurses into
  tuple elements like it does for arrays (`Type::is_tuple`, ast.x). The
  generated drop source is unchanged, so derive stays simple: the
  emitter's aggregate drop is the single place that knows an array/tuple
  has no decl. Regression: tests/own/27aggfield.x (struct array field,
  tuple field, nested array field, enum variant array field; pre-fix it
  does not compile). Still open (pre-existing): a *self-referential*
  aggregate field (`struct S{ t: (S, i32); }`) overflows the stack in
  `DropHelper::is_drop_type`/`is_drop_decl` (SIGSEGV, same pre-fix) --
  invalid type, should be a clean "cyclic type" error.

- Array elements as places (2026-10-18, same branch): closes the last
  documented array/ownership gap, in three parts. (1) `arr[i] = v` leaked
  the old element -- `drop_lhs` only knew struct fields, so an index place
  fell through as an untracked expression. It now drops the overwritten
  value for any place rooted at an index (`arr[i] = v`, `arr[i].f = v`,
  `arr[i].f[0] = v`), consulting the element's state first so an overwrite
  into an already moved-out element is a no-op (`Own::is_index_place` /
  `Own::index_root`). (2) `send(arr[0])` was refused; a *constant* index
  into a local array is a tracked place now (`Rhs::INDEX{scp, idx}`,
  produced by `Rhs::new` only for an `Expr::Name` base of array type with a
  literal index), so the element behaves like a struct field: moving one
  out suppresses the array's element-wise drop, and `check_partial`
  requires *every* drop element to move (the all-fields rule, enumerating
  array slots). Reassigning a moved element revives it, as for fields.
  (3) `for x in <array>` failed outright ("get_impl type not covered:
  [i32; 3]"); `Resolver::visit_for_each` now iterates a slice *view* of the
  array (`arr[0..N]`), dereferencing a pointer to an array first
  (`(*p)[0..N]`, since `p[0..N]` slices the temporary pointer and dangles).
  By value it copies, so a drop element type errors as it already does for
  slices; by reference each `x` points into the array. Still refused:
  dynamic index, slice, pointer base, nested array, and a *field* of an
  element -- `send(p[0].a)` used to compile and drop that field twice
  (`A::drop 1` twice), now a clean "cannot move out of an array element"
  (`Own::do_move` refuses any index-rooted place that is not `Rhs::INDEX`).
  Tests: tests/own/28arrassign.x, tests/own/29arrmove.x,
  tests/normal/40-array-foreach.x, tests/fail/array_elem_move.x (dynamic
  index now), tests/fail/array_elem_field_move.x. Residual (documented):
  writing into an element (or a field of one) after it was moved out is not
  diagnosed -- no double free, but the new value can leak.

## Known open holes (documented, not yet solved)

Ownership residuals: none open as of 4311e77 (see doc/ownership.txt
ledger). Remaining deliberate silent no-ops: bare `ptr::deref!` of an
untracked place, and `extern`/unsafe aliases (no body to check). Open:
language features (doc/todo).

Compile gaps (pre-existing, not yet fixed):
- A *self-referential* aggregate field (`struct S{ t: (S, i32); }`)
  overflows the stack inside `DropHelper::is_drop_type`/
  `is_drop_decl` mutual recursion -- SIGSEGV during `handle_attr`,
  before the field validator runs. Same pre-fix. The type is invalid
  (infinite size) and should be a clean "cyclic type" error.
  Non-self-referential arrays/tuples as fields work (owner entry above).
- Array-element places *are* tracked now (constant index into a local
  array; see the owner entry above), so `arr[i] = v` no longer leaks and
  `send(arr[0])` works. What stays refused, with a clean error, is any
  index place the state cannot name: a dynamic index, a slice, a pointer
  base, a nested array, and a field of an element. One residual: writing
  into an element (or a field of one) after it was moved out is not
  diagnosed -- the stale value is not dropped (so no double free), but
  the new value can leak.
- Not a compiler bug, but a harness constraint worth knowing: the
  `tests/normal` runner compiles with `-stdpath src` and no `-std`, so
  no std lib is linked -- only generic std code monomorphised into the
  user object resolves. A test that references a non-generic std symbol
  fails to link: `print("x {}\n", 1)` -> `Fmt__new`; `import std/string`
  + `String::new` -> `String__new`; any `List<T>` use ->
  `Fmt__drop_Fmt` (`List<T>::get_malloc`'s `panic("invalid size
  {}", ..)`). The `std_all` path passes `-flags $LIB_STD` and is
  unaffected. So a `tests/normal` regression must stick to builtins +
  monomorphised generics (as tests/normal/39-foreach-continue.x does: a
  slice loop via `import std/it`, literal print).

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
- Do not release/publish without asking. Next release (v1.17) bootstraps
  from v1.16 — re-prove before touching the workflow.
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
