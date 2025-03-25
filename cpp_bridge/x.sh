clang++-16 -I/usr/lib/llvm-16/include/ \
-c -o build/bridge.o src/bridge.cpp
ar s build/libbridge.a build/bridge.o
/usr/bin/ranlib build/libbridge.a
#rm build/bridge.o
