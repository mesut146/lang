// mcnt.c: an LD_PRELOAD allocation profiler for the x compiler.
//
// valgrind/perf are not available on every dev box (and callgrind is slow
// enough that it changes the mix), so this counts allocations directly:
//
//   - malloc/realloc/calloc/free per 16-byte size class up to 512 bytes,
//     powers of two above that;
//   - each allocation is attributed to the module its *caller* lives in
//     (the compiler binary vs libLLVM/libstdc++/libc), and to the exact
//     call site inside the compiler binary;
//   - with MCNT_SAMPLE_OFF=<offset> it also samples stack traces at that
//     one call site (1 in 256), which is how the callers of a hot
//     allocator like List<u8>::get_malloc are found.
//
// The compiler forks/execs one worker per module, so a plain counter
// reports the inherited parent state in every child. The shim therefore
// zeroes the counters in forked children (pthread_atfork) and also dumps
// on _exit(), which workers use; the per-process blocks are then summed.
// Startup allocations made before our constructor runs are served from a
// static arena and are (intentionally) not counted.
//
// build: gcc -O2 -fPIC -shared -o /tmp/mcnt.so bin/mcnt.c -ldl -pthread
// run:   LD_PRELOAD=/tmp/mcnt.so MCNT_OUT=/tmp/alloc.txt ./build/stage1 \
//            c -static -cache -j 1 -O2 -out <dir> -stdpath src -i src \
//            -name std src/std
// read:  bin/mcnt.py /tmp/alloc.txt --bin ./build/stage1
//
// Notes: -cache reuses a warm out dir, and a warm dir compiles in ~1/3 of
// the time with ~1/30 of the allocations, so always profile a wiped out
// dir (same rule as the test gates). Counts, not cycles: malloc/free cost
// depends on the pattern too (see handoff.md, batch 17 profile).
#define _GNU_SOURCE
#include <dlfcn.h>
#include <link.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <pthread.h>
#include <time.h>
#include <execinfo.h>

extern char *program_invocation_short_name;

#define NBUCK 96
#define NMOD 32
#define NIP 8192

static void *(*rmalloc)(size_t);
static void *(*rrealloc)(void *, size_t);
static void *(*rcalloc)(size_t, size_t);
static void (*rfree)(void *);
static void (*r_exit)(int);

static char boot[1 << 20];
static size_t boot_off;
static int ready;         // real_* resolved and the module map is live
static __thread int busy; // inside our own init / dl_* callbacks

static _Atomic uint64_t buck_n[NBUCK], buck_bytes[NBUCK];
static _Atomic uint64_t mod_n[NMOD], mod_bytes[NMOD], mod_free[NMOD];
static char modname[NMOD][48];
static int nmods;

static struct {
  _Atomic uintptr_t off;
  _Atomic uint64_t cnt;
} ipt[NIP];

static struct {
  uintptr_t lo, hi;
  int mod;
} ranges[NMOD * 2];
static int nranges;

static uintptr_t main_bias;
static uintptr_t sample_off;
static _Atomic uint64_t sample_n;
static __thread int bt_busy;

static _Atomic uint64_t t_malloc, t_realloc, t_calloc, t_free;
static _Atomic uint64_t t_bytes, t_realloc_bytes, t_calloc_bytes;
static const char *out_path;
static int want_mods = 1;
static int want_trace;

static int bucket(size_t n) {
  if (n <= 512)
    return (int)((n + 15) >> 4); // 16-byte classes, 0..32
  int l = 63 - __builtin_clzll((unsigned long long)n); // 9..63
  return 33 + (l - 9);
}

static void put(const char *s, int len);

static long long now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

// Every boot block carries a 32-byte header so realloc/free can be
// handled while we are still resolving the real allocator.
static void *boot_alloc(size_t n) {
  size_t a = (n + 15) & ~(size_t)15;
  if (boot_off + a + 32 > sizeof boot)
    return NULL;
  size_t *hdr = (size_t *)(boot + boot_off);
  hdr[0] = n;
  boot_off += 32;
  void *p = boot + boot_off;
  boot_off += a;
  return p;
}

static int is_boot(const void *p) {
  return (const char *)p >= boot && (const char *)p < boot + sizeof boot;
}

static void *boot_realloc(void *old, size_t n) {
  size_t oldn = ((size_t *)old)[-4];
  void *p = boot_alloc(n);
  if (p && oldn)
    memcpy(p, old, oldn < n ? oldn : n);
  return p;
}

static int mod_for(uintptr_t ip) {
  for (int i = 0; i < nranges; i++)
    if (ip >= ranges[i].lo && ip < ranges[i].hi)
      return ranges[i].mod;
  return 0;
}

