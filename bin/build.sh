dir=$(dirname $0)

if [ ! -d "$1" ]; then
 echo "provide toolchain dir"
 exit
fi

if [ -z "$2" ]; then
 echo "provide version"
 exit
fi

toolchain=$1
version=$2
compiler="$toolchain/bin/x"
build=$dir/../build
mkdir -p $build
name="xx2"
out_dir=$build/${name}_out

echo "compiler=$compiler"
echo "out=$out_dir"

$dir/build_std.sh $compiler $out_dir || exit 1
LIB_STD=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt

$dir/build_ast.sh $compiler $out_dir || exit 1
LIB_AST=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt

bridge_lib=$toolchain/lib/libbridge.a
llvm_lib="$toolchain/lib/libLLVM.so.19.1"
flags="$bridge_lib"
flags="$flags $LIB_AST"
flags="$flags $LIB_STD"
flags="$flags $llvm_lib"
flags="$flags -lstdc++"
#todo use toolchain's std dir?
linker=$($dir/find_llvm.sh clang)
LD=$linker $compiler c -norun -cache -stdpath $dir/../src -i $dir/../src -out $out_dir -flags "$flags" -name $name $dir/../src/parser
if [ ! "$?" -eq "0" ]; then
  echo "error while compiling"
  exit 1
fi

cp ${out_dir}/${name} $build

$dir/make_toolchain.sh ${out_dir}/${name} $toolchain . ${version} -zip
