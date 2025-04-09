#include <stdio.h>
#include <stdarg.h>

int test(int cnt, ...){
    va_list argp;
    va_start(argp, cnt);
    printf("from c test(%d)", cnt);
    if(cnt == 1){
        int a1 = va_arg(argp, int);
        printf(" a1=%d", a1);
    }else if(cnt == 2){
        int a1 = va_arg(argp, int);
        long a2 = va_arg(argp, long);
        printf(" a1=%d a2=%ld", a1, a2);
    }else if(cnt == 3){
        int a1 = va_arg(argp, int);
        char* a2 = va_arg(argp, char*);
        printf(" a1=%d a2='%s'", a1, a2);
    }
    printf("\n");
    va_end(argp);
    return cnt;
}