static void logmsg(const char *what, const char *arg) {
  if (!want_trace)
    return;
  char b[4096];
  int n = snprintf(b, sizeof b, "MCNT trace t=%lld pid=%d ppid=%d %s",
                   now_ms(), (int)getpid(), (int)getppid(), what);
  if (arg && arg[0])
    n += snprintf(b + n, sizeof b - (size_t)n, " %s", arg);
  n += snprintf(b + n, sizeof b - (size_t)n, "\n");
  put(b, n);
}

static void bt_sample(void) {
  if (bt_busy)
    return;
  bt_busy = 1;
  void *bt[16];
  int k = backtrace(bt, 16);
  char b[2048];
  int L = 0;
  L += snprintf(b + L, sizeof b - (size_t)L, "MCNT bt");
  for (int i = 1; i < k && i < 12 && L < (int)sizeof b - 40; i++)
    L += snprintf(b + L, sizeof b - (size_t)L, " %lx",
                  (unsigned long)((uintptr_t)bt[i] - main_bias));
  L += snprintf(b + L, sizeof b - (size_t)L, "\n");
  put(b, L);
  bt_busy = 0;
}

static void note_alloc(void *ip, size_t n) {
  if (bt_busy) // allocations made by backtrace() itself
    return;
  int b = bucket(n);
  atomic_fetch_add_explicit(&buck_n[b], 1, memory_order_relaxed);
  atomic_fetch_add_explicit(&buck_bytes[b], n, memory_order_relaxed);
  if (!want_mods)
    return;
  int m = mod_for((uintptr_t)ip);
  atomic_fetch_add_explicit(&mod_n[m], 1, memory_order_relaxed);
  atomic_fetch_add_explicit(&mod_bytes[m], n, memory_order_relaxed);
  if (m != 0 || !main_bias)
    return;
  uintptr_t off = (uintptr_t)ip - main_bias;
  if (sample_off && off == sample_off &&
      (atomic_fetch_add_explicit(&sample_n, 1, memory_order_relaxed) & 255) == 0)
    bt_sample();
  size_t h = (off >> 2) & (NIP - 1);
  for (int k = 0; k < 8; k++) {
    size_t sl = (h + (size_t)k) & (NIP - 1);
    uintptr_t cur = atomic_load(&ipt[sl].off);
    if (cur == off) {
      atomic_fetch_add_explicit(&ipt[sl].cnt, 1, memory_order_relaxed);
      return;
    }
    if (cur == 0) {
      uintptr_t exp = 0;
      if (atomic_compare_exchange_strong(&ipt[sl].off, &exp, off))
        atomic_fetch_add_explicit(&ipt[sl].cnt, 1, memory_order_relaxed);
      else if (atomic_load(&ipt[sl].off) == off)
        atomic_fetch_add_explicit(&ipt[sl].cnt, 1, memory_order_relaxed);
      return;
    }
  }
}

static void note_free(void *ip) {
  if (!want_mods)
    return;
  int m = mod_for((uintptr_t)ip);
  atomic_fetch_add_explicit(&mod_free[m], 1, memory_order_relaxed);
}

static int phdr_cb(struct dl_phdr_info *info, size_t size, void *data) {
  (void)size;
  (void)data;
  const char *name = info->dlpi_name;
  if (!name || !name[0]) {
    name = "<main>";
  } else {
    const char *s = strrchr(name, '/');
    if (s)
      name = s + 1;
  }
  int m = -1;
  for (int i = 0; i < nmods; i++)
    if (strncmp(modname[i], name, sizeof modname[i] - 1) == 0) {
      m = i;
      break;
    }
  if (m < 0) {
    if (nmods == NMOD)
      return 0;
    m = nmods++;
    strncpy(modname[m], name, sizeof modname[m] - 1);
  }
  for (int i = 0; i < info->dlpi_phnum; i++) {
    const ElfW(Phdr) *ph = &info->dlpi_phdr[i];
    if (ph->p_type != PT_LOAD)
      continue;
    if (nranges == (int)(sizeof ranges / sizeof ranges[0]))
      break;
    if (m == 0 && !main_bias)
      main_bias = (uintptr_t)info->dlpi_addr;
    ranges[nranges].lo = (uintptr_t)(info->dlpi_addr + ph->p_vaddr);
    ranges[nranges].hi = ranges[nranges].lo + ph->p_memsz;
    ranges[nranges].mod = m;
    nranges++;
  }
  return 0;
}

static int dumped;
static void do_dump(void);

