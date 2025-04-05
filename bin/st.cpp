#include <stdio.h>

static int x = 55;

int get(){
 return x + 10;
}

static int y = get();

int main(){
 printf("x=%d y=%d\n", x, y);
}
