dir=$(dirname $0)

#compiler=$dir/x-1.4-x64
compiler=$dir/x2-1.4-x64
#compiler=$dir/x3-1.3-x64
#compiler=$dir/../build/x-x64

#arch=arm
arch=x64

name=x2-1.4-$arch

build=$dir/../build
out_dir=$build/${name}_out

compiler=$build/x2
target_triple="aarch64-linux-gnu"

bridge=$dir/../cpp_bridge/build/libbridge.a
#bridge=$dir/../cpp_bridge/build/libbridge_shared.so
flags="$bridge $out_dir/std.a $libs"
flags="$flags -lstdc++"
libs="/usr/lib/llvm-16/lib/libLLVM.so"

$compiler c -static -stdpath $dir/../src -i $dir/../src -out $out_dir $dir/../src/std

vendor=x4 compiler_name=$name version=1.4 \
$compiler c -norun -cache -stdpath $dir/../src -i $dir../src -out $out_dir -flags "$flags" -name $name $dir/../src/parser

cp ${out_dir}/${name} $build
