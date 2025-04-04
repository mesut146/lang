libdir=$(llvm-config --libdir)

clang++ -lstdc++ -o x-termux x-termux.a std-termux.a ../cpp_bridge/build/libbridge.a $libdir/libLLVM.so
