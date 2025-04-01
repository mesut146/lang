dir=$(dirname $0)
rm $dir/build/libbridge.a $dir/build/bridge.o
clang++-16 -I/usr/lib/llvm-16/include/ \
-c -o $dir/build/bridge.o $dir/src/bridge.cpp
ar rcs $dir/build/libbridge.a $dir/build/bridge.o
/usr/bin/ranlib $dir/build/libbridge.a
#rm $dir/build/bridge.o
