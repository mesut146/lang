dir=$(dirname $0)

if [ ! -d "$1" ]; then
 echo "provide toolchain dir" && exit 1
fi

if [ -z "$2" ]; then
 echo "provide version" && exit 1
fi

toolchain=$1
version=$2
target_tool=$3
compiler="$toolchain/bin/x"
build=$dir/../build
name="xx2"

if [ -d "$target_tool" ]; then
  name="x_arm64"
fi

out_dir=$build/${name}_out

mkdir -p $out_dir

linker=$($dir/find_llvm.sh clang)
if [ -d "$target_tool" ]; then
   linker="aarch64-linux-gnu-g++"
   export target_triple="aarch64-linux-gnu"
fi
if [ ! -z "$XTERMUX" ]; then
  linker="./android-ndk-r27c/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang++"
  export target_triple="aarch64-unknown-linux-android24"
fi
export LD=$linker

$dir/build_std.sh $compiler $out_dir || exit 1
LIB_STD=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt

$dir/build_ast.sh $compiler $out_dir || exit 1
LIB_AST=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt

bridge_lib="$toolchain/lib/libbridge.a"
llvm_lib="$toolchain/lib/libLLVM.so.19.1"
#flags="$bridge_lib"
flags="$flags $LIB_AST"
flags="$flags $LIB_STD"
flags="$flags $llvm_lib"
flags="$flags -lstdc++"
#todo use toolchain's std dir?

cmd="$compiler c -norun -cache -stdpath $dir/../src -i $dir/../src -out $out_dir -flags '$flags' -name $name $dir/../src/parser"
if [ ! -z "$XOPT" ]; then
  cmd="$cmd $XOPT"
fi
if [ ! -z "$XDEBUG" ]; then
  cmd="$cmd -g"
fi
eval $cmd
if [ ! "$?" -eq "0" ]; then
  echo "error while compiling\n$cmd" && exit 1
fi

cp ${out_dir}/${name} $build

if [ ! -z "$XSTAGE" ]; then
  compiler2=${out_dir}/${name}
  cmd="${compiler2} c -norun -cache -stdpath $dir/../src -i $dir/../src -out $out_dir -flags '$flags' -name $name-stage2 $dir/../src/parser"
  eval $cmd
fi

if [ -d "$target_tool" ]; then
  $dir/make_toolchain.sh ${out_dir}/${name} $target_tool $dir/.. ${version} -zip || exit 1
else
  $dir/make_toolchain.sh ${out_dir}/${name} $toolchain $dir/.. ${version} -zip || exit 1
fi