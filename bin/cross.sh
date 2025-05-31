dir=$(dirname $0)
echo "cross.sh='$@'"
if [ -z "$1" ]; then
 echo "provide host toolchain dir"
 exit
fi

if [ ! -d "$2" ]; then
 echo "provide target toolchain dir"
 exit
fi

if [ -z "$3" ]; then
 echo "provide version"
 exit
fi

toolchain=$1
toolchain_target=$2
version=$3
compiler="$toolchain/bin/x"
build=$dir/../build
name="x_arm64"
out_dir=$build/${name}_out

mkdir -p $out_dir

sudo=""
if command -v sudo 2>&1 >/dev/null; then
  sudo="sudo"
fi
$sudo dpkg --add-architecture arm64
$sudo apt-get update
$sudo apt-get install -y zip unzip libffi8 libedit2 libzstd1 libxml2
$sudo apt-get install -y --only-upgrade libstdc++6
$sudo apt-get install -y binutils g++-aarch64-linux-gnu libffi8:arm64 libedit2:arm64 libzstd1:arm64 libxml2:arm64


#linker=$($dir/find_llvm.sh clang)
linker="aarch64-linux-gnu-g++"

target_triple="aarch64-linux-gnu" $compiler c -cache -static -stdpath $dir/../src -i $dir/../src -out $out_dir $dir/../src/std
if [ ! "$?" -eq "0" ]; then
  echo "error while compiling"
  exit 1
fi

target_triple="aarch64-linux-gnu" LD=$linker $dir/build_ast.sh $compiler || exit 1
LIB_AST=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt

target_triple="aarch64-linux-gnu" LD=$linker $dir/build_std.sh $compiler || exit 1
LIB_STD=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt

bridge_lib=$toolchain_target/lib/libbridge.a
llvm_lib=$toolchain_target/lib/libLLVM.so.19.1

flags="$bridge_lib"
flags="$flags $LIB_AST"
flags="$flags $LIB_STD"
flags="$flags $llvm_lib"
flags="$flags -lstdc++"

#todo use toolchain's std dir?
target_triple="aarch64-linux-gnu" LD=$linker $compiler c -norun -cache -stdpath $dir/../src -i $dir../src -out $out_dir -flags "$flags" -name $name $dir/../src/parser

if [ ! "$?" -eq "0" ]; then
  echo "Build failed"
  exit 1
fi

export ARCH=aarch64
$dir/make_toolchain.sh $out_dir/$name $toolchain_target $dir/.. $version -zip
exit 0

