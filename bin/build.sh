dir=$(dirname $0)

#compiler=$dir/x2-1.0-x64
#compiler=$dir/x3-x64
compiler=$dir/x4

build=$dir/../build/x_out

name=x-x64

echo "c -static -noroot -stdpath $dir/../src -i $dir/../src -out $build $dir/../src/std"
$compiler c -static -noroot -stdpath $dir/../src -i $dir/../src -out $build $dir/../src/std

echo "c -norun -cache -noroot -stdpath $dir/../src -i $dir../src -out $build -flags "$dir/../cpp_bridge/build/libbridge.a $build/std.a /usr/lib/llvm-16/lib/libLLVM.so -lstdc++" $dir/../src/parser"
vendor=x4 $compiler c -norun -cache -noroot -stdpath $dir/../src -i $dir../src -out $build -flags "$dir/../cpp_bridge/build/libbridge.a $build/std.a /usr/lib/llvm-16/lib/libLLVM.so -lstdc++" -name $name $dir/../src/parser
