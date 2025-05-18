dir=$(dirname $0)

if [ ! -d "$1" ]; then
 echo "provide toolchain dir"
 exit
fi

toolchain=$1
compiler="$toolchain/bin/x"
build=$dir/../build
mkdir -p $build
out_dir=$build/test_out
testd=$dir/../tests

check(){
  if [ ! "$?" -eq "0" ]; then
    echo "error while compiling $1"
    exit 1
  fi
}

if [ "$2" == "std" ]; then
  $compiler c -cache -static -stdpath $dir/../src -i $dir/../src -out $out_dir $dir/../src/std
  for f in $testd/std_test/*.x; do
    $compiler c -out $out_dir -stdpath $toolchain/src -flags $out_dir/std.a $f
    if [ ! "$?" -eq "0" ]; then
      echo "error while compiling $f"
      exit 1
    fi
  done
else
  for f in $testd/normal/*.x; do
    $compiler c -out $out_dir -stdpath $toolchain/src $f
    if [ ! "$?" -eq "0" ]; then
      echo "error while compiling $f"
      exit 1
    fi
  done
fi
