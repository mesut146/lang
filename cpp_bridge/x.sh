clang++-16 -I/usr/lib/llvm-16/include/ \
-c -o build/bridge.o src/bridge.cpp
ar rvs build/libbridge.a build/bridge.o
/usr/bin/ranlib libbridge.a
#rm build/bridge.o
