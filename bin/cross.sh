dir=$(dirname $0)

if [ -z "$1" ]; then
 echo "provide host toolchain dir" && exit 1
fi

if [ ! -d "$2" ]; then
 echo "provide target toolchain dir" && exit 1
fi

if [ -z "$3" ]; then
 echo "provide version" && exit 1
fi

host_tool=$1
target_tool=$2
version=$3
compiler=$host_tool/bin/x
build=$dir/../build
name="x_arm64"
out_dir=$build/${name}_out

mkdir -p $out_dir

linker="aarch64-linux-gnu-g++"
export target_triple="aarch64-linux-gnu"
if [ "$4" = "-termux" ]; then
  linker="./android-ndk-r27c/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang++"
  export target_triple="aarch64-unknown-linux-android24"
fi
export LD=$linker

$dir/build_ast.sh $compiler $out_dir || exit 1
LIB_AST=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt

$dir/build_std.sh $compiler $out_dir || exit 1
LIB_STD=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt

bridge_lib=$target_tool/lib/libbridge.a
llvm_lib=$target_tool/lib/libLLVM.so.19.1

#flags="$bridge_lib"
flags="$flags $LIB_AST"
flags="$flags $LIB_STD"
flags="$flags $llvm_lib"
flags="$flags -lstdc++"

static_flag=""
if [ "$4" = "-termux" ]; then
  #static_flag="-static"
  static_flag=""
fi


cmd="$compiler c -norun -cache -stdpath $dir/../src -i $dir/../src -out $out_dir -flags '$flags' -name $name $static_flag $dir/../src/parser"
eval $cmd
if [ ! "$?" -eq "0" ]; then
  echo "Build failed\n$cmd" && exit 1
fi

if [ "$4" = "-termux" ]; then
 for obj in $out_dir/*.o; do
   #dump=$(objdump -r --section=".ctors" $obj)
   #dump["*tatic_init"]
    echo "tmux"
 done
fi

export ARCH=aarch64
$dir/make_toolchain.sh $out_dir/$name $target_tool $dir/.. $version -zip || exit 1
