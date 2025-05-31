dir=$(dirname $0)

if [ -z "$1" ]; then
 echo "provide binary"
 exit
fi

compiler=$1
toolchain=$2
build=$dir/../build
mkdir -p $build
name="xx2"
out_dir=$build/${name}_out

echo "compiler=$compiler"
echo "out=$out_dir"

#bridge_lib=$toolchain/lib/libbridge.a
bridge_lib=$dir/../cpp_bridge/build/libbridge.a
#llvm_lib="$toolchain/lib/libLLVM.so.19.1"
llvm_lib="/usr/lib/llvm-19/lib/libLLVM.so.19.1"

libs+=$llvm_lib
flags="$bridge_lib"
flags="$flags $out_dir/std.a"
flags="$flags $libs"
flags="$flags -lstdc++"

#compile std
$compiler c -cache -static -stdpath $dir/../src -i $dir/../src -out $out_dir $dir/../src/std

if [ ! "$?" -eq "0" ]; then
  echo "error while compiling"
  exit 1
fi
#todo use toolchain's std dir?
linker=$($dir/find_llvm.sh clang)
LD=$linker $compiler c -norun -cache -stdpath $dir/../src -i $dir/../src -out $out_dir -flags "$flags" -name $name $dir/../src/parser -j 1
if [ ! "$?" -eq "0" ]; then
  echo "error while compiling"
  exit 1
fi

#change llvm path to relative to toolchain
if ! command -v patchelf 2>&1 >/dev/null; then
  sudo apt install -y patchelf
fi

#patchelf --set-rpath '$ORIGIN/../lib' ${out_dir}/${name}

cp ${out_dir}/${name} $build
