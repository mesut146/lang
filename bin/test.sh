dir=$(dirname $0)

toolchain=$1
compiler="$toolchain/bin/x"

if [ -f "$1" ]; then
  compiler="$1"
  toolchain=$dir/..
elif [ -d "$1" ]; then
  toolchain="$1"
  compiler="$toolchain/bin/x"
else
  echo "provide toolchain dir or compiler"; exit 1
fi

pat=$2
build=$dir/../build
mkdir -p $build
out_dir=$build/test_out
testd=$dir/../tests
stdpath=$toolchain/src
linker=$($dir/find_llvm.sh clang)

export LD=$linker 
export AR=ar

run(){
  eval $1 || (echo "error while compiling '$1'"; exit 1)
}

#XSKIP="20_worker": basenames to skip (space-separated, glob patterns ok),
#for tests known to fail under a given configuration. Currently used for
#20_worker under drops (needs the worker teardown redesign, doc/worker.txt).
skipped(){
  for s in $XSKIP; do
    if [[ "$1" == $s ]]; then return 0; fi
  done
  return 1
}

normal(){
  pass=0; fail=0; xpass=0
  for f in $testd/normal/*.x $testd/fail/*.x; do
    [ -f "$f" ] || continue
    base=$(basename $f .x)
    sf=$(head -10 "$f" | grep -m1 -oE '// should-fail.*' || true)
    xf=$(head -10 "$f" | grep -m1 -oE '// xfail.*' || true)
    if [ ! -z "$sf" ]; then
      #negative test: must fail to compile (never executed)
      msg=$(echo "$sf" | sed 's|// should-fail:||;s|// should-fail||;s|^ *||')
      if $compiler c -norun -o $base -out $out_dir -stdpath $stdpath -i $testd "$f" > $out_dir/$base.err 2>&1; then
        echo "FAIL (compiled, expected failure): $f"; exit 1
      elif [ ! -z "$msg" ] && ! grep -qF "$msg" $out_dir/$base.err; then
        echo "FAIL (wrong error, want '$msg'): $f"; exit 1
      else
        pass=$((pass+1))
      fi
    else
      if $compiler c -o $base -out $out_dir -stdpath $stdpath "$f" > /dev/null 2>&1 && $out_dir/$base > /dev/null 2>&1; then
        if [ ! -z "$xf" ]; then
          echo "XPASS (expected failure, but passed): $f :: $xf"; xpass=$((xpass+1))
        else
          pass=$((pass+1))
        fi
      else
        if [ ! -z "$xf" ]; then
          echo "XFAIL (expected): $f :: $xf"; pass=$((pass+1))
        else
          echo "FAIL: $f"
          if [ ! -z "$XGDB" ]; then
            gdb --eval-command="b exit" --eval-command "r c -out $out_dir -stdpath $stdpath $f" $compiler
          fi
          exit 1
        fi
      fi
    fi
  done
  echo "normal: pass=$pass xpass=$xpass"
  if [ "$xpass" != "0" ]; then
    echo "XPASS tests must have their markers removed"; exit 1
  fi
}

normal_regex(){
  has_match=false
  for f in $testd/normal/*.x; do
    if [[ "$f" =~ $1 ]]; then
      run "$compiler c -out $out_dir -stdpath $stdpath $f" || exit 1
      run "$out_dir/$(basename $f)" || exit 1
      has_match=true
    fi
  done
  if [ $has_match = false ]; then
    echo "regex no match"
    exit 1
  fi
}

debug_all(){
  #debug-info smoke: one self-contained test compiled WITH -g and executed.
  #-g codegen used to segfault repo-wide (FFI arity mismatches on the
  #debug-only bridge paths); keep this green.
  run "$compiler c -g -o 31-debug -out $out_dir -stdpath $stdpath $testd/normal/31-debug.x" || exit 1
  $out_dir/31-debug || exit 1
}

std_all(){
  $dir/build_std.sh $compiler $out_dir || exit 1
  LIB_STD=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt

  for f in $testd/std_test/*.x; do
    base=$(basename $f .x)
    if skipped $base; then echo "SKIP: $f"; continue; fi
    run "$compiler c -out $out_dir -stdpath $stdpath -flags $LIB_STD $f" || exit 1
    run "$out_dir/$(basename $f)" || exit 1
  done
}

lsp_all(){
  #Compile-only gate: `src/lsp` is built by no other step and rotted twice
  #without anyone noticing (a missing `std/io` import for `CmdArgs`, then the
  #`Item::Macro` variant that `overlay`'s match did not cover). It reuses the
  #std archive from this run and builds ast on demand (`-cache` makes it a
  #few seconds when std/ast are warm).
  if [ ! -f "$out_dir/std_out/std.a" ]; then
    $dir/build_std.sh $compiler $out_dir || exit 1
    rm -f $dir/tmp.txt
  fi
  if [ ! -f "$out_dir/ast_out/ast.a" ]; then
    $dir/build_ast.sh $compiler $out_dir || exit 1
    rm -f $dir/tmp.txt
  fi
  #the LSP sources come from the checkout, not from $stdpath: the packaged
  #toolchain ships src/{std,ast} but not src/lsp (the formatter does the same).
  run "$compiler c -norun -cache -out $out_dir -stdpath $stdpath -i $stdpath -i $dir/../src -name lsp -flags '$out_dir/ast_out/ast.a $out_dir/std_out/std.a' $dir/../src/lsp" || exit 1
  echo "lsp: pass"
}

std_regex(){
  $dir/build_std.sh $compiler $out_dir || exit 1
  LIB_STD=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt
  has_match=false
  
  for f in $testd/std_test/*.x; do
    if [[ "$f" =~ $1 ]]; then
      #NB: no -g here, debug info codegen is currently broken (segfaults
      #even on trivial files); use XGDB=1 for gdb sessions instead.
      cmd="run '$compiler c -out $out_dir -stdpath $stdpath -flags $LIB_STD $f'"
      eval $cmd || exit 1
      cmd="run '$out_dir/$(basename $f)'"
      eval $cmd
      if [ ! "$?" -eq "0" ]; then
        if [ ! -z "$XGDB" ]; then
          gdb --eval-command="b exit" --eval-command "r c -g -out $out_dir -stdpath $stdpath -flags $LIB_STD $f" $compiler
          #filename="${f%.*}"
          #gdb --eval-command="b exit" --eval-command "r" ${out_dir}/${filename}.bin
        fi
        exit 1
      fi
      has_match=true
    fi
  done
  if [ $has_match = false ]; then
    echo "regex no match"
    exit 1
  fi
}

#formatter: each tests/fmt/*.x must format to its checked-in
#.expected byte-for-byte (comment placement regressions show up as
#diffs here) and be idempotent (second pass changes nothing).
fmt_all(){
  $dir/build_formatter.sh $compiler || exit 1
  fmt=$dir/../build/fmt_out/fmt
  for f in $testd/fmt/*.x; do
    base=$(basename $f .x)
    run "$fmt $f $out_dir/$base.out" || exit 1
    if ! diff -q "$testd/fmt/$base.expected" "$out_dir/$base.out" > /dev/null; then
      echo "FMT-DIFF: $f"; exit 1
    fi
    run "$fmt $out_dir/$base.out $out_dir/$base.out2" || exit 1
    if ! diff -q "$out_dir/$base.out" "$out_dir/$base.out2" > /dev/null; then
      echo "FMT-NOT-IDEMPOTENT: $f"; exit 1
    fi
  done
  echo "fmt: pass"
}

#ownership + move-semantics tests (tests/own, tests/own_if).
#They share tests/own/common.x (Drop-tracker helper, no main) and assert
#runtime behavior, so every test is compiled, linked AND executed.
#NB: these tests assert Drop runs, which requires both drop flags
#(drops are env-gated, off by default).
own_all(){
  export drop_enabled=1 drop_lhs_enabled=1
  $dir/build_std.sh $compiler $out_dir || exit 1
  LIB_STD=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt

  run "$compiler c -nolink -cache -out $out_dir -stdpath $stdpath -i $testd $testd/own/common.x" || exit 1
  for f in $testd/own/*.x $testd/own_if/*.x; do
    base=$(basename $f .x)
    if [ "$base" = "common" ]; then continue; fi
    run "$compiler c -nolink -cache -out $out_dir -stdpath $stdpath -i $testd $f" || exit 1
    run "$linker -o $out_dir/$base.bin $out_dir/$base.o $out_dir/common.o $LIB_STD" || exit 1
    run "$out_dir/$base.bin" || exit 1
  done
}

#optimizer gate: same programs must produce identical observable behavior
#with the new-PM pipeline on. Fresh out dir on purpose: .o cache keys do
#not include the opt level, so reusing test_out could link -O0 objects.
opt_all(){
  opt_out=$build/test_opt_out
  rm -rf $opt_out
  mkdir -p $opt_out
  for f in $testd/normal/09-array.x $testd/normal/19-match.x $testd/normal/23-lambda.x $testd/normal/35-op-assign-deref.x $testd/normal/36-literal-operand.x; do
    base=$(basename $f .x)
    run "$compiler c -O2 -norun -o $base -out $opt_out -stdpath $stdpath \"$f\"" || exit 1
    run "$opt_out/$base" || exit 1
  done
  #std_test/06 reads into a local array and hands it to strcmp: with a 5-byte
  #array the comparison ran one byte past the buffer and only passed while the
  #-O0 stack layout left that byte zero (it failed at -O2 with 127/128). Run it
  #optimized so the terminator cannot silently regress.
  run "$compiler c -O2 -out $opt_out -stdpath $stdpath -i $testd $testd/std_test/06_libc-test.x" || exit 1
  run "$opt_out/06_libc-test.x" || exit 1
  echo "opt: pass"
}

#no--O pipeline ("-O0.5"): the emitter writes every local as an alloca plus
#loads/stores, so a default (-O0) build used to run its hot loops out of the
#stack (a 200M-iteration local loop: 431ms at -O0, 88ms once the allocas are
#promoted) and `#[inline]` bought nothing, because an inlined body's allocas
#stayed on the stack too. The no--O pipeline now runs `globaldce,mem2reg,dce`
#(`globaldce,always-inline,mem2reg,dce,globaldce` when a body carries
#`#[inline]`). This pins both halves on the emitted IR: after the pipeline a
#plain `i64` local must have no alloca left, and an `#[inline]` helper must be
#inlined *and* its dropped body gone.
pipeline_all(){
  mkdir -p $out_dir
  src=$out_dir/pipeline_src.x
  cat > $src <<'XEOF'
import std/io

#[inline]
func twice(x: i64): i64{
  return x * 2;
}

func sum(n: i64): i64{
  let s: i64 = 0;
  let i: i64 = 0;
  while(i < n){
    s = s + twice(i);
    i = i + 1;
  }
  return s;
}

func main(){
  assert(sum(10) == 90);
  print("pipeline ok\n");
}
XEOF
  rm -rf $out_dir/pipeline
  run "$compiler c -norun -out $out_dir/pipeline -stdpath $stdpath -i $testd $src" || exit 1
  ir=$out_dir/pipeline/pipeline_src.ll
  n=$(grep -c "alloca i64" "$ir")
  if [ "$n" != "0" ]; then
    echo "pipeline: $n i64 allocas left in the IR (mem2reg did not run?)"; exit 1
  fi
  if grep -q "define .*@twice(" "$ir"; then
    echo "pipeline: #[inline] body still defined (always-inline/globaldce did not run?)"; exit 1
  fi
  run "$compiler c -out $out_dir/pipeline -stdpath $stdpath -i $testd $src" || exit 1
  run "$out_dir/pipeline/pipeline_src.x" || exit 1
  echo "pipeline: pass"
}

#valgrind leak gate: raw malloc leaks the drop-count tracker cannot see
#(discarded format()/`?` buffers, Box::unwrap storage). Each
#tests/leak/*.x must run with zero definite/indirect bytes at exit.
#Needs valgrind; skips loudly (does not fail) when it is not installed.
leak_all(){
  if ! command -v valgrind > /dev/null 2>&1; then
    echo "leak: SKIP (valgrind not installed)"; return 0
  fi
  $dir/build_std.sh $compiler $out_dir || exit 1
  LIB_STD=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt
  for f in $testd/leak/*.x; do
    [ -f "$f" ] || continue
    base=$(basename $f)
    run "$compiler c -out $out_dir -stdpath $stdpath -flags $LIB_STD $f" || exit 1
    if ! valgrind -q --error-exitcode=99 --leak-check=full \
         --errors-for-leak-kinds=definite,indirect \
         $out_dir/$base > /dev/null 2>&1; then
      echo "LEAK: $f"
      valgrind -q --leak-check=full --errors-for-leak-kinds=definite,indirect \
        $out_dir/$base
      exit 1
    fi
  done
  echo "leak: pass"
}

#vararg (C interop): tests/vararg/vararg.x + tests/vararg/main.c
vararg_all(){
  run "$compiler c -nolink -cache -out $out_dir -stdpath $stdpath $testd/vararg/vararg.x" || exit 1
  run "gcc -c -o $out_dir/main.o $testd/vararg/main.c" || exit 1
  run "$linker -o $out_dir/vararg.bin $out_dir/vararg.o $out_dir/main.o" || exit 1
  run "$out_dir/vararg.bin" || exit 1
}

#tool discovery with LD and AR unset: the compiler must find a linker and an
#archiver itself. Both candidate probes used to run the tool with no arguments,
#which always exits non-zero (clang: "no input files"; ar: usage), so a build
#without LD/AR exported panicked ("can't find linker" / "can't find AR").
tools_all(){
  run "env -u LD -u AR $compiler c -o selfind -out $out_dir -stdpath $stdpath $testd/normal/01-var.x" || exit 1
  run "$out_dir/selfind" || exit 1
  #-static builds a library through ar (needs AR); the plain compile above also
  #needs ar whenever the std archive has to be built from source.
  run "env -u LD -u AR $compiler c -static -o selflib -out $out_dir -stdpath $stdpath $testd/normal/01-var.x" || exit 1
  run "test -f $out_dir/selflib" || exit 1
}

#build flags: every front-end module must be compiled with $XOPT. `backend`
#used to be pinned to -O0 as a workaround for the resolver name-shadowing bug
#(fixed in d640a2b, shipped in v1.19): the pin kept unoptimized dead code in
#the shipped compiler (backend.a 1.1M instead of 0.6M) and cost ~2% of user
#compile time on a front-end-bound workload. A stub compiler records the
#command line of each module build, so a re-introduced exemption fails here
#instead of silently slowing the shipped compiler down.
buildflags_all(){
  mkdir -p "$out_dir"
  stub=$out_dir/fake_compiler
  log=$out_dir/buildflags.log
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexit 0\n' "$log" > "$stub"
  chmod +x "$stub"
  for level in "-O2" ""; do
    rm -f "$log"
    for name in std ast resolver backend; do
      XLIBNAME=$name XLIBSRC=$testd/../src/$name XOPT="$level" XJOBS=1 \
        $dir/build_module.sh "$stub" "$out_dir/buildflags" >/dev/null || exit 1
      rm -f $dir/tmp.txt
    done
    if [ -z "$level" ]; then
      n=$(grep -c -- "-O2" "$log")
      if [ "$n" != "0" ]; then
        echo "buildflags: -O2 used with an empty XOPT"; cat "$log"; exit 1
      fi
    else
      n=$(grep -c -- "$level" "$log")
      if [ "$n" != "4" ]; then
        echo "buildflags: $n/4 modules built with $level"; cat "$log"; exit 1
      fi
    fi
    rm -rf "$out_dir/buildflags"
  done
  echo "buildflags: pass"
}

#multi-file import resolution (tests/incremental_test/*.x, single main)
inc_all(){
  run "$compiler c -out $out_dir -stdpath $stdpath -i $testd $testd/incremental_test" || exit 1
  run "$out_dir/incremental_test" || exit 1
  #parallel compile path (-j): each job is a child compiler whose stdout must
  #be drained before the stream is closed, or the child dies with SIGPIPE and
  #the build fails ("failed to compile"). A fresh out dir keeps the cache cold
  #so the children actually run.
  run "$compiler c -cache -j 4 -out $out_dir/inc_j -stdpath $stdpath -i $testd $testd/incremental_test" || exit 1
  run "$out_dir/inc_j/incremental_test" || exit 1
  #-j stress: 40 independent modules through the parallel path with the
  #allocator's own checks on. A finishing worker used to start the next queued
  #job itself, appending to Worker::threads while join() removed from it:
  #concurrent realloc aborted here ("corrupted size vs. prev_size"), and at
  #other timings the worker's completion node was lost and join() spun forever.
  #the default worker count (directory compiles are parallel unless -j is
  #given) must not change the output: the same directory built with no -j and
  #with -j 1 has to be byte identical. Both paths sort the object list before
  #linking, otherwise the parallel one links in completion order.
  run "$compiler c -cache -out $out_dir/inc_def -stdpath $stdpath -i $testd $testd/incremental_test" || exit 1
  run "$compiler c -cache -j 1 -out $out_dir/inc_ser -stdpath $stdpath -i $testd $testd/incremental_test" || exit 1
  cmp $out_dir/inc_def/incremental_test $out_dir/inc_ser/incremental_test || \
    { echo "DEFAULT-JOBS: the default output differs from -j 1"; exit 1; }
  echo "default-jobs: pass"
  stress=$out_dir/stress_src
  rm -rf $stress && mkdir -p $stress
  for i in $(seq 1 40); do
    printf 'func s%s(): i32{\n    return %s;\n}\n' $i $i > $stress/s$i.x
  done
  run "MALLOC_CHECK_=3 $compiler c -nolink -cache -j 4 -out $out_dir/stress_out -stdpath $stdpath -i $testd $stress" || exit 1
}

#-trace frame instrumentation (std/rt.x call_stack): the emitter synthesizes
#`enter_frame("<sig> <path>:<line>")` per method, i.e. it passes a `str`
#literal. Decl protos are demand-driven (resolver.used_types), so a unit that
#never mentions `str` used to die in mapType ("mapType2 str") before emitting
#anything -- the program below deliberately has no other str and no `assert`
#(the assert expansion allocates a str of its own, which masked the panic).
#Also covers the link+run against the std frame runtime and the trimmed path
#in the frame line.
trace_all(){
  d=$out_dir/trace_all
  rm -rf $d
  mkdir -p $d
  d=$(readlink -f $d)
  #two methods, no `assert` and no str use of its own (either would proto str)
  printf 'func helper(){\n    print_frame();\n}\nfunc main(){\n    let a = 2;\n    helper();\n}\n' > $d/prog.x
  $dir/build_std.sh $compiler $out_dir || exit 1
  LIB_STD=$(cat "$dir/tmp.txt") && rm -rf "$dir/tmp.txt"
  run "$compiler c -trace -out $d -stdpath $stdpath -flags $LIB_STD -o prog $d/prog.x" || exit 1
  run "$d/prog > $d/out.txt" || { echo "TRACE-RUN-FAILED"; cat $d/out.txt; exit 1; }
  #both frames: enter_frame ran for each method, with trimmed paths
  grep -q "0 main() $d/prog.x:4" $d/out.txt \
    || { echo "TRACE-FRAME-MISSING (main)"; cat $d/out.txt; exit 1; }
  grep -q "1 helper() $d/prog.x:1" $d/out.txt \
    || { echo "TRACE-FRAME-MISSING (helper)"; cat $d/out.txt; exit 1; }
  #parallel: -j children are separate compiler processes, so the flag has to be
  #forwarded (see make_compile_job) or the frame code vanishes silently
  rm -rf $d/j $d/jout
  mkdir -p $d/j
  cp $d/prog.x $d/j/prog.x
  printf 'func unused(){\n    let b = 3;\n}\n' > $d/j/other.x
  run "$compiler c -trace -j 2 -out $d/jout -stdpath $stdpath -flags $LIB_STD -o prog $d/j" || exit 1
  run "$d/jout/prog > $d/jout.txt" || { echo "TRACE-RUN-FAILED (-j)"; cat $d/jout.txt; exit 1; }
  grep -q "1 helper() $d/j/prog.x:1" $d/jout.txt \
    || { echo "TRACE-FRAME-MISSING (-j)"; cat $d/jout.txt; exit 1; }
  echo "trace: pass"
}


#Source paths recorded in the output: `assert`/`panic` bake the unit path into
#the object, diagnostics print it and -g puts it in DWARF. They must be
#lexically normalized (`bin/../src/x.x` must not ship) and remappable with
#-remap-path-prefix, so release artifacts do not leak the build directory
#(doc/todo "trim debug paths?"). Resolution/codegen keep the original
#spelling (a symlinked dir with `..` must still open), so only the recorded
#strings are checked here.
path_all(){
  d=$out_dir/path_all
  rm -rf $d
  mkdir -p $d
  #absolute (and free of any `bin/..` in $out_dir), so the recorded path is the
  #build directory the leak is about
  d=$(readlink -f $d)
  mkdir -p $d/src $d/bin
  printf 'func main(){\n    assert(1 == 2);\n}\n' > $d/src/prog.x
  printf 'func main(){\n    panic("boom");\n}\n' > $d/src/pan.x
  printf 'func main(){\n    let a: i32 = "s";\n}\n' > $d/src/bad.x
  #1) lexical normalization: the `dir/../src` spelling collapses
  run "$compiler c -nolink -out $d/norm -stdpath $stdpath $d/bin/../src/prog.x" || exit 1
  if strings $d/norm/prog.o | grep -q 'bin/\.\./src'; then
    echo "PATH-UNNORMALIZED (assert literal): $d/bin/../src/prog.x"; exit 1
  fi
  strings $d/norm/prog.o | grep -qF "$d/src/prog.x" \
    || { echo "PATH-MISSING (assert literal): $d/norm/prog.o"; exit 1; }
  #2) same for the panic literal
  run "$compiler c -nolink -out $d/pan -stdpath $stdpath $d/bin/../src/pan.x" || exit 1
  strings $d/pan/pan.o | grep -qF "$d/src/pan.x" \
    || { echo "PATH-MISSING (panic literal): $d/pan/pan.o"; exit 1; }
  #3) diagnostics print the normalized path
  "$compiler" c -nolink -out $d/diag -stdpath $stdpath $d/bin/../src/bad.x > $d/diag.log 2>&1
  grep -qF "$d/src/bad.x" $d/diag.log \
    || { echo "PATH-MISSING (diagnostic)"; cat $d/diag.log; exit 1; }
  #the diagnostic line is `path:line method()`; the "compiling <file>" log line
  #deliberately echoes the path as given, so match on path:line only
  if grep -E 'bin/\.\./src.*bad\.x:[0-9]+' $d/diag.log; then
    echo "PATH-UNNORMALIZED (diagnostic)"; cat $d/diag.log; exit 1
  fi
  #4) -remap-path-prefix drops the build directory from the object
  run "$compiler c -nolink -out $d/remap -remap-path-prefix $d=. -stdpath $stdpath $d/src/prog.x" || exit 1
  if strings $d/remap/prog.o | grep -qF "$d/src/prog.x"; then
    echo "PATH-NOT-REMAPPED (assert literal): $d/remap/prog.o"; exit 1
  fi
  strings $d/remap/prog.o | grep -qF "./src/prog.x" \
    || { echo "PATH-MISSING (remap target): $d/remap/prog.o"; exit 1; }
  #5) -g DWARF carries the same trimmed name
  run "$compiler c -nolink -g -out $d/dbg -remap-path-prefix $d=. -stdpath $stdpath $d/src/prog.x" || exit 1
  readelf --debug-dump=info $d/dbg/prog.o > $d/dbg.txt
  if grep -qF "$d/src/prog.x" $d/dbg.txt; then
    echo "PATH-NOT-REMAPPED (-g DWARF)"; exit 1
  fi
  echo "path: pass"
}

if [ -z "$pat" ]; then
  normal
elif [ "$pat" == "std" ]; then
  if [ -z $3 ]; then
    std_all
  else
    std_regex $3
  fi
elif [ "$pat" == "own" ]; then
  own_all
elif [ "$pat" == "vararg" ]; then
  vararg_all
elif [ "$pat" == "inc" ]; then
  inc_all
elif [ "$pat" == "tools" ]; then
  tools_all
elif [ "$pat" == "buildflags" ]; then
  buildflags_all
elif [ "$pat" == "pipeline" ]; then
  pipeline_all
elif [ "$pat" == "path" ]; then
  path_all
elif [ "$pat" == "trace" ]; then
  trace_all
elif [ "$pat" == "lsp" ]; then
  lsp_all
elif [ "$pat" == "fmt" ]; then
  fmt_all
elif [ "$pat" == "opt" ]; then
  opt_all
elif [ "$pat" == "leak" ]; then
  leak_all
elif [ "$pat" == "all" ]; then
  normal
  fmt_all
  debug_all
  trace_all
  std_all
  lsp_all
  own_all
  leak_all
  vararg_all
  inc_all
  tools_all
  buildflags_all
  pipeline_all
  path_all
  opt_all
elif [ ! -z "$pat" ]; then
  normal_regex $pat
fi
