dir=$(dirname $0)

if [ -z "$1" ]; then
 echo "provide compiler"
 exit
fi

cur=$(dirname $0)

compiler="$1"

echo "compiler=$1"

#name=$(basename $compiler)2
name="x2"

build=$dir/../build
out_dir=$build/${name}_out


bridge=$dir/../cpp_bridge/build/libbridge.a
#bridge=$dir/../cpp_bridge/build/libbridge.so

sf=$($cur/find_llvm.sh)
libdir=$(llvm-config${sf} --libdir)
libs="$libdir/libLLVM.so"
flags="$bridge"
flags="$flags $out_dir/std.a"
flags="$flags $libs"
flags="$flags -lstdc++"

$dir/../cpp_bridge/x.sh

#compile std
$compiler c -static -stdpath $dir/../src -i $dir/../src -out $out_dir $dir/../src/std

#vendor=x4 compiler_name=$name version=1.7 \
$compiler c -norun -cache -stdpath $dir/../src -i $dir../src -out $out_dir -flags "$flags" -name $name $dir/../src/parser

cp ${out_dir}/${name} $build
