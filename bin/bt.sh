dir=$(dirname $0)

if [ -z "$1" ]; then
 echo "provide binary" && exit 1
fi

name="xx2"
if [ ! -z "$2" ]; then
 name=$2
fi

if [ "$3" = "-stage2" ]; then
 echo "todo"
fi

compiler=$1
build=$dir/../build
mkdir -p $build
out_dir=$build/${name}_out

if [ -d "$1" ]; then
  compiler="$1/bin/x"
fi

echo "compiler=$compiler"
echo "out=$out_dir"

$dir/build_std.sh $compiler || exit 1
LIB_STD=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt

if [ ! "$?" -eq "0" ]; then
  echo "error while compiling" && exit 1
fi
#todo use toolchain's std dir?
linker=$($dir/find_llvm.sh clang)

$dir/build_ast.sh $compiler lib || exit 1
LIB_AST=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt

bin=$(dirname $compiler)


#bridge_lib=$toolchain/lib/libbridge.a
bridge_lib=$dir/../cpp_bridge/build/libbridge.a
llvm_lib="/usr/lib/llvm-19/lib/libLLVM.so.19.1"
if [[ "$bin" == */bin ]]; then
  toolchain=$bin/..
  llvm_lib="$toolchain/lib/libLLVM.so.19.1"
fi

flags="$bridge_lib"
#flags="$flags $out_dir/std.a"
flags="$flags $LIB_STD"
flags="$flags $LIB_AST"
flags="$flags $llvm_lib"
flags="$flags -lstdc++"
cmd="LD=$linker $compiler c -norun -cache -stdpath $dir/../src -i $dir/../src -out $out_dir -flags '$flags' -name $name $dir/../src/parser -j 1"
eval $cmd

if [ ! "$?" -eq "0" ]; then
  echo "error while compiling"
  echo $cmd
  exit 1
fi

#change llvm path to relative to toolchain
if ! command -v patchelf 2>&1 >/dev/null; then
  sudo apt install -y patchelf
fi

#patchelf --set-rpath '$ORIGIN/../lib' ${out_dir}/${name}

cp ${out_dir}/${name} $build