// A forked worker inherits the parent's counters, so zero them in the
// child: each process then reports only its own traffic and the blocks
// can be summed.
static void child_reset(void) {
  for (int i = 0; i < NBUCK; i++) {
    atomic_store(&buck_n[i], 0);
    atomic_store(&buck_bytes[i], 0);
  }
  for (int i = 0; i < NMOD; i++) {
    atomic_store(&mod_n[i], 0);
    atomic_store(&mod_bytes[i], 0);
    atomic_store(&mod_free[i], 0);
  }
  for (int i = 0; i < NIP; i++) {
    atomic_store(&ipt[i].off, 0);
    atomic_store(&ipt[i].cnt, 0);
  }
  atomic_store(&t_malloc, 0);
  atomic_store(&t_realloc, 0);
  atomic_store(&t_calloc, 0);
  atomic_store(&t_free, 0);
  atomic_store(&t_bytes, 0);
  atomic_store(&t_realloc_bytes, 0);
  atomic_store(&t_calloc_bytes, 0);
  dumped = 0;
}

__attribute__((constructor)) static void init(void) {
  if (ready)
    return;
  busy = 1;
  rmalloc = dlsym(RTLD_NEXT, "malloc");
  rrealloc = dlsym(RTLD_NEXT, "realloc");
  rcalloc = dlsym(RTLD_NEXT, "calloc");
  rfree = dlsym(RTLD_NEXT, "free");
  r_exit = dlsym(RTLD_NEXT, "_exit");
  pthread_atfork(NULL, NULL, child_reset);
  if (!nranges)
    dl_iterate_phdr(phdr_cb, NULL);
  out_path = getenv("MCNT_OUT");
  const char *so = getenv("MCNT_SAMPLE_OFF");
  sample_off = so ? (uintptr_t)strtoull(so, NULL, 0) : 0;
  const char *wm = getenv("MCNT_MOD");
  want_mods = wm ? (wm[0] != '0') : 1;
  const char *wt = getenv("MCNT_TRACE");
  want_trace = wt ? (wt[0] != '0') : 0;
  ready = rmalloc && rrealloc && rcalloc && rfree && nranges > 0;
  busy = 0;
}

void *malloc(size_t n) {
  if (!ready) {
    if (busy)
      return boot_alloc(n);
    init();
    if (!ready)
      return boot_alloc(n);
  }
  void *p = rmalloc(n);
  atomic_fetch_add_explicit(&t_malloc, 1, memory_order_relaxed);
  atomic_fetch_add_explicit(&t_bytes, n, memory_order_relaxed);
  note_alloc(__builtin_return_address(0), n);
  return p;
}

void *calloc(size_t a, size_t b) {
  size_t n = a * b;
  if (!ready) {
    if (busy) {
      void *p = boot_alloc(n);
      if (p)
        memset(p, 0, n);
      return p;
    }
    init();
    if (!ready) {
      void *p = boot_alloc(n);
      if (p)
        memset(p, 0, n);
      return p;
    }
  }
  void *p = rcalloc(a, b);
  atomic_fetch_add_explicit(&t_calloc, 1, memory_order_relaxed);
  atomic_fetch_add_explicit(&t_calloc_bytes, n, memory_order_relaxed);
  note_alloc(__builtin_return_address(0), n);
  return p;
}

void *realloc(void *old, size_t n) {
  if (!ready) {
    if (is_boot(old))
      return boot_realloc(old, n);
    if (busy)
      return NULL;
    init();
    if (!ready) {
      if (is_boot(old))
        return boot_realloc(old, n);
      return NULL;
    }
  }
  if (is_boot(old))
    return boot_realloc(old, n);
  void *p = rrealloc(old, n);
  atomic_fetch_add_explicit(&t_realloc, 1, memory_order_relaxed);
  atomic_fetch_add_explicit(&t_realloc_bytes, n, memory_order_relaxed);
  note_alloc(__builtin_return_address(0), n);
  return p;
}

void free(void *p) {
  if (!p)
    return;
  if (is_boot(p))
    return;
  if (!ready && !busy)
    init();
  if (ready) {
    atomic_fetch_add_explicit(&t_free, 1, memory_order_relaxed);
    note_free(__builtin_return_address(0));
  }
  if (rfree)
    rfree(p);
}

static void put(const char *s, int len) {
  if (len <= 0)
    return;
  if (out_path && out_path[0]) {
    int fd = open(out_path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
      if (write(fd, s, (size_t)len)) {}
      close(fd);
      return;
    }
  }
  if (write(2, s, (size_t)len)) {}
}

int fork(void) {
  static int (*r_fork)(void);
  if (!r_fork)
    r_fork = dlsym(RTLD_NEXT, "fork");
  int pid = r_fork ? r_fork() : -1;
  logmsg(pid == 0 ? "fork-child" : "fork-parent", NULL);
  return pid;
}

