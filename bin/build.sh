dir=$(dirname $0)

compiler=$dir/x-1.4-x64
#compiler=$dir/x2-1.4-x64
#compiler=$dir/x3-1.3-x64
#compiler=$dir/../build/x-x64

name=x2-1.4-x64

build=$dir/../build
out_dir=$build/${name}_out

echo "c -static -noroot -stdpath $dir/../src -i $dir/../src -out $out_dir $dir/../src/std"
$compiler c -static -noroot -stdpath $dir/../src -i $dir/../src -out $out_dir $dir/../src/std

echo "c -norun -cache -noroot -stdpath $dir/../src -i $dir../src -out $out_dir -flags "$dir/../cpp_bridge/build/libbridge.a $out_dir/std.a /usr/lib/llvm-16/lib/libLLVM.so -lstdc++" $dir/../src/parser"
libs="$libs /usr/lib/llvm-16/lib/libLLVM.so"

target_triple="aarch64-linux-gnu" vendor=x4 compiler_name=$name version=1.4 $compiler c -norun -cache -noroot -stdpath $dir/../src -i $dir../src -out $out_dir -flags "$dir/../cpp_bridge/build/libbridge.a $out_dir/std.a -lstdc++ $libs" -name $name $dir/../src/parser

cp ${out_dir}/${name} $build
