//coarse async sampling profiler for x-compiled binaries (no ptrace/perf
//needed): SIGPROF every 10ms, backtrace() into a preallocated buffer
//(no malloc in handler), PID-suffixed dump of adjusted addresses at exit.
//build: gcc -shared -fPIC -O2 -o libsprof.so bin/sprof.c
//use: bin/sprof.sh <binary> <args...>
#define _GNU_SOURCE
#include <execinfo.h>
#include <signal.h>
#include <sys/time.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#define DEPTH 16
#define MAXS 4096
static void* buf[MAXS * (DEPTH + 1)];
static int nsamples = 0;

static void handler(int sig) {
    (void)sig;
    if (nsamples >= MAXS) return;
    void* bt[DEPTH];
    int n = backtrace(bt, DEPTH);
    void** slot = buf + nsamples * (DEPTH + 1);
    slot[0] = (void*)(long)n;
    for (int i = 0; i < DEPTH; i++) slot[i + 1] = (i < n) ? bt[i] : 0;
    nsamples++;
}

__attribute__((constructor)) static void start_prof(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = handler;
    sa.sa_flags = SA_RESTART;
    sigaction(SIGPROF, &sa, 0);
    struct itimerval it;
    it.it_interval.tv_sec = 0;
    it.it_interval.tv_usec = 10000;
    it.it_value = it.it_interval;
    setitimer(ITIMER_PROF, &it, 0);
}

__attribute__((destructor)) static void dump_prof(void) {
    struct itimerval off;
    memset(&off, 0, sizeof(off));
    setitimer(ITIMER_PROF, &off, 0);
    //main-binary base from /proc/self/maps (first mapping of /proc/self/exe)
    char exep[256];
    ssize_t el = readlink("/proc/self/exe", exep, sizeof(exep) - 1);
    if (el < 0) return;
    exep[el] = 0;
    FILE* maps = fopen("/proc/self/maps", "r");
    unsigned long base = 0;
    if (maps) {
        char line[512];
        while (fgets(line, sizeof(line), maps)) {
            if (strstr(line, exep)) {
                base = strtoul(line, 0, 16);
                break;
            }
        }
        fclose(maps);
    }
    const char* dir = getenv("SPROF_DIR");
    if (!dir) dir = "/tmp/opencode";
    char out[256];
    snprintf(out, sizeof(out), "%s/prof.%d.bin", dir, getpid());
    int fd = open(out, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return;
    char tmp[32];
    for (int s = 0; s < nsamples; s++) {
        void** slot = buf + s * (DEPTH + 1);
        int n = (int)(long)slot[0];
        for (int i = 0; i < n; i++) {
            unsigned long a = (unsigned long)slot[i + 1] - base;
            int l = snprintf(tmp, sizeof(tmp), "%lx\n", a);
            if (l > 0) write(fd, tmp, (unsigned)l);
        }
        write(fd, "---\n", 4);
    }
    close(fd);
}
