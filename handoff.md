# Handoff — x language toolchain (ownership focus)

Date: 2026-10-21. Main: `ba6af50` (owns `681a8cc` array places, place
use-after-move `163359c`/docs `f478e0e`, cyclic-type fix `8b6190b`/docs
`3105e7f`, custom printer `{::Trait}`, trait-aware method mangling, the
`bin/build.sh` two-stage link fix, delegate-derive closed, source path
normalization / `-remap-path-prefix`, `-trace` codegen + `-j` flag forwarding,
user-defined macros slice 1 `67f3962`/docs `28e2b07`, slice 2 `331e934`, macro
hygiene `de51789`, scoped macro calls and `use` `9cf94a4`, the module/`use`
fixes `36b8bb4` (multi-form printing, a diagnostic instead of the `get_decl`
panic for a module of another unit), and the ownership expansion walk
`6ca6ca6`: the else-path re-analysis reaches `Expr::MacroCall` expansions, and
the Clone derive copying plain-value fields `b16ebee`, drop methods for
generic instantiations met before the derives `d686482`, method calls on
unit-variant values `01ac0e2`, `#derive(Display)` `3e4d3ae`, the std archive linked
by default `dea55e6`, the user-codegen design note
`1e6904a`, the two `-j` pool fixes
`fc2ed48`, linker/archiver discovery on PATH
`86a6cca`, the macro free-name capture guard `63d6c55`, and user codegen
phase A (list parameter + repetition, both positions)
`ce2e35c`/`cb670a9`, the closures design note `1574277`, capturing
lambdas (closures phase A: by value, plain values) `8d71526`, the typed
float-literal fix `74ffd58`, the LSP build + `lsp` test gate
`00b6f94`/`f574496`, and parallel directory builds by default with a
deterministic link order `22d22a2`, the type-lookup/copy speedups `4f5c345`,
geometric `List` growth `e687d07`, the memoized impl lookup `adde952`,
memoized generated-method signatures `11e72f2`, the drop/is_str/append
cleanups `56bb6e4`, dead-linkonce elimination before codegen `8a7c2d7`, the
-O2 front-end library build `f9ef66c`, the record of the -O2 backend
corruption `04ae052`, the resolver name-shadowing fix `d640a2b` that explains
it, the String/List hot-path batch `7e4201f`, the lazy-List/reserve batch
`f48aaaa`, and the std node rename `ba6af50` that keeps the bootstrap able to
build it).
v1.18 released at `8a03e72` (tag `v1.18`, CI run 39289319650 green: x86_64,
aarch64 and termux toolchains built, tested and published). Next release v1.19
bootstraps from v1.18. Releases: v1.11 -- v1.18.

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

## What's in the tree (main = ba6af50)

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
  does not compile). The *self-referential* aggregate field (`struct S{
  t: (S, i32); }`) stack overflow noted here (SIGSEGV in
  `DropHelper::is_drop_type`/`is_drop_decl`) is fixed -- see the
  cyclic-type entry below.

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
  diagnosed -- no double free, but the new value can leak. (Closed by the
  next entry; the hole was not array-specific.)

- Place use-after-move (2026-10-18, same branch, closes the residual above):
  `Own::check_place` is the place counterpart of `Own::check` -- reading a
  moved-out struct/tuple field or array element, writing a *part* of it, or
  moving it a second time is now "use after move in <fn>:<move line> <place>"
  (the aggregate owns the bytes, the value is gone; Rust rejects the same
  shapes). A whole-place *write* (`arr[i] = v`, `f.a = v`) stays legal: it
  reinitializes the place like `x = v` does, so `Emitter::get_lhs` passes
  `check=false` for it while the dispatcher passes `check=true`. The place is
  built by `Own::place_rhs`, a total mirror of `Rhs::new` restricted to
  FIELD/INDEX, because `Rhs::new` panics on a vh `var_map` does not know (a
  `*self` base, a global) and the emitter hands us any expression. The
  struct-field half was the same hole at the same cost (`let y = g.f;` after
  `send(g.f)` was an invalid read + invalid free; `g.f.s = ..` leaked), so
  the fix is one rule for both roots. Whole-var reinit needed care: `x =
  X{..}` makes the pre-write move marks of x's sub-places stale (that is
  std/hashmap's `rehash` loop), and *deleting* them lets the loop's exit
  state say x is fully live -- the last node is then dropped whole and its
  payload freed twice (double free in 12_hashmap-test). `Own::note_reinit` /
  `reinit_places` instead keep a shadow set of invalidated sub-places that
  `check_place` skips (monotone: see the ledger for the rejected variants).
  Tests: tests/fail/dead_elem_write.x / dead_elem_read.x / dead_elem_move.x,
  tests/fail/dead_field_write.x / dead_field_move.x (all compile pre-fix),
  tests/own/30loopreinit.x (the reinit loop + post-loop live use; runs with
  identical drop counts pre-fix). All new behavior verified with the v1.17
  compiler (ex3/ex4 probes: write/read/second-move over dead elements and
  fields; revive and live-write still compile and are valgrind-clean).

- Cyclic value types are a clean error (2026-10-18, same branch, closes the
  documented compile gap): `DropHelper::is_drop_type`/`is_drop_decl` is a
  mutual recursion that walks the whole type graph, so a type containing
  itself by value (`struct S{ s: S; }`, also through a tuple field, an array
  element or a base; `struct A{ b: B; } struct B{ a: A; }`) recursed forever
  -- SIGSEGV (stack overflow, exit 139) inside `handle_attr` during
  `Resolver::init`, i.e. *before* `Resolver::is_cyclic` (is_valid_field)
  could report the cycle, for both v1.17 and the new main. The query is now
  total: `DropHelper::active` holds the `Type::print` keys being expanded and
  a re-entered key returns false -- a type that contains itself by value has
  infinite size, so the recursive position cannot contribute drop-ness. The
  set is balanced (every add has its matching remove on every return path,
  hence the split into `is_drop_rt`), so diamond nesting
  (`struct A{ x: C; y: C; }`) and recursion *through a pointer*
  (`struct S{ s: S*; }`, `Box<N>`, `[S]` -- the std tree relies on this) are
  untouched: neither ever re-enters a key that is still active. With the
  crash gone the validator reports `cyclic type S` (the decl under
  validation; `A` for the mutual pair) and exits. Tests:
  tests/fail/cyclic_type.x / cyclic_type_tuple.x / cyclic_type_mutual.x /
  cyclic_type_array.x -- all four dump core pre-fix, so the harness's
  message check is what fails there. All 8 `DropHelper{...}` literals became
  `DropHelper::new(...)`. Gates: full suite green on the self-hosted binary
  (`normal pass=77`, fmt/opt pass; the leak gate self-skips, valgrind is not
  installed in this environment), triangle byte-identical (A built by the
  pre-fix main compiler, B built by A, `cmp` clean; A != pre-fix main).

- Custom printer placeholders (2026-10-18, same branch, doc/todo item
  "inside format macro, call custom printer"): `{::TraitName}` in a format
  string now calls `TraitName::fmt(<arg>, &f)` instead of `Display::fmt` /
  `Debug::debug`, so a user trait with `func fmt(self, f: Fmt*)` prints a
  value its own way. Both `generate_format` copies grew the case (the
  `Call*` one behind `print`/`format`/`panic` and the `MacroCall*` one
  behind `print!`/`format!`/`panic!`); `func_name` became a `String` so the
  name can be built. The placeholder is positional like `{}` (it consumes
  the next call argument) and mixes freely with `{}`, `{:?}` and named
  args; `{::}` is a clean "invalid format custom printer" (pre-fix the name
  was taken as a named-argument expression and the parser died on the
  leading `::`, "invalid expr Token{value: '::'}", for *every* `{::...}`),
  and an unknown trait / missing impl goes through ordinary method
  resolution ("no such method Hex::fmt(P*, Fmt*)"). Tests:
  tests/std_test/33-custom-printer.x (positive: mixed placeholders, two
  custom printers in one string, `print` call + `print!` macro, asserts the
  rendered text) and tests/fail/custom_printer_no_impl.x /
  custom_printer_empty.x (both parse-panic pre-fix, so the harness message
  check is what fails there). The placeholder is only reliable while the
  receiver type has no other `fmt` impl -- that used to be a hard limit
  because an explicit trait-qualified call did not disambiguate by trait;
  the mangling fix in the next entry closes it, so `{::Hex}` now works on a
  type that also implements Display (extended test above).
  Gates: full suite green on the self-hosted binary (`normal pass=79`,
  fmt/opt pass, std gate includes the new test; leak self-skips, no
  valgrind here), triangle byte-identical (A built by the cyclic-fix
  compiler, B built by A, `cmp` clean; A != previous main).

