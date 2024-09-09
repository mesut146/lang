../../build/x2 c -norun -nolink -out . -stdpath ../../src vararg.x 
gcc -c -o main.o main.c
gcc vararg.o main.o
./a.out
rm a.out main.o vararg.o vararg.ll
