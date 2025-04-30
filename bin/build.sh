dir=$(dirname $0)

if [ -z "$1" ]; then
 echo "provide compiler"
fi

compiler="$1"

name=$(basename $compiler)2

build=$dir/../build
out_dir=$build/${name}_out


bridge=$dir/../cpp_bridge/build/libbridge.a
#bridge=$dir/../cpp_bridge/build/libbridge.so

sf=$(./find_llvm.sh)
libdir=$(llvm-config${sf} --libdir)
libs="$libdir/libLLVM.so"
flags="$bridge"
flags+=" $out_dir/std.a"
flags+=" $libs"
flags+=" -lstdc++"

$dir/../cpp_bridge/x.sh

#compile std
$compiler c -static -stdpath $dir/../src -i $dir/../src -out $out_dir $dir/../src/std

vendor=x4 compiler_name=$name version=1.7 \
$compiler c -norun -cache -stdpath $dir/../src -i $dir../src -out $out_dir -flags "$flags" -name $name $dir/../src/parser

cp ${out_dir}/${name} $build
