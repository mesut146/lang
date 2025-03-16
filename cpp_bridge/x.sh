g++ -I/usr/lib/llvm-16/include/ \
-c -o bridge.o src/bridge.cpp
ar rvs libbridge.a bridge.o
