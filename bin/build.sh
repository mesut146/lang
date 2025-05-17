dir=$(dirname $0)

if [ -z "$1" ]; then
 echo "provide toolchain dir"
 exit
fi

toolchain=$1
compiler="$toolchain/bin/x"
build=$dir/../build
mkdir -p $build
name="xx2"
out_dir=$build/${name}_out

echo "compiler=$compiler"
echo "out=$out_dir"

bridge_lib=$toolchain/lib/libbridge.a
llvm_lib="$toolchain/lib/libLLVM.so"

libs+=$llvm_lib
flags="$bridge_lib"
flags="$flags $out_dir/std.a"
flags="$flags $libs"
flags="$flags -lstdc++"

#compile std
$compiler c -static -stdpath $dir/../src -i $dir/../src -out $out_dir $dir/../src/std

#todo use toolchain's std dir?
LD=clang $compiler c -norun -cache -stdpath $dir/../src -i $dir../src -out $out_dir -flags "$flags" -name $name $dir/../src/parser

cp ${out_dir}/${name} $build

$dir/make_toolchain.sh ${out_dir}/${name} $toolchain . -zip
