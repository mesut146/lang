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
      if $compiler c -norun -o $base -out $out_dir -stdpath $stdpath "$f" > $out_dir/$base.err 2>&1; then
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
    run "$compiler c -out $out_dir -stdpath $stdpath -flags $LIB_STD $f" || exit 1
    run "$out_dir/$(basename $f)" || exit 1
  done
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
      eval $cmd
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

#vararg (C interop): tests/vararg/vararg.x + tests/vararg/main.c
vararg_all(){
  run "$compiler c -nolink -cache -out $out_dir -stdpath $stdpath $testd/vararg/vararg.x" || exit 1
  run "gcc -c -o $out_dir/main.o $testd/vararg/main.c" || exit 1
  run "$linker -o $out_dir/vararg.bin $out_dir/vararg.o $out_dir/main.o" || exit 1
  run "$out_dir/vararg.bin" || exit 1
}

#multi-file import resolution (tests/incremental_test/*.x, single main)
inc_all(){
  run "$compiler c -out $out_dir -stdpath $stdpath -i $testd $testd/incremental_test" || exit 1
  run "$out_dir/incremental_test" || exit 1
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
elif [ "$pat" == "fmt" ]; then
  fmt_all
elif [ "$pat" == "all" ]; then
  normal
  fmt_all
  debug_all
  std_all
  own_all
  vararg_all
  inc_all
elif [ ! -z "$pat" ]; then
  normal_regex $pat
fi