int execve(const char *path, char *const argv[], char *const envp[]) {
  static int (*r_execve)(const char *, char *const[], char *const[]);
  if (!r_execve)
    r_execve = dlsym(RTLD_NEXT, "execve");
  if (want_trace) {
    char b[2048];
    int n = 0;
    for (int i = 0; argv && argv[i] && i < 16 && n < (int)sizeof b - 80; i++)
      n += snprintf(b + n, sizeof b - (size_t)n, "%s ", argv[i]);
    logmsg("execve", b);
  }
  return r_execve ? r_execve(path, argv, envp) : -1;
}

// Workers may leave through _exit(), which skips the destructor.
void _exit(int status) {
  if (!dumped)
    do_dump();
  if (r_exit)
    r_exit(status);
  for (;;)
    pause();
}

void _Exit(int status) { _exit(status); }

__attribute__((destructor)) static void dump(void) { do_dump(); }

static void do_dump(void) {
  if (dumped)
    return;
  dumped = 1;
  char buf[65536];
  int len = 0;
#define ROOM (int)sizeof buf - len
  len += snprintf(buf + len, ROOM,
                  "MCNT t=%lld pid=%d prog=%s malloc=%llu realloc=%llu "
                  "calloc=%llu free=%llu bytes=%llu realloc_bytes=%llu "
                  "calloc_bytes=%llu\n",
                  now_ms(), (int)getpid(),
                  program_invocation_short_name ? program_invocation_short_name : "?",
                  (unsigned long long)atomic_load(&t_malloc),
                  (unsigned long long)atomic_load(&t_realloc),
                  (unsigned long long)atomic_load(&t_calloc),
                  (unsigned long long)atomic_load(&t_free),
                  (unsigned long long)atomic_load(&t_bytes),
                  (unsigned long long)atomic_load(&t_realloc_bytes),
                  (unsigned long long)atomic_load(&t_calloc_bytes));

  int idx[NMOD];
  for (int i = 0; i < nmods; i++)
    idx[i] = i;
  for (int i = 0; i < nmods; i++)
    for (int j = i + 1; j < nmods; j++)
      if (atomic_load(&mod_n[idx[j]]) > atomic_load(&mod_n[idx[i]])) {
        int t = idx[i];
        idx[i] = idx[j];
        idx[j] = t;
      }
  for (int i = 0; i < nmods && len < (int)sizeof buf - 300; i++) {
    int m = idx[i];
    len += snprintf(buf + len, ROOM,
                    "MCNT mod %-22s n=%-9llu bytes=%-11llu free=%-9llu\n",
                    modname[m], (unsigned long long)atomic_load(&mod_n[m]),
                    (unsigned long long)atomic_load(&mod_bytes[m]),
                    (unsigned long long)atomic_load(&mod_free[m]));
  }

  int top[NBUCK];
  for (int i = 0; i < NBUCK; i++)
    top[i] = i;
  for (int i = 0; i < NBUCK; i++)
    for (int j = i + 1; j < NBUCK; j++)
      if (atomic_load(&buck_n[top[j]]) > atomic_load(&buck_n[top[i]])) {
        int t = top[i];
        top[i] = top[j];
        top[j] = t;
      }
  for (int i = 0; i < NBUCK && len < (int)sizeof buf - 300; i++) {
    int b = top[i];
    uint64_t n = atomic_load(&buck_n[b]);
    if (!n)
      break;
    if (b <= 32)
      len += snprintf(buf + len, ROOM,
                      "MCNT size %4d-%4d n=%-9llu bytes=%llu\n", b * 16,
                      b * 16 + 15, (unsigned long long)n,
                      (unsigned long long)atomic_load(&buck_bytes[b]));
    else
      len += snprintf(buf + len, ROOM,
                      "MCNT size 2^%02d+     n=%-9llu bytes=%llu\n",
                      9 + (b - 33), (unsigned long long)n,
                      (unsigned long long)atomic_load(&buck_bytes[b]));
  }

  int tops[32];
  for (int i = 0; i < 32; i++)
    tops[i] = -1;
  for (int i = 0; i < NIP; i++) {
    uint64_t c = atomic_load(&ipt[i].cnt);
    if (!c)
      continue;
    for (int k = 0; k < 32; k++) {
      if (tops[k] < 0 || c > atomic_load(&ipt[tops[k]].cnt)) {
        for (int j = 31; j > k; j--)
          tops[j] = tops[j - 1];
        tops[k] = i;
        break;
      }
    }
  }
  for (int k = 0; k < 32 && len < (int)sizeof buf - 200; k++) {
    if (tops[k] < 0)
      break;
    len += snprintf(buf + len, ROOM, "MCNT ip off=0x%llx n=%llu\n",
                    (unsigned long long)atomic_load(&ipt[tops[k]].off),
                    (unsigned long long)atomic_load(&ipt[tops[k]].cnt));
  }

  put(buf, len);
#undef ROOM
}
