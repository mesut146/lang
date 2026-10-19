# Handoff — x language toolchain (ownership focus)

Date: 2026-10-19. Main: `6ca6ca6` (owns `681a8cc` array places, place
use-after-move `163359c`/docs `f478e0e`, cyclic-type fix `8b6190b`/docs
`3105e7f`, custom printer `{::Trait}`, trait-aware method mangling, the
`bin/build.sh` two-stage link fix, delegate-derive closed, source path
normalization / `-remap-path-prefix`, `-trace` codegen + `-j` flag forwarding,
user-defined macros slice 1 `67f3962`/docs `28e2b07`, slice 2 `331e934`, macro
hygiene `de51789`, scoped macro calls and `use` `9cf94a4`, the module/`use`
fixes `36b8bb4` (multi-form printing, a diagnostic instead of the `get_decl`
panic for a module of another unit), and the ownership expansion walk
`6ca6ca6`: the else-path re-analysis reaches `Expr::MacroCall` expansions).
v1.17 released at
`92e3875`; next release v1.18 bootstraps from v1.17. Releases: v1.11 -- v1.17.

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

## What's in the tree (main = 6ca6ca6)

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
  units). Still open: token streams (resolver/macros.x stub) and definition-site
  resolution of a body name that is never declared (it still captures the call
  site); `print!`/`format!`/`panic!`/`assert!` remain builtins handled in the
  format/derive path, and their names are reserved.
- no `=>` closures and no capture: `|a: i32|: i32{ .. }` works,
  `(a: i32): i32 => { .. }` does not parse, and a lambda cannot read an
  outer local (tests/normal/23-lambda.x has the failing capture case
  commented out).
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
