dir=$(dirname $0)

if [ ! -d "$1" ]; then
 echo "provide toolchain dir"
 exit
fi

toolchain=$1
compiler="$toolchain/bin/x"
build=$dir/../build
name="x_arm64"
out_dir=$build/${name}_out

target_triple="aarch64-linux-gnu" $compiler c -cache -static -stdpath $dir/../src -i $dir/../src -out $out_dir $dir/../src/std

if [ ! "$?" -eq "0" ]; then
  echo "error while compiling"
  exit 1
fi
#todo use toolchain's std dir?
linker=$($dir/find_llvm.sh clang)
target_triple="aarch64-linux-gnu" LD=$linker $compiler c -norun -cache -stdpath $dir/../src -i $dir../src -out $out_dir -flags "$flags" -name $name $dir/../src/parser

if [ ! "$?" -eq "0" ]; then
  echo "error while compiling"
  exit 1
fi

./ll_zip.sh $out_dir
