clear
suffix="-19"

cmd="clang++$suffix -o x-arm64 x-arm64.a std.a ../../cpp_bridge/build/libbridge.a /usr/lib/llvm$suffix/lib/libLLVM.so -lstdc++"

$cmd || echo $cmd
