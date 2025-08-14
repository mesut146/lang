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

run(){
  eval $1 || (echo "error while compiling '$1'"; exit 1)
}

normal(){
  for f in $testd/normal/*.x; do
    run "$compiler c -out $out_dir -stdpath $stdpath $f"
    if [ ! "$?" -eq "0" ]; then
      if [ ! -z "$XGDB" ]; then
        gdb --eval-command="b exit" --eval-command "r c -out $out_dir -stdpath $stdpath $f" $compiler
      fi
      exit 1
    fi
  done
}

normal_regex(){
  has_match=false
  for f in $testd/normal/*.x; do
    if [[ "$f" =~ $1 ]]; then
      run "$compiler c -out $out_dir -stdpath $stdpath $f" || exit 1
      has_match=true
    fi
  done
  if [ $has_match = false ]; then
    echo "regex no match"
    exit 1
  fi
}

std_all(){
  $dir/build_std.sh $compiler $out_dir || exit 1
  LIB_STD=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt

  for f in $testd/std_test/*.x; do
    run "$compiler c -out $out_dir -stdpath $stdpath -flags $LIB_STD $f" || exit 1
  done
}

std_regex(){
  $dir/build_std.sh $compiler $out_dir || exit 1
  LIB_STD=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt
  has_match=false
  
  for f in $testd/std_test/*.x; do
    if [[ "$f" =~ $1 ]]; then
      cmd="run '$compiler c -g -out $out_dir -stdpath $stdpath -flags $LIB_STD $f'"
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

if [ -z "$pat" ]; then
  normal
elif [ "$pat" == "std" ]; then
  if [ -z $3 ]; then
    std_all
  else
    std_regex $3
  fi
elif [ ! -z "$pat" ]; then
  normal_regex $pat
fi
