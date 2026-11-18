// 3000 short threads, each allocating: their signal stacks must go back at exit.
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
static void *work(void *a) { free(malloc(32)); return a; }
static long maps(void) {  // VmSize in KiB: adjacent anonymous maps merge, so counting lines hides it
  FILE *f = fopen("/proc/self/status", "r"); char l[256]; long k = 0;
  while (fgets(l, sizeof l, f)) if (sscanf(l, "VmSize: %ld", &k) == 1) break;
  fclose(f); return k;
}
int main(void) {
  long before = maps();
  for (int i = 0; i < 3000; i++) { pthread_t t; pthread_create(&t, 0, work, 0); pthread_join(t, 0); }
  printf("vm_grown_kib=%ld\n", maps() - before);
  return 0;
}
