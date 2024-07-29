dir=$(dirname $0)
#compiler=$dir/x-1.0-x64
compiler=$dir/x2-1.0-x64

build=$dir/../build/x2_out

$compiler c -static -noroot -stdpath $dir/../src -i $dir/../src -out $build $dir/../src/std
$compiler c -norun -cache -noroot -stdpath $dir/../src -i $dir../src -out $build -flags "$dir/../cpp_bridge/build/libbridge.a $build/std.a /usr/lib/llvm-16/lib/libLLVM.so -lstdc++" $dir/../src/parser