- Trait impl methods carry their trait in the mangled name (2026-10-18,
  same branch, closes the hole the entry above ran into): `mangle` built
  `<impl type>__<name>_<self>_<params>` and ignored the impl's trait, so
  two traits handing one type the same method name and signature
  (`impl Display for P{ func fmt }` + `impl Hex for P{ func fmt }`, or a
  trait method vs an inherent one) produced *one* symbol. LLVM then kept a
  single function and the second body was emitted as an unreachable block
  (`entry1`) inside the first, so every call -- `Hex::fmt(&p, &f)`,
  `{}`/`{::Hex}`, `p.fmt(&f)` -- ran whichever impl was declared first.
  The resolver had picked the right candidate all along (`is_same` filters
  by trait; `get_impl`'s trait scope path is fine), so this was purely a
  symbol collision, not a resolution bug: the debug run showed one
  candidate per call and one `define` with two `entry` blocks. `mangle`
  now inserts the trait name when the method's impl has one
  (`P__Display__fmt_P$P_Fmt$P`). Inherent impls, trait default methods and
  extern methods mangle exactly as before, and cross-unit calls stay
  consistent because the trait name is stable across units (an impl idx
  would not be). Tests: tests/std_test/34-trait-method-symbols.x (two
  traits, same method name for one type, `A::tag`/`B::tag` dispatch) and
  the extended tests/std_test/33-custom-printer.x (P implements Display
  *and* the custom Hex, `{}`/`{::Hex}`/`{:?}` mixed in one string);
  pre-fix 34's `tag_b` returns "A" and 33's first assert fails, so both
  are genuine regression guards.
  ABI note: every trait-impl method symbol moves, so `-cache` objects from
  an older compiler no longer link -- wipe the out dirs (the suite rebuilds
  std itself; I wiped test_out/std_out/ast_out/fmt_out/test_opt_out).
  Triangle: A (built by the pre-fix compiler) != B (built by A) is
  *expected* here, because A's own trait-impl methods carry the old names;
  B == C (built by B) is the fixpoint, byte-identical. Full suite green on
  the fixpoint binary (`normal pass=79`, fmt/opt pass, leak self-skips).

- `bin/build.sh` linked the two bootstrap stages into one command (2026-10-18,
  found when the mangling change turned CI red): `flags` was never reset, so
  the stage2 command passed stage1's `std/ast/resolver/backend` archives
  (built by the *previous release*) *before* stage2's own. ld resolves from
  the first occurrence, so the shipped stage2 binary was a silent mix. That
  is invisible while the ABI is frozen, but the mangling change above made it
  fatal: stage1's objects (old names) reference `Rhs__drop_Rhs`-style symbols
  that only stage2's objects define under the new names -- CI failed with 46
  `undefined reference` errors in the stage2 link. `build()` now clears
  `flags` per stage, so each stage links only its own libraries.
  Reproduced and verified locally without the `rm -rf build`/apt/llvm steps:
  a stubbed replica of `build.sh` (`/tmp/opencode/build_ci.sh`) bootstrapped
  from the real v1.17 toolchain (`gh release download v1.17`) builds stage1
  and then stage2 cleanly, and the full suite passes on that stage2 binary
  (`normal pass=79`, fmt/opt pass). Also confirmed by hand: compiling
  `src/parser` with stage2's compiler and *both* archive sets fails with the
  46 undefined refs, with only stage2's set it links. `bin/stage1.sh` has a
  single stage, no accumulation -- unaffected. Worth knowing that the
  pre-existing behaviour meant the stage2 artifact was never purely
  stage2-built; the "two bootstrap rounds" argument (e.g. for valgrind
  leaks) now actually holds.

- Paths recorded in the output are normalized and remappable (2026-10-18,
  doc/todo "trim debug paths?"): every `assert`/`panic` literal, diagnostic
  line and DWARF file name carried the unit path *as given*, so a release
  shipped `bin/../src/ast/ast.x:1044` and a build from an absolute path baked
  that absolute path (plus, from the C++ bridge, 19
  `/tmp/usr/lib/llvm-19/include/...` LLVM-header strings from LLVM's own
  asserts). Two mechanisms, both purely string-level:
  `Path::normalize` (std/fs.x) drops `.`/empty segments, collapses `dir/..`
  and duplicate slashes, and never touches the filesystem; `-remap-path-prefix
  OLD=NEW` (repeatable, Rust-style, first match wins, whole path component
  only) is applied on top by `Path::display_path(path, remaps)`.
  `CompilerConfig::remaps`/`display_path` hold the specs and `Context::remaps`
  is copied from the config at all four `Context::new` sites, so the resolver
  can trim what it prints. Applied at the record/print sites only: the assert
  literal and `make_panic_messsage` (assert/panic/`assert!`-style messages) in
  derive.x, `print_line_ctx` in resolver.x, the DWARF `createFile` name in
  emitter.x, and the `-trace` `enter_frame("sig path:line")` string.
  Deliberately *not* trimmed: everything resolution/codegen needs -- import
  resolution, `File::resolve`, cache keys, output `.o` names and the external
  `*_static_init` symbol name (`mangle_unit(path)`; trimming it could make two
  distinct units collide after a remap) -- because a lexical `dir/..` collapse
  can differ from what the OS resolves through a symlinked directory; only the
  recorded/printed spelling is our business.
  `-j` worker children build their own command line, so `make_compile_job`
  forwards every `-remap-path-prefix` (otherwise parallel and serial objects
  would embed different paths; verified byte-identical).
  Caveat: the .o cache is mtime-based and does *not* key on options, so
  toggling the flag in a warm out dir can reuse objects with the old spelling
  (same shape as the opt-level hazard noted in `opt_all`); use a fresh dir.
  Bridge: `cpp_bridge/x.sh` passes `-ffile-prefix-map=$inc_dir=/usr/include`
  (and `$dir=cpp_bridge`) behind a one-line compile probe, since gcc<8 lacks
  the flag; a fresh `libbridge.a` has zero `/tmp/...` include paths and 19
  `/usr/include/llvm/...` ones.
  Test: new `path` gate in bin/test.sh (`path` pattern, part of `all`) -- it
  compiles from a `<dir>/../src/prog.x` spelling and checks the assert literal,
  the panic literal and the diagnostic line, then does the same object under
  `-remap-path-prefix $d=.` plus a `-g` DWARF check with `readelf`. Pre-fix
  red: the pre-fix compiler's object carries
  `.../path_all/bin/../src/prog.x:2` (verified against a pre-batch binary).
  The `-trace` `enter_frame` string is trimmed too; it could not be gated
  until the `mapType2 str` panic was fixed (next entry).
  Effect on the artifact: the pre-fix binary and the stage built *by* it carry
  748 `bin/../src` strings; the next stage (compiled by that one) carries 0 and
  swaps all 19 LLVM include paths for `/usr/include/...`.
  ABI note: no mangling change, but the *content* changes (string literals), so
  the usual fixpoint shifts one stage: B (built by the pre-fix compiler) still
  embeds `bin/../src` + old LLVM include paths, C (built by B) does not, hence
  B != C by construction while C == D is byte-identical. Checked exactly that
  way: `cmp` C vs D clean; `nm` symbol lists of B and C identical (6706
  symbols, no ABI drift); the `.rodata` string-literal *sets* (extracted with
  `objcopy --only-section=.rodata`) are identical modulo the two path
  spellings -- 2321 entries each; full suite green on the fixpoint binary
  (`normal pass=79 xpass=0`, fmt/path/opt pass, leak self-skips -- no valgrind
  here).

- `-trace` was dead on arrival for any unit that never mentions `str`
  (2026-10-18): the emitter synthesizes `enter_frame("<sig> <path>:<line>")`
  per method in genCode(), and that argument is a `str` literal, which
  AllocHelper allocates a slot for. Decl protos are demand-driven
  (`resolver.used_types`), so a unit with no `str` of its own had no proto for
  it and mapType2 panicked (`mapType2 str`, compiler_helper.x:365) before
  emitting a single instruction. Reproduced on the minimal
  `func main(){ let a = 2; }`: `assert` masks it (its expansion allocates a
  `str` of its own), which is why the flag shipped broken unnoticed.
  Fix: `Emitter::compile` marks `str` used when `-trace` is on, *before*
  `createProtos()`, via `resolver.add_used_decl` rather than a raw
  `used_types.add` so the decl's imports/drop glue come along like any other
  used type. No protos change unless the flag is on.
  Adjacent gap found while gating it: `-j` worker children are separate
  compiler processes and inherited neither `-trace` nor `-g`, so a parallel
  build silently emitted no frame calls (and no debug info);
  `make_compile_job` now forwards both, next to the `-remap-path-prefix`
  forwarding from the entry above.
  Test: new `trace` gate (`bin/test.sh trace`, part of `all`). Two methods, no
  own `str` and no `assert` (either would proto `str` and hide the bug), no
  import/multi-unit: compiled with `-trace`, run, and both frames must print
  with trimmed paths (`0 main() <abs>/prog.x:4`, `1 helper() ...:1`); then the
  same program through `-j 2`, which is what catches the unforwarded flag.
  Red pre-fix (the mapType2 panic aborts the compile).
  Also verified by hand: `-g -trace`, `-trace` on a program that *does* use
  `str`, and `-trace -j` over a real two-unit directory all run and print
  frames. Triangle: no ABI or content change (nothing new is baked into the
  compiler: the fix only affects `-trace` compilations), so the strict
  B == C byte-identical holds, and the full suite is green on that binary
  (`normal pass=79 xpass=0`, fmt/trace/path/opt pass, leak self-skips).

- User-defined macros, slice 1: `macro name(p: Expr){ ... }` + `name!(...)`
  (2026-10-18, doc/todo "full macro support"). A parameter is a *syntax
  slot*: every reference to it in the body is replaced by a copy of the
  matching argument, and the body is copied per call site -- so a macro can
  do what a function cannot, assign through its argument (`swap!(a, b)`).
  Most of the plumbing already existed: `name!(...)` parses as
  `Expr::MacroCall`, and the emitter is name-agnostic (it looks the call's
  node id up in `resolver.format_map` and emits `info.block`), which is how
  all builtins (`format!`, `print!`, `panic!`, `std::env`, `ptr::*`) work.
  So this batch is parser + resolver:
  - parser: a `macro` item, params optionally parenthesised (`macro
    name{...}` is the zero-parameter form doc/todo sketched);
  - `Resolver::init_item` seeds a unit-local `macros` map. Module-nested
    definitions are seeded too (bare name, like the rest of the compiler's
    flat name spaces), a duplicate name is an error and `m::name!(...)` is
    rejected with "unit-local, not scoped";
  - `expand_user_macro` (derive.x): `AstCopier` copies the body with fresh
    node ids (`unit.last_id`), a new `expr_map` substitutes bare names with a
    copy of the bound argument (guarded by `in_arg` so an argument is never
    re-substituted -- parameters are often named exactly like the caller's
    variables), the block is resolved in a fresh scope (`newScope`/
    `dropScope`: without it the body's locals leaked into the call site, and
    x rejects any name that exists in a live scope) and registered in
    `format_map`. A trailing expression makes the macro an expression macro
    with an inferred result type (`macro square(x: Expr){ x * x }`), a
    statement body a void macro; using a void macro as a value still reports
    the ordinary "void variable" error;
  - an `Item::Macro` resolves nothing at its definition site (the body only
    means something at a call site), and `own_visitor` now walks user-macro
    blocks, so drops inside an expansion are inserted and a twice-used
    *moving* argument is a diagnosed use-after-move instead of a silent
    double free.
  Limits, on purpose (slice 1): only `Expr` parameters (a non-`Expr`
  parameter is a definition-site error; value parameters are the next slice),
  no hygiene beyond the expansion being its own scope -- a body local named
  like a call-site name is a collision the user must avoid, the same trade
  the builtin macros make by naming their temporaries `f_<id>`, real renaming
  is TODO --, arguments are evaluated once *per use* (a body using one
  argument twice evaluates it twice, Rust-`macro_rules!`-like), an argument
  the body never uses is never evaluated or type-checked, recursion is capped
  (`MAX_MACRO_DEPTH`, "macro expansion too deep"), and macros do not cross
  units yet (imported/`use`d macros, and the token-stream design sketched in
  `resolver/macros.x` + `TokenStream`, are later slices).
  Tests: `tests/normal/40-user-macro.x` (lvalue swap, twice-used argument,
  macro calling macro, the expansion's scope, expression position),
  `tests/fmt/macro.x` + `.expected` (printer round-trip, incl. the bare
  `macro name{...}` form; the formatted output compiles and runs) and eight
  `tests/fail/macro_*.x`: arity, unknown name, non-`Expr` parameter, reserved
  name (`print`/`format`/`panic`/`debug_member`), duplicate name, scoped
  call, recursive expansion, and use-after-move through a macro. Pre-fix red:
  main's parser panics `invalid top level decl: 'macro'`, so the positive
  test cannot even parse and each fail test reports the wrong error.
  Triangle: no ABI or content change (macros are opt-in per program; the
  compiler itself defines none), so B == C byte-identical holds and the suite
  is green on that binary (`normal pass=88 xpass=0` = 79 + 1 new normal + 8
  fail, fmt/trace/path/opt pass, leak self-skips).
  Observed while validating, pre-existing and unrelated: `bin/build_lsp.sh`
  does not build on this tree (`visit_type failed for CmdArgs`, identical
  with this batch stashed); the lsp is not part of `bin/build.sh`/CI.

- User-defined macros, slice 2: typed *value* parameters + macros across units
  (2026-10-18). Slice 1 gave `Expr` slots (substitution); this one lands the
  other half of the doc/todo shape:
  - a parameter whose declared type is not `Expr` is a *value*: the expansion
    starts with `let p: T = <arg>;` in declaration order, so the argument is
    type-checked (`type mismatch i32 vs str` at the call line), evaluated
    exactly once (`bind!(next())` runs `next` once even though the body reads
    the parameter twice), and behaves like a local of the expansion: assigning
    to it does not touch the caller, a move-type argument is moved into it (a
    second call with the same variable is the ordinary use-after-move error).
    Both kinds mix freely (`macro build_h(v: Expr, extra: i32)`), which is the
    `macro panic(e: Expr, s: String)` shape doc/todo sketched (under a
    non-reserved name: `panic` itself is a builtin);
  - x has *no shadowing* (`addScope` rejects any name live in any enclosing
    scope), so a value binding cannot simply take the parameter's name -- the
    argument is often a variable of that very name (`take!(s)`, the natural
    spelling). `Resolver::has_live_name` decides: free name -> bind as-is,
    otherwise bind `<name>_<call id>` and rename the body's references
    (`AstCopier::rename_map`). An `Expr` parameter cannot be renamed that way
    (its references are replaced by AST copies), so a body that *declares* a
    parameter's name is now an error instead of silently referring to the
    parameter (`macro m: body declares `x`, which is a parameter`); the check
    sits in the copier's `Fragment`/`LambdaParam` visitors, so `for` and lambda
    binders are covered too;
  - macros are looked up through imports: `Resolver::find_macro` checks the
    unit's own map first, then every resolver `get_resolvers()` returns (prelude
    plus the units imported here). A hit in a foreign unit also copies that
    unit's imports into `extra_imports` -- the same trick `add_used_decl` uses
    for foreign generics -- so the copied body still resolves the names its own
    unit could see, and no more: the caller must import the macro's unit for the
    lookup to find it. `m::name!(...)` stays rejected ("must be called
    unqualified"); `use` aliases for macros are still open;
  - seeding also rejects duplicate *parameter* names now, and slice 1's
    `Expr`-only definition-site check is gone (that fail test,
    `macro_param_kind.x`, is replaced by `macro_value_type.x`).
  Tests: `tests/normal/41-macro-value-params.x` (single evaluation via a
  `static` call counter, an `Expr` slot writing through where a value parameter
  does not, a parameter sharing the caller's name, an expression macro with
  value parameters, a struct argument moving into the binding), four new
  `tests/fail/macro_*.x` (type mismatch through a value parameter, duplicate
  parameter, body declaring a parameter) plus the rewritten `macro_scoped_call`,
  and `tests/fmt/macro.x`+`.expected` grew value parameters. The cross-unit case
  lives in `tests/incremental_test/`: `macros.x` defines `build_h` whose body
  uses `H`/`h_seven` from `mhelper.x` -- which `main.x` does *not* import -- so
  the expansion only compiles through the foreign-imports step (`main.x` imports
  `macros` and calls `build_h!(30, 5)`; the `inc` gate compiles the directory and
  runs it).
  Triangle: no ABI or content change for non-macro programs (the compiler defines
  no macros itself), B == C byte-identical; full suite green on that binary
  (`normal pass=91 xpass=0` = 79 + 2 normal + 10 fail, fmt/trace/path/opt pass,
  leak self-skips).

- User-defined macros, slice 3: hygiene for the names the body declares
  (2026-10-18). A macro body is alpha-renamed per call site: `hygienic` mode on
  `AstCopier` renames every binder the body declares -- `let`/`for` variables
  (`Fragment`), for-each variables, lambda parameters, match/if-let bindings
  (`ArgBind`) -- to `{name}_{call id}_{seq}`; `Expr::Name` references follow the
  map, which is consulted *before* the parameter maps, so a body local that
  reuses a parameter's name means the local from its declaration on and the
  parameter before it. An unqualified `Call` whose callee names a body local (a
  lambda in the body) is renamed too: callee names are plain strings, so a
  renamed lambda would otherwise be unresolvable ("no such method f(i32)"); a
  scoped call is a method lookup and is left alone, as is a callee the body does
  not declare. Effect: a macro may use `t`, `i` or `res` whatever the call site
  has in scope, and a substituted argument can no longer be captured by a body
  local of the same name. Slice 2's "a body may not declare a parameter's name"
  error -- and the copier's `param_decl` channel -- is gone with it (that body is
  legal now), so `tests/fail/macro_param_shadow.x` is deleted and the case is
  covered positively.
  Limits, documented: the map is never restored when a nested scope ends (a
  nested binder's spelling keeps its fresh name to the end of the body), and a
  body name that is *not* declared still resolves at the call site -- the
  capture doc/todo's macro proposal relies on; definition-site resolution would
  be the real fix and stays open. Diagnostics inside an expansion print the
  fresh names (the `assert` message text is the resolved AST, so `t` may read
  `t_46_0`).
  Tests: `tests/normal/42-macro-hygiene.x` -- a body local against a caller
  variable; the argument itself named like a body local; the same spelling
  declared twice in one body (`let i` plus the for's `let i`); a for-each
  variable and a body local against caller names; a lambda parameter; a match
  binding; a body local reusing a parameter's name; and one case pinning that an
  undeclared body name still captures the call site. Pre-fix red: slice 2's
  compiler reports `variable t already exists`.
  Triangle: no ABI or content change for non-macro programs, B == C
  byte-identical; full suite green (`normal pass=91 xpass=0`, fmt/trace/path/opt
  pass, leak self-skips).

- User-defined macros, slice 3b: scoped calls and `use` (2026-10-18). Macro
  lookup follows the same path as any other name now, so the "unit-local, bare
  name only" restriction is gone:
  - `m::name!(...)` (and `a::b::name!`) resolves when the macro's *declared
    module* matches the path: `init_item` records the module per name
    (`Resolver::macro_scopes`, absent = top level) and `lookup_macro_local`
    compares it structurally (`Type::eq`). The search order is this unit, then
    the units it imports -- and a foreign hit still pulls the defining unit's
    imports into `extra_imports`, so a scoped call into a module of an *imported*
    unit works too;
  - a bare `name!` reaches the macros registered in `use_items` and, as for
    types, `visit_item` registers every `mod` as a use prefix: a module's macros
    are therefore in scope unit-wide, and `use m;` / `use m::{name}` are the
    explicit spellings (`find_use_alias` canonicalizes the list form to
    `m::name`, whose scope is what is matched). Macros of imported units: only
    their top-level ones are reachable bare, their module macros take the scoped
    form -- the same split types have;
  - diagnostics follow the new rules: an unresolved scoped call reports
    "no macro 'x' in 'm'" instead of "must be called unqualified", and
    `expand_user_macro` no longer rejects a scope.
  Tests: `tests/normal/43-macro-scoped.x` (top-level bare; `helpers::double_it!`;
  nested `helpers::more::add_one!`; `use helpers::{double_it}` then bare;
  `use tools;` then bare), a new `tests/fail/macro_bad_scope.x`
  (`other::m!(v)` -> "no macro 'm' in 'other'", replacing `macro_scoped_call.x`
  whose error no longer exists) and `tests/incremental_test/` grew a module macro
  in `macros.x`, called from `main.x` as `toolkit::build_pair!` (scoped,
  cross-unit, and the body uses `mhelper.x`, which main does not import).
  `tests/fmt/macro.x`+`.expected` print a scoped call and a `use` too.
  Pre-fix red: main's compiler rejects all of them with "must be called
  unqualified".
  Observed while validating -- pre-existing, not that batch: all three are
  closed by the entries below (the `use m::{name}` printing loss and the
  `get_decl` panic by the module/`use` fixes; the ownership visitor's macro
  branch by the expansion-walk entry), so nothing from that list is still open.
  Triangle: no ABI or content change for non-macro programs, B == C
  byte-identical; full suite green (`normal pass=92 xpass=0` = 79 + 3 normal +
  10 fail, fmt/trace/path/opt pass, leak self-skips).

- Module and `use` fixes (2026-10-19). The two module bugs the slice 3b
  validation had observed, both fixed:
  - `use m::{name}` prints its list again. `parse_use` never set
    `UseItem.has_multiple`, and the printer (and `find_use_alias`'s multi-form
    branch) read exactly that flag, so the formatter dropped the `{...}` and
    emitted `use m;` -- the narrow form could not round-trip. The parser now
    sets it where it parses the list. Resolution is unchanged: `find_use_alias`
    canonicalizes `A` to `m::A`, which is the path the use-prefix scan took
    anyway (`tests/normal/33-use.x` covers the multi form).
  - a module *of another unit* gets a diagnostic instead of a panic.
    `find_imports` probes imported units by leaf name and passed whatever it
    found on to `get_decl`, including a `Desc{kind: RtKind::Module}` -- and
    `get_decl` has no module case, so `inner::h()` or `m::S{...}` against an
    imported unit died with `get_decl() m=Desc{kind: RtKind::Module, ...}`. A
    module hit is now returned as it is (that RType is what the member lookup
    in `visit_type_str0` already walks through `get_module`), and the two
    places that can still meet a foreign module -- that member lookup and a
    static call scope -- report `... is a module of another unit (<path>): a
    module's members are only visible in the unit that declares them`. Module
    members of the *same* unit keep working (`m::a()`, `m::S{...}`), and macros
    are unaffected (their lookup is resolver-side, so a scoped call into an
    imported unit's module does work). `visit_type` also surfaces the
    resolver's own message (`self.err` with the error's line) instead of the
    bare `visit_type failed for T` panic, so an unknown type now reads
    `couldn't find type: T` and the new message arrives intact.
  Tests: `tests/fmt/macro.x` uses the multi form (`use m::{scaled};`), so its
  checked-in `.expected` is the round-trip; `tests/fail/foreign_mod_type.x`
  (`let s: m::S = m::S{a: 1}`) and `tests/fail/foreign_mod_call.x`
  (`m::helper()`) share a new helper unit `tests/helpers/mod_owner.x` -- the
  fail gate compiles with `-i tests` now, and since the gates glob
  `tests/<dir>/*.x`, the helper's own directory keeps it out of the test set.
  Pre-fix red: main's compiler panics in `get_decl` for both fail tests (so the
  gate reports the wrong error) and the formatter prints `use m;`
  (FMT-DIFF against the new expected).
  Triangle: no ABI or content change (no layout/string baked into the
  compiler), B == C byte-identical; full suite green (`normal pass=94
  xpass=0` = slice 3b's 92 + the two new fail tests, fmt/trace/path/opt pass,
  leak self-skips). README/dev docs for the rule live in doc/modules.txt.

- Ownership: the else-path re-analysis reaches macro expansions (2026-10-19).
  The last item on slice 3b's observed list, and not inert after all: the
  ownership visitor that `Own::end_scope_if` runs over an *else* body
  (`OwnVisitor`, src/parser/own_visitor.x) dispatched only
  `Expr::Call`/`Obj`/`Infix`, and the parser makes an `Expr::MacroCall` for
  every `name!(...)` (user macros and the bang builtins alike), so the
  re-analysis never walked an expansion block.
  - the visible consequence is at the join, not inside the expansion (the
    emitter's own walk of the block was always right, which is why the slice 3b
    probe saw "drops inside an expansion work"): `end_scope_if` decides whether
    the *then* path must drop a value the *else* path moved, from the state the
    re-analysis recorded for the else scope. With the move invisible, that drop
    was skipped and the then path leaked the value -- silently, since leaks are
    the safe direction (`tests/own/31macro_else.x`: `branch(true)` reported 0
    drops where the plain `send(a)` spelling drops 1, `check_ids(1)` failed
    `0 != 1`).
  - fix: `visit_expr` gained an `Expr::MacroCall` arm (`visit_macrocall`) that
    walks the block the resolver kept in `format_map` and moves the block's
    return expression, exactly like the `Call*` branch does for the
    Call-shaped builtins. That branch's `resolver.macros.contains(&mc.name)`
    disjunct is gone with its misleading comment: it was how user macro calls
    were *meant* to arrive, and they never do -- it now keys on the recorded
    block, so `format(...)`/`std::print_type`/`std::env` (Call nodes with a
    block) are still walked and a Call named like a macro can no longer reach an
    `.unwrap()` on a missing entry.
  Tests: `tests/own/31macro_else.x` (drop-tracker: the then path drops what the
  else moved through the macro; the else path drops once, in `send`). Pre-fix
  red: the test aborts with `assert_eq(i32, i32) assertion failed: 0!= 1` on
  main's compiler (the leak), so the own gate exits 1.
  Triangle: no ABI or content change, B == C byte-identical; full suite green
  (`normal pass=94 xpass=0`, fmt/trace/path/opt pass, own green incl. the new
  test, leak self-skips). doc/ownership.txt notes the walk.

- Derive: `#derive(Clone)` copies plain values, clones owners (2026-10-19).
  `generate_clone` called `.clone()` on every non-pointer field, so a struct
  with a `bool`, `str`, `f64`, array, tuple or plain nested-struct field did
  not compile at all: std has Clone impls only for i8..u64 and String, and a
  value has no `clone` method.
  - `is_clone_copy(decl, helper, type)` (derive.x) decides per field: copy
    when the type is a primitive, `str` or a slice (views never own), or when
    the declaration is not generic and the type has no drop glue
    (`DropHelper::is_drop_type`). Everything else -- String and friends, a
    #drop struct, a non-primitive field of a *generic* declaration -- keeps
    `Clone::clone`. The generic case is the careful one: a type parameter (or
    a type built from one) may own and `DropHelper` cannot decide an
    unresolved parameter, so those never take the copy path.
  - the enum arm's copy case is a deref (`let __x = *x;`): its payload
    bindings are pointers, which is also why the pre-existing pointer case
    emits `*name` in the returned literal.
  Tests: `tests/normal/44-derive-clone.x` (plain struct + nested + #drop owner
  + enum with unit/payload/owned variants + generic; plain `-stdpath`, so the
  owner is a local #drop type and the `str` fields are covered by the
  generated body compiling -- x has no `==` on str and the normal gate does
  not link the std archive). Pre-fix red: `no such method bool::clone(bool)`
  at `Plain::clone`.
  Triangle: this changes *generated* code, and the compiler derives Clone on
  its own `LambdaCallInfo` (resolver.x:105), so B (new sources compiled by the
  pre-fix compiler) carries the old generated body and cannot equal C.
  Verified instead: B != C, C == D byte-identical, `nm`/defined-symbol sets
  identical for B/C/D, and the full suite green *on the fixpoint* C
  (`normal pass=95 xpass=0`, fmt/trace/path/opt pass, leak self-skips).
  Observed while validating (all pre-existing, reproducible on the pre-fix
  compiler, none of them about Clone's field rule):
  - a *generic* instantiated with a drop-type parameter (`Wrapper<Owner>`)
    panics in `DropHelper::find_drop_impl` -- "no drop method for
    Wrapper<Owner>": the per-instantiation Drop impl is not generated;
  - a generic instantiated with a *std* type (`Wrapper<String>`) does not link
    in a plain `-stdpath` build (the prelude archive is not linked; the same
    applies to `.clone()` on a primitive);
  - a method call on a unit-variant literal (`Kind::Empty.clone()`) reports
    "get_alloc() not set"; binding it first works (fixed by the entry below).
  doc/token_macros.txt section 3 and doc/todo now list these.

- Compiler crash: a generic over a drop type (2026-10-19). `init` visits
  declared types (`init_type_items`) *before* it generates the derives and
  appends them to `unit.items`. So when a *field* instantiates a generic whose
  parameter is a drop type -- `struct Outer{ b: Box2<A>; }` -- `add_used_decl`
  -> `handle_drop_method` reached `DropHelper::find_drop_impl` while the
  template's generated `Drop` impl did not exist yet, and panicked: `no drop
  method for Box2<A>`. The compiler died on ordinary code (a 12-line file
  reproduces it); it turned up while writing the 44-derive-clone test, which
  had to avoid the shape.
  - fix: `handle_drop_method` asks `DropHelper::has_drop_impl` first. When the
    impl is not there yet it records the instantiation in the new
    `Resolver::pending_drops` (dedup by type) and returns; the end of `init`
    retries each recorded instantiation once the derives are appended.
    Instances met after `init` -- the common case, `let x = Box2<A>{...}` in a
    body -- are unaffected and still generate eagerly, as do foreign units
    (their resolver's init has completed).
  Tests: `tests/own/32generic_drop.x` (drop-tracker: `Outer{b: Box2<A>}` drops
  its field exactly once). Pre-fix red: the *compiler* panics, so the case was
  not expressible at all. `tests/normal/44-derive-clone.x` got the cloned
  `Wrapper<Owner>` field shape back (the original trigger).
  Triangle: the change is behaviour-neutral except where the old code panicked,
  and the drift between B and C is the *known* one from the entry above: the
  compiler's own `StateType` derives Clone, so B (new sources compiled by the
  pre-fix compiler) still carries the old generated body. Verified: `nm`
  defined-symbol sets identical, exactly one symbol differs in size
  (`StateType__Clone__clone_StateType$P`, 0xe8 vs 0xdd -- the generator change,
  not this fix), C == D byte-identical, full suite green (`normal pass=95
  xpass=0`, fmt/trace/path/opt pass, own green incl. the new test, leak
  self-skips).

- A method on a unit-variant value (2026-10-19). `Kind::Empty.clone()` -- any
  method call whose receiver is a unit-variant literal -- did not compile.
  Three stacked bugs, all about "an Expr::Type that is a value":
  - AllocHelper skipped *every* `Expr::Type` call scope. That is right for a
    type path (`M::A::method`, `Trait::method(x)`, `m::f()`), which is not a
    runtime value, but a unit variant is one: it never got an alloc and the
    emitter died with `get_alloc() not set`. It now asks `is_unit_variant`
    (alloc_helper.x: the scope resolves to a decl that is an enum, its name is
    one of the variants, and the variant has no fields) and visits value
    scopes normally.
  - `eval_operand` had no operand for an `Expr::Type` at all (it is a type
    path most of the time). For a unit variant it now returns the temporary
    that `visit` built (`simple_enum`) -- the next error was otherwise
    `eval_operand Kind::Empty`.
  - `debug_call` printed every type-scoped call as `scope::name(...)`, static
    or not. `assert` builds its message by printing the condition and parsing
    it back (`generate_assert`), so `assert(Kind::Empty.is_empty())` became a
    *static* call and resolution failed with `arg size mismatched 0 vs 1`. The
    printer now prints `::` only when `is_static` is set; a value receiver
    keeps its dot.
  Tests: `tests/normal/45-variant-receiver.x` (unit-variant receiver for a
  derived clone and for a user method -- the latter through `assert` -- plus a
  payload-variant receiver and a static call/module call as guards). Pre-fix
  red: `method Kind::Empty::is_empty() not found from candidates / arg size
  mismatched 0 vs 1` (resolution; the emission-stage `get_alloc()` is what it
  would hit next).
  Triangle: no generated code changes for the compiler itself; C == D
  byte-identical, `nm` sets identical, and B != C only in the known
  `StateType__Clone__clone_StateType$P` size drift from the Clone-generator
  entry (0xe8 vs 0xdd). Suite green (`normal pass=96 xpass=0`,
  fmt/trace/path/opt pass, leak self-skips).

- #derive(Display) (2026-10-19). `{}` on a struct was a resolve error ("no such
  method Display::fmt(P*, Fmt*)") unless the type had a hand-written Display.
  `#derive(Display)` now generates one:
  - generate_printer is the shared body of #derive(Debug) and #derive(Display)
    (generate_debug/generate_display are thin wrappers): the same dump shape --
    `Type{field: value}`, `Type::Variant(...)` / `Type::Variant{field: ...}` --
    with `fmt` instead of `debug` and Display::fmt instead of Debug::debug.
    Pointer fields still print as hex (i64::debug_hex), like Debug.
  - a generic declaration's field type is not known when the impl is generated,
    so it goes through new std::display / std::display2 builtins -- the twins of
    std::debug/std::debug2 (expanded in visit_call, emitter mirrors it).
  - a hand-written Display *or* Debug makes that derive step aside
    (has_trait_impl): the explicit impl is the user's choice, and two impls for
    one type would make method lookup depend on candidate order. (Previously
    both were registered and the manual one happened to win.)
  Tests: tests/std_test/14_display_test.x (struct, nested struct field, all
  three enum variant shapes, a generic instantiation, a pointer field, `{}`
  through Fmt directly, and a hand-written Display next to the derive).
  Pre-fix red: `generate_derive decl: A der: 'Display'`.
  Triangle: the compiler itself derives Debug only, and the generated body text
  is unchanged by the refactor (the std Debug test still passes), so the only
  B != C drift is the known StateType::clone one; C == D byte-identical, `nm`
  size-by-name identical for B/C. Suite green on B and on the fixpoint
  (`normal pass=96 xpass=0`, std gate includes the new test, fmt/trace/path/opt
  pass, leak self-skips).
  doc/token_macros.txt section 3b now records it as fixed; the one derive-area
  gap left there is a plain build not linking the std archive.

- Plain builds link the standard library (2026-10-19). `x c prog.x` produced
  `undefined reference to String__new_str` (and the primitive `Clone` impls,
  `String__drop`, ...) unless the caller passed the archive through `-flags`;
  the README quick start has no `-flags`, so it only worked for programs that
  avoided std. The `-std` flag existed but was undocumented in the quick start
  and *wrong* with `-stdpath`: it called `build_std(std_path, ...)`, i.e. it
  compiled `<stdpath>` itself (with `-stdpath src` that is the whole compiler,
  which died inside `str::check_all` -- unrelated crash, but it showed the
  path was never exercised).
  - std now links by default; `-nostd` restores the bare link line. `-std` is
    still accepted as a no-op.
  - `-stdpath <dir>`: if `<dir>/../lib/std.a` exists (the toolchain layout,
    `<toolchain>/{src/std, lib/std.a}`) it is linked, so no `ar` is needed and
    nothing is rebuilt. Otherwise `<dir>/std` is built into the `-out` dir and
    linked; the build is cached there, so only the first compile per out dir
    pays (~4s). `-nolink` never builds it.
  - without `-stdpath` (installed `bin/x`): `<toolchain>/lib/std.a` when
    present. A bare compiler binary (build/.../stage1) has no toolchain tree,
    so it links nothing -- unchanged, and its std imports would not resolve
    either.
  Tests: tests/normal/46-std-link.x (String, `String::clone`, `i32::clone`, a
  `#derive(Clone)` over a String field) -- a plain `-stdpath src` compile with
  no `-flags`. Pre-fix red: `undefined reference to String__new_str`.
  Verified by hand (no harness test): `-nostd` gives the old link error;
  a toolchain layout (`src/std` + `lib/std.a`) links without `AR`; the second
  compile in one out dir takes 0.24s (cache).
  Triangle: the compiler itself is built with `-flags` that already contain
  its std archive, so the extra auto link is the same archive twice (harmless;
  the first compile per out dir is a cache hit because bin/build_std.sh
  already built it there). C == D byte-identical; B != C only in the known
  StateType::clone drift. Suite green (`normal pass=97 xpass=0`).
  README quick-start note and doc/macros.txt `-nostd` entry updated.

- User code generation: design note (2026-10-19). doc/codegen_macros.txt answers
  Q3/Q4 of doc/token_macros.txt (whether user code generation is a goal, and in
  which shape). It records what slices 1-3b already give (statement and
  expression position, `Expr` syntax slots, value parameters, per-call-site
  hygiene, nesting to depth 64) and the two verified missing pieces: no
  repetition over an argument list, and no item position (`m!();` between items
  is "invalid top level decl: ... 'm'", and an item inside a body is a parse
  error).
  - recommendation: declarative shape C1 -- a `T...` rest parameter (last, one
    per macro) with `$( body )*` / `$( body ),*` in the body and `$name` for the
    current element. No CTFE, no token-tree matcher. Zipping is via tuples of
    expressions; joined name/type lists are phase C.
  - phased: A list + repetition (statement/expression position, Expr elements);
    B item position (`Item::MacroCall`, a body element parsed as an item when it
    starts with an item keyword, expansion before init so generated items go
    through the normal attr/derive pass, line = call site, no item hygiene);
    C `Ident` fragments (cheap, from name expressions) and only later `Type`
    fragments, which need parser support at the call site (`List<i32>` parses as
    a comparison, `[i32; 2]` as an array literal).
  - out of scope, with reasons: CTFE (no interpreter inside the compiler), a
    token-tree matcher (replaces the typed-slot model instead of extending it),
    and text-level codegen as the *user* surface -- it cannot substitute AST (so
    no hygiene, no static errors) and it round-trips through the printer, which
    is exactly the assert bug fixed in 01ac0e2 (`Kind::Empty.clone()` printed as
    `Kind::Empty::clone()`, re-parsed as a static call).
  - each slice has a test plan; compiler changes carry the strict triangle,
    generated *user* code needs its own gate.
  Docs: doc/token_macros.txt sections 6/7 point at it (Q3/Q4 answered), doc/todo
  and doc/macros.txt updated, the resolver/macros.x stub marker points at it.
  No code change: the one-line comment edit keeps the compiler byte-identical
  (verified by rebuilding with the same host and `cmp`), so the suite result
  from the previous commit carries over.

- Parallel compile pool: two long-standing bugs fixed (2026-10-19), found by
  the v1.18 release dry run (the full suite hung ~45 minutes in the inc gate's
  `-j` step). Both are in the path handed off as "done" by doc/worker.txt.
  - `Worker.threads` was appended from *worker* threads: worker_bridge pulled
    the next queued job itself and called `Worker::add_arg` (which appends to
    `threads`) while the owner removed from it in `join()`. Two concurrent
    `List::add` reallocs on one buffer: 40 modules through `-j 4` abort 10/10
    with "corrupted size vs. prev_size"; at other timings a completion node is
    lost and `join()` polls `infos` forever (the observed hang). Fix: workers
    never start jobs -- `worker_bridge` retires SELF and returns, and `join()`
    (the owner) hands queued jobs to fresh workers, then stops only when both
    `infos` and `todo` are empty. Owner-only spawn makes the documented
    invariant true again.
  - `CompileArgs.idx` was `&idx` of a *loop-local* `Mutex` in the enqueue loop.
    A job runs later in a worker thread, so `args.idx.lock()` locked a mutex in
    a dead stack frame whose bytes the next call reused -- locking that garbage
    waits forever, which is the flaky hang (the stuck workers sit exactly
    between the cmd build and the "compiling" print). The field was dead
    (incremented, never read) and is gone.
  - Regression: the inc gate compiles 40 generated modules through `-j 4` under
    `MALLOC_CHECK_=3`. Pre-fix it fails 3/3 with the abort; post-fix 20/20
    standalone stress runs, 8/8 inc gates, and the full suite
    (`normal pass=97 xpass=0`) are clean. Triangle: C == D byte-identical,
    B != C only in the known StateType::clone drift. doc/worker.txt records
    both bugs and the fix.

- Linker/archiver discovery (2026-10-19). `get_linker()`/`get_ar()` probed
  candidates by *running* them with no arguments and treating a non-zero exit
  as "not found" -- but a compiler or archiver with no input always exits
  non-zero (clang: "no input files"; `ar`: usage), so neither fallback ever
  matched and a build without `LD`/`AR` exported panicked ("can't find linker" /
  "can't find AR"). The README told users to export both, which is why it
  survived; the fallback is what the panic message implies should work.
  - both now ask the shell (`command -v <tool> >/dev/null 2>&1`, via popen) and
    the candidate lists gained `c++` (linker) and `llvm-ar` (archiver), so a
    system with only clang or only gcc, and a Termux install without binutils,
    are covered.
  - Regression: a new `tools` gate in bin/test.sh compiles a program and a
    `-static` library with `env -u LD -u AR` (the plain compile also needs `ar`
    whenever the std archive is built from source; `-static` pins the archiver
    case). Pre-fix red: the gate fails with "can't find AR". Post-fix green;
    the full suite passes (`normal pass=97 xpass=0`).
  - Triangle: C == D byte-identical, B != C only in the known StateType::clone
    drift. README quick start no longer exports `LD`/`AR` (and uses the v1.18
    toolchain in its example); doc/macros.txt notes the search order.

- Macro free-name capture: the caller-local half of definition-site resolution
  (2026-10-19). The hygiene work renames the names a body *declares*, but a body
  name that is neither declared nor a parameter was resolved at the call site
  with no diagnostic, so a body could silently read a caller local
  (`tests/normal/42-macro-hygiene.x` used to assert exactly that:
  `let outer = 5; use_outer!();`).
  - `AstCopier` now records every free `Expr::Name` it copies (while not inside
    a substituted argument) in `free_names`; `expand_user_macro` rejects a free
    name that `has_live_local` reports as bound by a local scope at the call
    site: "macro m body name 'v' resolves to a local at this call site; pass it
    as a parameter or declare it in the body". `has_live_local` deliberately
    skips `scopes[0]` (the unit's globals, pushed by `init()`): a free name
    hitting a *global* is the ordinary case and keeps resolving at the call
    site, which is what made a first version over-reject
    `tests/normal/41-macro-value-params.x` (its body reads the global `calls`).
  - Tests: `tests/fail/macro_capture_local.x` (pre-fix it compiled and printed
    the caller's `v`; the harness now reports "FAIL (compiled, expected
    failure)", post-fix the message above), and 42-macro-hygiene moved its
    capture case to a module-level `static outer` so the unchanged half stays
    covered. `tests/normal/40-user-macro.x` gained a free name that is a
    top-level function.
  - Residual (still open, recorded in doc/todo/doc/macros.txt): a free name
    that the macro's unit declares but the caller also has (a global, a
    function, or a same-named import) still resolves at the caller -- full
    definition-site resolution needs a per-subtree resolution context (body =
    defining unit, substituted arguments = call site), which is a resolver
    change of its own.
  - Suite green (`normal pass=98 xpass=0`, all gates); triangle C == D
    byte-identical, B != C only in the known StateType::clone drift.

- User codegen, phase A: list parameter + statement repetition (2026-10-19).
  `doc/codegen_macros.txt` proposed C1 (declarative, no CTFE, no token-tree
  matcher); this is its first slice.
  - syntax: `macro m(xs: Expr...){ $( <statements> )* }` and `$xs` for the
    current element. `...` needs no new lexer entry: like the extern vararg
    form it lexes as DOTDOT + DOT (parser.x's param parsing consumes the same
    pair). `$` is TokenType::DOLLAR; `$name` stays an `Expr::Name` whose text
    starts with `$`, so the printer/printer round-trip and the copier's
    substitution need no new Expr kind (adding one would have touched every
    Expr match).
  - AST: `MacroParam.list`, `struct Repeat{body: Block}`, `Stmt::Repeat`.
    Parsing: `is_stmt` includes `$(`, so a repetition is a statement; a
    repetition inside `{ ... }`/`if`/`while` reaches it through
    `AstCopier::visit_stmts` (the copier's Block arm now goes through it).
  - expansion: `expand_user_macro` validates the list parameter (last, at most
    one, `Expr`), binds `fixed` parameters as before, and hands the elements to
    the copier (`repeat_param`/`repeat_elems`). `AstCopier::expand_repeat`
    copies the body once per element with `$xs` bound in `expr_map`; copying
    per iteration is what gives per-iteration hygiene (each iteration's `let t`
    is alpha-renamed again). Nested `$(` is an error; the copier collects
    those messages in `errors` (it has no resolver) and `expand_user_macro`
    reports them at the call site.
  - errors, all at the call site: "list parameter must be last", "more than
    one list parameter", "list parameter must be an Expr", "expects at least N
    args", "'$x' is only valid inside $( ... )*", "'$x' is not a list
    parameter", "list parameter 'xs' must be used as '$xs' inside $( ... )*",
    "nested $( ... )* is not supported". A `Stmt::Repeat` that somehow survives
    copying is a resolver error ("$( ... )* is only valid inside a macro body");
    the backend's two Stmt matches and the formatter have no-op/print arms.
  - tests: `tests/normal/47-macro-repeat.x` (one/many/zero elements, element in
    an expression and as a macro argument, per-iteration locals, repetition in
    an `if`, fixed parameter before the list, expression macro) and four
    `tests/fail/macro_repeat_*.x` (not last, `$` outside a repetition, bare
    list name, nested). Pre-fix red: the old lexer rejects `$` ("unexpected
    char: '$'") and 47 fails to parse. `tests/fmt/macro.x` gained a repetition
    and a list parameter (canonical form `$(stmt;)*`, `xs: Expr...`), macro.expected
    regenerated and idempotent.
  - suite green (`normal pass=103 xpass=0`, fmt/trace/path/opt, leak self-skips);
    triangle C == D byte-identical, B != C only in the known StateType::clone
    drift.
  - deferred (recorded in doc/codegen_macros.txt): separator + expression
    position (`$( <expr> ),*` needs a new Expr kind), item position (phase B),
    fragment kinds (C).

- User codegen phase A, expression position (2026-10-19, follows the list
  parameter + statement repetition entry): `$( <exprs> ),*` as an element of an
  *expression list* -- call/macro-call arguments, array elements, tuple
  elements.
  - AST: `struct RepeatExpr{body: List<Expr>; sep: String}` and
    `Expr::Repeat`. `sep` is spelling only (the enclosing list supplies the
    commas); it exists so the formatter round-trips `,$`-style input.
  - parser: `prim` accepts `$( <exprs> )<sep>*`, where `<exprs>` is
    `exprList(RPAREN)` and `<sep>` is an optional `,`. So
    `($( $xs ),*, 99)` is a tuple: elements then 99; `($( $xs ),*)` is a
    *parenthesized* repetition (the `,` belongs to the repetition), and a
    single-value position is rejected.
  - copier: `visit_exprs`/`visit_expr_list` flatten `Expr::Repeat` (one copy of
    the body per element, `$xs` bound, per-iteration hygiene as in the
    statement form) and are used for Call args, MacroCall args, Array elements
    and Tuple elements. `Expr::Repeat` reaching a single value is a copier
    error; the resolver's `visit_nc` and the backend have unreachable/error
    arms.
  - tests: `tests/normal/48-macro-repeat-expr.x` (array literal, nested macro
    call argument list, tuple with a tail element, element used twice),
    `tests/fail/macro_repeat_value.x`, and tests/fmt/macro.x formats
    `[$($xs),*]` (expected regenerated, idempotent). Pre-fix red: the older
    parser stops at "expected name got '('" and 48 fails to parse.
  - suite green (`normal pass=105 xpass=0`, fmt/trace/path/opt, leak
    self-skips); triangle C == D byte-identical, B != C only in the known
    StateType::clone drift.
  - still open for codegen: item position (phase B), fragment kinds (C),
    non-`Expr` list elements, struct-literal entries.

- Docs pass + closure decision (2026-10-20). No compiler changes.
  - corrected the stale "`tests/normal` links no std" note: since `dea55e6`
    std links by default, so the runner's plain `c -o .. -stdpath src` builds
    and links `<out>/std.a` (`tests/normal/46-std-link.x` uses `String::new` in
    that form). The old text had already misled a batch.
  - re-checked the open-items list on the current compiler: nested `match`
    works (the `doc/todo` line is gone); partial turbofish
    `to_list<i32>(&l)` still fails with "type arg size mismatched" (the item is
    about the *omitted tail* of the type-argument list; `to_list<i32, i32>`
    works); `impl E::A`, integer match patterns and `=>` closures are
    unchanged.
  - `=>` closures are abandoned (user, 2026-10-20): `(a: i32): i32 => { .. }`
    parses as a tuple and dies on `:`. The lambda form we keep is
    `|a: i32|: i32{ .. }`, which parses and works -- what it cannot do is read
    an enclosing local ("captured params not supported yet").
  - new design note `doc/closures.txt`: why a bare function pointer cannot
    carry captures, R1 (heap closure object + hidden trailing argument) vs R2
    (by-value struct), by-value vs by-reference capture, plain vs owning
    captures, an implementation sketch, phasing A/B/C and six questions
    (Q1-Q6). Nothing is implemented; the note says so.
  - `doc/todo` now points at the note (and keeps the partial-turbofish
    clarification); `doc/ownership.txt`'s todo probe says capture is the open
    part.

- Compiler speed, batch 11: lazy lists and geometric reserve (2026-10-21).
  callgrind on a single-file compile (`src/resolver/resolver.x`, which includes
  the std build) put the allocation cluster at ~11% of instructions
  (`_int_free` 3.56, `_int_malloc` 2.79, `malloc` 2.72, `free` 1.74,
  `malloc_consolidate` 0.52), with `List<u8>::reserve` 2.55 and the
  `str::real_len`/`empty`/`len`/`cmp` chain ~6.4 (all tiny out-of-line calls).
  Three changes, all in std:
  1. `List<T>::new()` no longer allocates: it returns a null buffer with cap 0
     (`new(cap)` skips the allocation for cap <= 0 too). `expand` already grew
     a cap-0 list to 10 and `free(null)` is a no-op, so an empty String/List is
     now free; they are extremely common (every temporary, every
     `String::new()`).
  2. `List<T>::reserve` grows geometrically instead of `need + 10`: a String
     built by repeated small appends recopied its whole buffer every ~10 bytes
     (quadratic). The copy loops in `expand`/`reserve` also read through
     `ptr::get!` instead of the checked `get`.
  3. `str::real_len` is one `len()` plus one raw last-byte load (it was
     `empty`+`get`+`len`, three calls, and `cmp` calls it twice), and
     `str::eq` is just `cmp(s) == 0` (the two `empty()` calls it did first are
     implied).
  Measured (module set, `-j` default, two rounds): 32.8s -> 28.6s (-12.9%).
  Per module: std 2.27s -> 2.11s, ast 6.0s -> 5.1s, resolver 13.5s -> 12.0s,
  backend 11.0s -> 9.3s. Against the 146s serial baseline from before batch 1
  that is ~5.1x. A re-measure on an idle machine after the node rename gave
  24.2s (std 1.87, ast 4.6, resolver 9.9, backend 7.6); the 28.6s above was
  taken while /home was nearly full, so the *delta* is the reliable number,
  the absolute one drifted with the machine.
  Correctness: suite green (`normal pass=117`, fmt, lsp, opt, std, own, fail,
  `default-jobs: pass`), the tree rebuilt by its own output is byte-identical
  (C == D), and `tests/normal/58-empty-and-growth.x` pins the empty-value
  behaviour (len/eq/print/clone on an empty String and List) and 1000 small
  appends plus 1000 adds.
  The first CI run of this batch died in the *bootstrap* stage: stage1 (built
  by the v1.18 toolchain, which still has the bare-name resolver bug) segfaulted
  in `List<Thread>::add` while building std for stage2. With the lazy `List` the
  stale layout finally mattered: stage1's own backend module still lays
  `Worker` out as 160 bytes (llist's `Node<T>` resolving to ast's plain `Node`)
  while std writes 168, so `Worker::threads.cap` landed outside the alloca and
  held garbage. Fixed by renaming std's internal node types -- llist
  `Node<T>` -> `LNode<T>`, set `Node<T>` -> `SetNode<T>` -- which removes the
  collision for any compiler, old or new (the two std node types also collided
  with each other, both arity 1, which the resolver fix cannot disambiguate).
  Re-verified through the real bootstrap: v1.18 -> stage1 (now emits
  `[24 x i8]` for `Option<LNode<...>>`, compiles std) -> stage2, suite green,
  C == D.

- Compiler speed, batch 10: String/List hot paths (2026-10-21).
  Re-profiled after batch 8 (the front end is -O2 now). The sampler in
  `bin/sprof.sh` is no longer usable: it calls `backtrace()` from a SIGPROF
  handler, which is not async-signal-safe and now makes the -O2 compiler fail
  on `src/resolver/progress.x`. Used `perf` instead (`apt install
  linux-tools-generic`; the wrapper `/usr/bin/perf` wants a matching
  linux-tools-<kernel> package that does not exist for 6.6.157, so call
  `/usr/lib/linux-tools/*/perf` directly). With `perf record -F 499 -g
  --call-graph dwarf` the profile is dominated by `String`/`str`/`List<u8>`
  plumbing: every byte access was a chain of out-of-line calls.
  Five changes, all in std:
  1. `List<T>::get` inlines its bounds check (`check` was a separate call:
     `List<u8>::check` 4.3% + `List<u8>::get` 3.2% self).
  2. `List<T>::add` returns the slot pointer directly instead of
     `self.get(count-1)` (a second checked lookup per add).
  3. `List<T>::drop_elems` walks the buffer with a pointer: one call per
     element (its drop glue) instead of `len` + `get_internal` + deref.
  4. `str::hash` walks the buffer with a pointer (`self.get(i)` was a call
     plus a bounds check per byte; hash is the entry point of every map/set
     lookup in the compiler).
  5. `String::str`/`slice` build the slice straight from the buffer (they
     went through `slice` -> `len` -> `arr.slice`), `String::clone` and
     `String::new([u8])` are one `memcpy` instead of a `Clone::clone` +
     checked `add` per byte.
  Also removed `str::check_all`/`is_valid`: `String::new(str)` validated every
  byte against a debug whitelist that *panicked* on `@` and on any non-ASCII
  byte (`String::new("@")` aborted; the parser hit it on a source comment),
  and it scanned every byte of every `String::new(str)`.
  Measured (module set, `-j` default, same machine, two rounds): 36.5s ->
  32.8s (-10%). Per module: std 2.28s -> 2.27s, ast 6.4s -> 6.0s, resolver
  14.8s -> 13.5s, backend 13.1s -> 11.0s. Against the 146s serial baseline
  from before batch 1 that is ~4.45x.
  Correctness: suite green (`normal pass=116`, fmt, lsp, opt, std, own, fail,
  `default-jobs: pass`), the tree rebuilt by its own output is byte-identical
  (C == D), and `tests/normal/57-string-bytes.x` covers the removed validator
  (it panics on the previous compiler).

- Resolver bug: a plain `Node` shadowed `Node<T>`; that was the -O2 backend crash (2026-10-21).
  The crash that made batch 8 pin `backend` to -O0 was not a codegen bug: one
  struct had two different layouts in the same program. `std/llist` declares
  `Node<T>` (24 bytes), `ast/ast` declares a plain `Node` (line/pos/id, 12
  bytes), and `Resolver::find_type`/`find_imports` looked types up by their
  bare name. Once anything had resolved the plain `Node` (the backend uses it
  for AST nodes) the cache hit answered `Node<i32>`/`Node<Box<T>>` as well, and
  otherwise the first import that had the name won. std therefore laid
  `Node<T>` out as 24 bytes while every module that resolved ast's `Node` first
  used 12: `Worker`'s `LinkedList` field was 168 bytes in std and 160 in the
  backend, and an -O2 frame placed the `Worker` alloca directly under its
  saved `rbx`, so `Worker::new`'s 168-byte copy stored 0xa over the caller's
  saved register. At -O0 the same overflow lands in frame padding, which is
  why it only appeared with an -O2 backend.
  How it was found: the saved-`rbx` slot held 10 at the crash; a hardware
  watchpoint on that slot showed the writer was a legitimate 168-byte memcpy
  from `Worker::new` into a 160-byte alloca; diffing the per-module `.ll`
  showed `%"Option<Node<Box<WorkerBridgeInfo>>>"` as `[24 x i8]` in `th.ll`
  but `[12 x i8]` in `compiler.ll`; a print in `Emitter::fill_decl` showed the
  enum payload resolving to the 3-field ast::Node (96 bits). (The earlier
  "latent corruption, layout-dependent" reading was a symptom of this: the
  binary was the same, the *type layouts* inside the emitted code were not.)
  Fix: `find_type` only reuses a cached decl for a use that has type arguments
  when that decl is generic with the same arity (non-decl entries and
  unresolved decls keep the old behaviour); `find_imports` no longer returns
  the first import with the bare name but prefers the generic whose arity
  matches, keeping the first hit as the fallback for non-generic uses.
  Guard: `tests/normal/55-generic-name-shadow.x` resolves a plain local
  `Node` first and then uses `Node<i32>` (it fails with "invalid field
  Node.val" before the fix, and also with the v1.18 toolchain). The
  import-order half (ast's `Node` vs llist's `Node<T>`, no plain use first)
  cannot be a suite test: the packaged toolchain ships only `src/std`, so a
  test cannot import `ast/ast`; it is covered by the compiler's own build,
  whose backend module imports ast and uses llist's `Node<T>` (the layout
  check below).
  Verified with an all--O2 compiler (backend included, built by a compiler
  that has the fix): it emits `[24 x i8]` for
  `Option<Node<Box<WorkerBridgeInfo>>>`, compiles `src/std` five times in a row
  without a crash, is valgrind-clean on that workload, passes the suite
  (`normal pass=115`, fmt, lsp, opt, std, own, fail, `default-jobs: pass`,
  also with a packaged toolchain built by the v1.18 bootstrap, which is the
  path CI uses) and the tree rebuilt by its own output is byte-identical
  (mfix_o2 == mfix_o2b == mfix_o2c).
  `backend` stays pinned to -O0 for now, for a bootstrap reason rather than a
  codegen one: whoever *builds* a compiler decides the layout of the new
  binary's own backend module, and the bootstrap (and every release before this
  fix) still has the resolver bug, so an -O2 backend built by it can still
  crash. The pin costs nothing measurable (36.2s vs 35.8s on the module set)
  and the compiler still emits correct layouts for user code; drop it once the
  bootstrap contains the fix.

- Compiler speed, batch 8: the shipped compiler was built half-unoptimized (2026-10-20).
  `bin/build.sh` passed `$XOPT` (CI sets `-O2`) only to the final `src/parser`
  compile: `build_std.sh`/`build_ast.sh`/`build_resolver.sh`/`build_module.sh`
  never saw it, so every release ran its whole front end (std/ast/resolver/
  backend) at -O0 while only `main` was optimized -- and the front end is where
  a user's compile spends most of its time.
  `bin/build_module.sh` now applies `$XOPT` to the library builds too. At the
  time `backend` was pinned to -O0 because an -O2 backend crashed in
  `compile_dir`; that turned out to be a resolver bug (a plain `Node` shadowing
  `Node<T>`, so the struct had two layouts) and the pin is gone -- see the
  entry above.
  Measured (module set, `-j` default, same machine): 41.2s -> 35.7s (-13.3%)
  for the user-facing compile of std/ast/resolver/backend. One-time cost: the
  toolchain build runs LLVM's -O2 on three more libraries (~+15s here).
  Correctness: a program built by the all--O0 compiler, by the old
  (parser-only -O2) one and by the new one is byte-identical; suite green
  (`normal pass=114`, fmt, lsp, opt, std, own, fail, `default-jobs: pass`);
  the tree rebuilt by its own output is byte-identical (m63 == m64).
  PGO is *not* part of this: it needs a compiler that understands a profile
  (the bootstrap host v1.18 cannot), llvm-profdata and the compiler-rt profile
  runtime locally, and would buy less than this did for far more CI machinery.

- Compiler speed, batch 7: drop unreferenced linkonce bodies before codegen (2026-10-20).
  A unit emits a `linkonce` body for every generic instantiation it uses and for
  the drop/clone/debug glue it generates -- in `resolver.x` that is 1698 of
  1897 functions. Those bodies exist so that whoever references them can link
  them; a unit that does not reference one still ran full ISel + object
  emission for it. `Emitter::compile` now runs the `globaldce` pipeline (the
  new-PM text pipeline, via the new `LLVMInfo::optimize_pipeline`) when no `-O`
  is given; with `-O` the level's pipeline already contains it. Discarding an
  unreferenced `linkonce` body is exactly the contract the linker relies on:
  every referencing unit emits its own copy, so a live one is never dropped
  (`nm` symbol sets stay equal, the 30 entries that disappear are undefined
  references to bodies another object provides).
  Measured: resolver module `-j 1` 28.2s -> 25.7s (-9%); the parallel module set
  (std/ast/resolver/backend, `-j` default) 44.0s -> 41.1s (-6.5%). Side effect:
  a stage1 built from the tree is 4.27MB -> 3.21MB, because the same dead bodies
  are no longer in the objects the linker reads.
  Against the 146s serial baseline from before batch 1 the build is now ~3.5x
  faster (41s, parallel).
  Guard: `tests/normal/54-generic-link.x` (instantiations reached only through
  helpers); the real coverage for this change is the multi-unit link path -- a
  live definition dropped by mistake fails the link in every test that links
  `std.a`, not silently.
  Suite green (`normal pass=114`, fmt, lsp, opt, std, own, fail,
  `default-jobs: pass`); the tree rebuilt by its own output is byte-identical
  (m55 == m56).

- Compiler speed, batch 6: small hot-path cleanups (2026-10-20).
  Four independent, behavior-preserving items:
  1. Drop-ness is memoized per unit (`Resolver::drop_type_cache`, keyed on the
     type print). `is_drop_type` walked the whole field graph for every
     expression the resolver and the emitter looked at, and the code already
     carried a `todo cache drop types`. The `active` recursion guard still
     short-circuits cycles and only stable answers are stored.
  2. `Type::is_str` compares the simple name directly. It went through
     `eq("str")`, whose fast path only covers bare names, so pointer, slice and
     generic receivers fell back to printing the whole type.
  3. `Signature::new` builds its `AstCopier` once instead of once per
     parameter (it allocated its maps/lists for every parameter of every
     candidate signature).
  4. `String::append(String*)` is grow-once + memcpy like the `str` overload;
     it appended a byte at a time through the capacity-checked path.
     Self-append keeps the old loop, because growing may move the source.
  Measured: the parallel module set (std/ast/resolver/backend, `-j` default)
  44.1s -> 42.0s (~4%). Deliberately small: `emit_object` is now ~29% of a
  large file's compile and the emitter ~41% inclusive, so what is left is
  mostly LLVM codegen -- further resolver memoization is into diminishing
  returns. Guard test: `tests/normal/53-drop-memo.x` (drop through two field
  levels, counted through a pointer, twice).
  Suite green (`normal pass=113`, fmt, lsp, opt, std, own, fail,
  `default-jobs: pass`); the tree rebuilt by its own output is byte-identical
  (m52 == m53).

- Compiler speed, batch 5: memoized generated-method signatures (2026-10-20).
  `MethodResolver::generateMethod` has a fast path keyed on (method, receiver,
  inferred types), but on every miss it re-checked the instance cache by
  rebuilding a full `Signature` -- resolving and cloning every parameter type
  -- for *each already-generated method of that name*, then comparing. That is
  O(instances^2) type resolutions per generic method (a big file instantiates
  `List`, `HashMap`, `Option` and friends at many types), and it was 11% of the
  resolver profile on its own.
  The resolved parameter list of a generated method is now memoized in
  `Resolver::gen_args`, keyed by (method name, index into
  `generated_methods[name]`), and the scan compares against that directly
  (`is_same_gen`); `handle`'s candidate loop keeps a thin `is_same(sig, sig2)`
  wrapper. Hash nodes are individually allocated, so the cached entry's address
  is stable and the scan never copies the parameter list.
  Measured: resolver module `-j 1` 31.6s -> 28.5s (-10%); the parallel module
  set (std/ast/resolver/backend, `-j` default) 51.0s -> 44.3s (-13%). Against
  the 146s serial baseline from before batch 1 the build is now ~3.3x faster.
  Profile after (resolver.x alone): emitter 38.6% inclusive with `emit_object`
  28.3% (now the largest single item), `String` clones 10.3%, method resolution
  13.7% (it was 30% before batch 4). Guard test:
  `tests/normal/52-generic-instantiation.x` (one generic method at several
  types, both through `List` and a plain `func`).
  Suite green (`normal pass=112`, fmt, lsp, opt, std, own, fail,
  `default-jobs: pass`); the tree rebuilt by its own output is byte-identical
  (m46 == m47).

- Compiler speed, batch 4: memoized impl lookup and a single module verify (2026-10-20).
  A member call re-scanned the calling unit's item list *and* the item list of
  every imported unit on every call site, then rebuilt
  `Signature::make_inferred` once per import on the way down.
  1. `MethodResolver::get_impl` memoizes the unscoped scan in
     `Resolver::impl_cache`, keyed on what the scan compares (the erased type
     name, or the full print when the receiver is scoped, e.g. `M::A`), per
     unit. Items are fixed after parse, so one scan per (unit, receiver type)
     is enough; trait searches keep the plain path.
     Caught mid-batch: keying every receiver on the bare name made `M::A` and
     `N::A` share an entry -- `tests/normal/32-module-dup.x` failed, which is
     exactly the aliasing it was written for. The key now carries the scope and
     `tests/normal/51-impl-lookup-scope.x` pins the scoped-vs-top-level case.
  2. `Signature::make_inferred` (resolves the receiver's decl and prints each
     type parameter) is computed once per `collect_member` and passed through
     the per-import recursion instead of being rebuilt for every import.
  3. `LLVMInfo::emit_obj` verified the module and then `emit_object`
     (cpp_bridge) verified it again; the x-side call is gone, so each object is
     verified once.

  Measured: resolver module `-j 1` 35.3s -> 31.1s (-12%); the parallel module set
  (std/ast/resolver/backend, `-j` default) 55.4s -> 50.1s (-10%). Against the
  146s serial baseline from before batch 1 the build is now ~2.9x faster.
  Profile after (resolver.x alone): `MethodResolver::handle` 24.6% (was 30%),
  `collect`/`collect_member` 12.7% (was ~19%), `generateMethod` 13.8%
  (unchanged: mostly genuine instantiation), emitter 32.7% with `emit_object`
  22.7%, type clones ~8%, `String` clones ~9%. Next: the `generateMethod` miss
  path (it rebuilds a `Signature` per already-generated method to compare),
  `Desc`/type-name string clones, and the LLVM side.
  Suite green (`normal pass=111`, fmt, lsp, opt, std, own, fail,
  `default-jobs: pass`); the tree rebuilt by its own output is byte-identical
  (m43 == m44).

- Compiler speed, batch 3: geometric `List` growth (2026-10-20).
  `List<T>::expand` grew the buffer by **10 elements** per reallocation, so
  building an n-element list copied O(n^2/10) elements. The lexer's token list
  is exactly that shape, and `String` is a `List<u8>`, so lexing, printing and
  every `append` paid it; the profile had `List<Token>::add`/`expand` 15.5%
  inclusive with `String::Clone` 12.1% and `List<u8>::Clone` 11.7% on top
  (each growth moved every element's String too). `expand` now doubles (min 10)
  and `reserve` still allocates exactly what a bulk caller asks for.
  Measured: resolver module `-j 1` 49.2s -> 34.1s (-31%); the parallel module
  set (std/ast/resolver/backend, `-j` default) 73.5s -> 55.0s (-25%). Against
  the serial baseline before batch 1 (146s) the build is now 2.65x faster.
  Correctness: full suite green (`normal pass=110`, fmt, lsp, opt, std, own,
  fail, `default-jobs: pass`) and the tree rebuilt by its own output is
  byte-identical (m38 == m39). Memory: capacity is at most 2x the live size,
  which is the usual doubling trade-off (it was count+10 before).

- Compiler speed, batch 2: cheap type lookup and cheap type copies (2026-10-20).
  Two hot-path fixes, both measured against the batch-1 compiler (same tree,
  `-j 1`, cold resolver module): 65.0s -> 49.3s (-24%); the parallel module set
  (std/ast/resolver/backend, `-j` default) 97.8s -> 73.1s (-25%), so against
  the original serial 146s the whole build is now 2.0x faster.
  1. `Type::clone` went through `AstCopier`, which allocates a HashMap plus
     seven more containers per call; the copier's `type_map` is always empty
     for a plain clone. `Type::clone` is now `clone_type`/`clone_simple`
     (direct recursive copy, same ids/line as before). Type clones are what a
     `visit_type` cache hit returns, so this was the single biggest cost
     (29% inclusive before, 10% after).
  2. `get_resolvers` keyed its memo on `curMethod.path`, but only a *generic*
     method adds its unit's imports transitively, so the cache missed once per
     method and re-ran the import list build plus a `realpath`/`is_file` per
     import on every rebuild. The key now includes the method only when it is
     generic (18.4% inclusive after, was 24.2%).
  Profile after (resolver.x alone): `visit_type*` 32% -> 14%, `Type` clone
  29% -> 10%, `MethodResolver::*` 31%, resolver construction 18%, parser 18%,
  emitter inclusive 47% with 18% in LLVM object emission (this file is 4.4k
  lines, so codegen is now a large share). Next candidates: a
  per-(receiver type, method) signature cache in `MethodResolver` (31%), then
  the per-file import resolver setup (18%) and the LLVM/emitter side.
  Suite green (`normal pass=110`, fmt, lsp, opt, std, own, fail,
  `default-jobs: pass`); the tree rebuilt by its own output is byte-identical
  (m35 == m36).

- Compiler speed, batch 1: parallel builds by default (2026-10-20).
  Measurements first (4 cores, cold, module builds through the scripts):
  std 3.8s, ast 19.1s, resolver 51.0s, backend 71.8s (146s). A sampling
  profile (bin/sprof.sh) of the resolver module says the time is spread thin:
  resolver `visit*` 66% inclusive, of that `visit_type*` 32% and `visit_call`
  30%; `MethodResolver::*` 35%; deep `Type` clones (`Type::Clone` /
  `AstCopier::clone<Type>`) 29%; type-clone-adjacent `RType::Clone` 15%;
  resolver construction for imports (`Resolver::new`, `create_resolver`,
  `get_resolvers`, `find_imports`) 24%; parser 21%; emitter 28% with 12% inside
  LLVM object emission. No single hotspot above ~2% self, so the wins are
  structural (fewer clones, cached import resolvers), not one bad function.
  This batch takes the structural-free win: directory compiles are parallel by
  default (`cpu_count()` in parser/main.x, online CPUs from /proc/cpuinfo
  capped at 8; `-j N` explicit, `-j 1` serial, single-file compiles
  unaffected), and `bin/jobs.sh` gives the bootstrap scripts the same default
  (`XJOBS` overrides, including the final `src/parser` compile in
  stage1/stage2, so a self-build is parallel even when the host toolchain
  predates this default). Result: 146 -> 97s for the module builds (1.5x) and
  84.8 -> 40.1s for a 10-file directory compile (2.1x).
  Required a determinism fix: the sequential path linked in `read_dir` order
  and the parallel path in completion order, so binaries differed in function
  layout (a pre-existing `-j` bug, not introduced here; `nm` symbol sets were
  equal). Both paths now sort the object list before linking. The inc gate adds
  the guard: the same directory built with no `-j` and with `-j 1` must be byte
  identical (`default-jobs: pass`). Consequence for the triangle: the first
  build after this batch differs from its predecessor in layout only (C != D
  once, m31 vs m32, symbol sets identical); from then on it is stable --
  m32 == m33 byte identical.
  Next candidates, in profile order: (a) share initialized resolvers for
  imported units across the files of one compile (24%), (b) cut the deep
  `Type` clones on `visit_type` cache hits (29%), (c) cache method signatures
  per receiver type (35% in MethodResolver). Each needs its own batch and
  measurement; doc/worker.txt has the parallel-build details.

- The LSP builds again, and `all` gates it (2026-10-20)., and `all` gates it (2026-10-20). `src/lsp` had rotted
  in two ways: `main.x` used `CmdArgs` without `import std/io`, and the
  `match` in `overlay` over `unit.items` did not cover the `Item::Macro`
  variant added with user macros. Both are fixed (the new arm is a no-op:
  macros are not part of the overlay dump yet); `bin/build_lsp.sh` itself was
  fine. `bin/test.sh` gained a compile-only `lsp_all` step, in `all` and
  runnable alone as `bin/test.sh <compiler> lsp`: it reuses this run's std
  archive, builds ast on demand and compiles *and links* `src/lsp` with
  `-norun`, so a missing import or a non-exhaustive `match` fails the suite.
  Verified the step exits 1 on the pre-fix source and 0 after. The first CI run
  of the gate failed on the packaged toolchain: `src/lsp` is not shipped in
  `x-toolchain-*`, so the step compiles it from the checkout
  (`$dir/../src/lsp`, like the formatter) while still taking std/ast from
  `$out_dir`; re-checked against a simulated packaged toolchain (bin/x + a src
  tree without `lsp`). Suite green (`normal pass=110`, fmt, lsp, opt, std, own,
  fail). The compiler is untouched by this batch, so the float-literal batch's
  C == D still holds. README's tool/test lines updated.

- Typed float literals (2026-10-20). `let k: f64 = 2.5;`,
  `take(1.5)` for a `f64` parameter, a `f64` struct field and a negative float
  literal now compile. The literal-coercion branch of
  `MethodResolver::is_compatible` runs `i64::parse(<literal text>)` for the
  range check, which panicked on the text of a float literal; it now handles a
  float argument before that: a float target is compatible, any other target
  reports `2.5 is a float literal, not i32` (instead of aborting).
  Tests: `tests/normal/50-float-literal-cast.x` (pre-fix: the panic above, on
  the released compiler too), `tests/fail/float_literal_as_int.x`. Suite green
  (`normal pass=110`), C == D byte-identical (`build/m29_out` ->
  `build/m30_out`).

- Capturing lambdas, phase A (2026-10-20). A `|...|` lambda may now read an
  enclosing local. The resolver already turned such a reference into an extra
  parameter of the generated method (`VarHolder.inLambda` /
  `visit_name_opt`) and then errored "captured params not supported yet"; it
  now records the types in `LambdaType.captured` and the creation-site reads in
  `Resolver::lambda_caps` (resolved *outside* the lambda scope, so they do not
  try to capture themselves, and with fresh node ids: `Node::new(line)` takes
  the line as the *id*, so every read shared one cache slot and the first
  capture's width was copied for every field -- found by a bool+str+f32 shape,
  now pinned in the test). The emitter takes their cached type
  (`visit_cached`) instead of re-visiting the name at emit time, where the
  resolver is no longer in the enclosing scope. A capturing lambda's value is a heap closure
  object `{ fn, captured... }` (`closure_payload_type`; a tuple type, so the
  backend's tuple struct cache supplies the layout): `Expr::Lambda` mallocs it
  and copies the captured values in, `visit_lambda_call` loads `fn` from field
  0 and appends the captured fields as arguments, and `drop_force` frees the
  object (`DropHelper::is_drop_type`/`is_drop_rt` treat a capturing lambda as a
  drop type). Globals are not captured (the body reads them when it runs).
  `make_proto(LambdaType*)` now mirrors the method ABI for struct parameters
  (pointer), which also fixes struct parameters of plain lambdas. `free` is
  declared lazily and reuses a `free` the unit already resolved: declaring it
  eagerly in `init` stole the name and left std's own calls as `free.1`
  (undefined symbol). Semantics are capture-by-value (Q1/Q2/Q3 in
  `doc/closures.txt`): a plain captured value stays usable at the caller, and
  writes in the body touch the closure's copy.
  Tests: `tests/normal/49-closure-capture.x` (by value, two closures, move,
  generic pass-through, aggregate capture, global not captured, per-iteration
  drop, parameter capture), `tests/fail/closure_capture_owning.x`,
  `tests/fail/closure_capture_nested.x`. Full suite green (normal pass=108,
  fmt, opt, std, own, fail); the tree rebuilt by its own output is
  byte-identical (`build/m27_out` -> `build/m28_out`).
  Still open: phase B (owning captures, nested lambdas, `self`) and
  by-reference capture.
  Found while testing (pre-existing, not caused here): a lambda that *returns*
  a struct segfaults -- the generated method uses the sret ABI while the
  lambda-call prototype returns the struct by value. See open holes.

## Known open holes (documented, not yet solved)

Ownership residuals: place use-after-move is closed as of this batch (see
doc/ownership.txt ledger: `check_place` + `reinit_places`). One narrow
residual documented there: while a whole-var write's invalidation entry
holds, a *second* move of that variable's field/element is not diagnosed
(`send(x.f); x = X{..}; send(x.f); send(x.f);`) -- pre-fix silent behaviour,
bounded to a variable wholly reassigned after the first move. Remaining
deliberate silent no-ops: bare `ptr::deref!` of an untracked place, and
`extern`/unsafe aliases (no body to check). Open: language features
(doc/todo), verified 2026-10-18 (details in doc/ownership.txt):
- user-defined macros: LANDED in slices 1--3b (see the entries above);
  `macro name(p: Expr, n: i32){...}` + `name!(...)`, statement and expression
  position, macro-level hygiene for the names the body declares, module rules
  (`m::name!(...)`, `use m;` / `use m::{name}`, top-level macros of imported
  units). Still open: definition-site resolution of a body name that is never
  declared (it still captures the call site); `print!`/`format!`/`panic!`/
  `assert!` remain builtins handled in the format/derive path, and their names
  are reserved. Code generation (token streams / `#derive_macro`) is a
  *proposal* with no consumer: doc/token_macros.txt records why the
  resolver/macros.x stub is unused (the live derive generators are in
  derive.x) and which of its gaps were closed (Clone's field handling, the
  generic-over-a-drop-type crash, `#derive(Display)`, the std archive link --
  see the entries above). For *user*-authored code generation the design note
  is now doc/codegen_macros.txt (declarative list parameters + `$( ... )*`
  repetition; item position and fragment kinds phased behind it).
- closures: `|a: i32|: i32{ .. }` / `||` lambdas work, and since 2026-10-20
  they capture (phase A: enclosing locals/parameters, by value, plain values
  only -- `tests/normal/49-closure-capture.x`, `doc/closures.txt` section 8).
  The `(a: i32): i32 => { .. }` form is abandoned (user, 2026-10-20). Still
  open: owning captures, capture through an inner lambda, `self`, and
  by-reference capture (phase B/C in the note).
- `match` is enum-only: nested match is fine, an integer pattern is
  rejected cleanly (`match expr is not enum: i32`).
- `?` (doc/throw.txt) works and is used across std/fs.x; turbofish calls
  work (`conv<i32, i32>(5)`).
- `impl E::A{ .. }` (impl on an enum variant, doc/enum_var_type) fails with
  `invalid field E*.x`; the doc's `A(a: i32, b: str)` variant syntax is not
  what is implemented (variants are comma-separated with `{}` fields).
- `#derive(Debug = SomeTrait)` delegation (doc/delegate trait): CLOSED, not
  planned (user, 2026-10-18). It would generate exactly the 4-line
  `impl Debug for P{ func debug(self, f){ Trait::m(self, f); } }` that can
  be written by hand, while still needing the trait (and usually its manual
  impl) written by hand; `{::Trait}` (the custom printer above) already
  covers custom formatting at the call site. Its one unique effect would be
  silently redirecting *all* Debug formatting for a type (panic messages,
  std containers) -- a surprising thing to hide in an attribute -- and the
  doc syntax would force a same-unit trait lookup just to learn the
  delegate method's name. If ever revisited, prefer the inverted form:
  `#derive(Hex)` deriving a *user* printer trait with the standard field
  dump, so `{::Hex}` works on every opted-in type without hand-written
  formatters. Today it still panics "derive expr Debug = MyDebugTrait".
- `//trim debug paths?`: panic messages embed absolute source paths
  (`/home/.../src/ast/parser.x:119 -- Parser::err`); nothing trims them.

Compile gaps (pre-existing, not yet fixed):
- (fixed 2026-10-20) A *typed float literal* panicked the compiler:
  `let k: f64 = 2.5;` aborted with
  `unwrap on empty Result, err='invalid digit '.' at pos 1'`. The
  literal-coercion path in `MethodResolver::is_compatible` (method_resolver.x,
  the `arg_val.is_some()` "autocast literal" branch) ran the *integer* range
  check `i64::parse(v.str()).unwrap()` for every literal, so a float literal's
  text was parsed as an integer. `let k: f32 = 2.5;` worked (arg and target are
  equal there, so the branch is skipped), as did `2.5 as f64` and
  `let k: f64 = 2;`. The branch now takes a float argument first: a float
  target is compatible, an integer target is a clean
  `2.5 is a float literal, not i32`. See the entry above.
- A lambda that *returns* a struct segfaults at run time (found 2026-10-20
  while testing closures; reproducible with the released compiler). The
  generated method uses the method ABI, which returns a struct through an sret
  pointer (`make_proto(Method*)`), while the lambda-call prototype
  (`make_proto(LambdaType*)`) returns the struct by value, so the callee writes
  through an argument the caller did not pass. Struct *parameters* were fixed
  in the closures batch (the same prototype now mirrors the method ABI); the
  sret case needs the RVO path in `visit_lambda_call`. A capturing lambda has
  the same hole (it is the same call path).
- (fixed 2026-10-18) A *self-referential* aggregate field (`struct S{
  t: (S, i32); }`) overflowed the stack inside
  `DropHelper::is_drop_type`/`is_drop_decl` -- SIGSEGV during
  `handle_attr`, before the field validator ran. The drop query is now
  total (`DropHelper::active`) and the validator reports `cyclic type S`
  cleanly; see the cyclic-type entry above.
  Non-self-referential arrays/tuples as fields work (owner entry above).
- (fixed 2026-10-18) Explicit trait-qualified method calls
  (`Trait::method(x, ..)`) picked the *first-declared* impl of that method
  name for the receiver's type instead of the named trait: with
  `impl Display for P{ func fmt }` declared before `impl Hex for P{ func
  fmt }`, `Hex::fmt(&p, &f)` ran Display's body (and `{}` ran whichever came
  first). Root cause was the symbol, not the resolver: `mangle` omitted the
  trait, so both impls shared one symbol and the second body became an
  unreachable block. `mangle` now includes the trait; see the entry above
  and tests/std_test/34-trait-method-symbols.x. Found while adding the
  `{::Trait}` custom printer, which generates exactly that call.
- Array-element places *are* tracked now (constant index into a local
  array; see the owner entry above), so `arr[i] = v` no longer leaks and
  `send(arr[0])` works. What stays refused, with a clean error, is any
  index place the state cannot name: a dynamic index, a slice, a pointer
  base, a nested array, and a field of an element. That refusal is now a
  *closed decision* (user, 2026-10-18: no runtime-index place tracking --
  a static name + literal index is the tracking boundary; do not
  "fix" this without asking). The write-after-move residual of the first
  array batch is closed: `Own::check_place` (place counterpart of
  `check`) now rejects reading a moved-out field/element, writing a part
  of it, and moving it twice, for struct/tuple fields *and* array
  elements alike (`tests/fail/dead_elem_*.x`, `dead_field_*.x`); the
  whole-place write stays legal (the revive), and `reinit_places` keeps
  a loop that reassigns the whole var (std/hashmap's rehash) green.
- Harness note (corrected 2026-10-20): `tests/normal` used to compile with
  `-stdpath src` and no std archive, so only std code monomorphised into the
  user object resolved and a non-generic std symbol failed to link. Since std
  links by default (`dea55e6`) the runner's plain `c -o ... -stdpath src`
  builds and links `<out>/std.a`, so a normal regression may use non-generic
  std symbols -- `tests/normal/46-std-link.x` uses `String::new` in exactly
  that form. `-nostd` still restores the bare link line. The earlier text was
  left over from before `dea55e6` and misled a batch.

## Validation protocol (mandatory before merging to main)

1. Develop on a worktree/branch, never on main.
2. Strict build: `./bin/stage1.sh <prev-release-toolchain> <ver>`
   must exit 0 (previous release is the reference builder since
   2026-10-13; 1.05 retired -- it predates drop_lhs and cannot compile
   current sources, e.g. borrow payloads off field bases). Surfaces
   analyzer fallout as precise errors.
3. Full suite: `bin/test.sh <compiler> all` → `normal pass=68 xpass=0`
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
8. A symbol/ABI change (mangling) breaks the strict triangle by nature:
   A (built by the previous compiler) != B (built by A), because A's own
   trait-impl methods still carry the old names. Build C with B and require
   B == C (the fixpoint), then run the full suite on the fixpoint binary.
   Wipe the shared out dirs first (`build/{test,std,ast,fmt,test_opt}_out`):
   `-cache` keys on sources, not the ABI, so stale objects silently fail to
   link the new symbols. `bin/build.sh` had a latent variant of this: the
   two bootstrap stages shared one `flags` string, so stage2 linked stage1's
   archives (mixed ABI). Fixed 2026-10-18.
   A change that only rewrites *embedded strings* (paths, see the
   `-remap-path-prefix` entry above) shifts the fixpoint one stage further:
   B (built by the pre-fix compiler) still carries the old strings, C (built
   by B) carries the new ones -- so require C == D byte-identical instead,
   and show the drift is only strings (`nm` B vs C equal, `strings` diff B vs
   C only path spellings). Same for any change to what the compiler bakes
   into its own output.

## Environment gotchas

- `bin/stage1.sh` does `rm -rf build/` at start: keep logs outside
  `build/`, never run two builds sharing it, binaries vanish (rebuild).
- `-cache` keys on sources only, not on the compiler or on options -- so
  changing the bootstrap (or reusing an out dir across `-O`/
  `-remap-path-prefix` values) reuses stale objects. `rm -rf build/stage2_out`
  whenever the
  bootstrap changes (incl. stash/pop: a popped source keeps its old mtime
  and the object looks fresh). Compiler-internal valgrind leaks are only
  meaningful on a binary whose objects were generated by an already-fixed
  compiler (two bootstrap rounds), never on a prev-release build.
- To exercise the real CI build path locally without `rm -rf build/` or
  apt/llvm: `gh release download v1.17 -D /tmp/opencode/ci`, unzip, then
  `/tmp/opencode/build_ci.sh /tmp/opencode/ci/x-toolchain-1.17-x86_64`
  (stubbed copy of `bin/build.sh`: two stages, -O2, into
  `build/cistage{1,2}_out`; run the suite on `cistage2`).
- `/tmp` is wiped on restarts: toolchains there must be re-downloaded
  (`gh release download`); repo-root `x-toolchain-1.05-x86_64`,
  `build/tmp` (LLVM), `cpp_bridge` lib survive.
- Pod memory limit is 16GB (`oom_kill` counter provable); full-module
  builds flakily OOM — retry (cache resumes), never parallel builds.
- `test.txt` (untracked) regenerates itself; leave it.
- Dev compiler builds must use a unique `<name>_out`: `bin/build_formatter.sh`
  owns `build/fmt_out` and `cache_env.sh` wipes it on a flag-signature
  mismatch, which silently deletes your compiler mid-suite (`build/cprint_out`,
  `build/dev_out` etc. are safe).
- `20_worker` is timing-sensitive; validate with repeated runs.
- Method-call turbofish works, including runtime (`to_list<i32>(41)`
  probed green on v1.15).
- Do not release/publish without asking. Next release (v1.18) bootstraps
  from v1.17 — re-prove before touching the workflow.
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
