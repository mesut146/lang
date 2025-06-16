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
  echo "provide toolchain dir or compiler"
  exit 1
fi

pat=$2
build=$dir/../build
mkdir -p $build
out_dir=$build/test_out
testd=$dir/../tests
stdpath=$toolchain/src
linker=$($dir/find_llvm.sh clang)

run(){
  eval $1 || (echo "error while compiling '$1'"; exit 1)
}

normal(){
  for f in $testd/normal/*.x; do
    LD=$linker run "$compiler c -out $out_dir -stdpath $stdpath $f"
  done
}

normal_regex(){
  has_match=false
  for f in $testd/normal/*.x; do
    if [[ "$f" =~ $1 ]]; then
      run "$compiler c -out $out_dir -stdpath $stdpath $f"
      has_match=true
    fi
  done
  if [ $has_match = false ]; then
    echo "regex no match"
    exit 1
  fi
}

std_all(){
  run "$compiler c -cache -static -stdpath $dir/../src -i $dir/../src -out $out_dir $dir/../src/std" || exit 1
  for f in $testd/std_test/*.x; do
    run "$compiler c -out $out_dir -stdpath $stdpath -flags $out_dir/std.a $f"
  done
}

std_regex(){
  has_match=false
  for f in $testd/std_test/*.x; do
    if [[ "$f" =~ $1 ]]; then
      run "$compiler c -out $out_dir -stdpath $stdpath -flags $out_dir/std.a  $f"
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
