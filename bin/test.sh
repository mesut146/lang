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

check(){
  if [ ! "$?" -eq "0" ]; then
    echo "error while compiling $1"
    exit 1
  fi
}

normal(){
  for f in $testd/normal/*.x; do
    LD=$linker $compiler c -out $out_dir -stdpath $stdpath $f
    check $f
  done
}

normal_regex(){
  has_match=false
  for f in $testd/normal/*.x; do
    if [[ "$f" =~ $1 ]]; then
      $compiler c -out $out_dir -stdpath $stdpath $f
      check $f
      has_match=true
    fi
  done
  if [ $has_match = false ]; then
    echo "regex no match"
    exit 1
  fi
}

std_all(){
  $compiler c -cache -static -stdpath $dir/../src -i $dir/../src -out $out_dir $dir/../src/std
  for f in $testd/std_test/*.x; do
    $compiler c -out $out_dir -stdpath $stdpath -flags $out_dir/std.a $f
    check $f
  done
}

std_regex(){
  has_match=false
  for f in $testd/std_test/*.x; do
    if [[ "$f" =~ $1 ]]; then
      $compiler c -out $out_dir -stdpath $stdpath -flags $out_dir/std.a  $f
      check $f
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
  normal_regex $2
fi
