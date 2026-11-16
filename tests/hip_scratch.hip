#include <hip/hip_runtime.h>
__global__ void scr(int *out, int n) {
  int a[256];  // indexed by a runtime value: the compiler must put it in scratch (private segment)
  for (int i = 0; i < 256; i++) a[i] = i * n;
  out[threadIdx.x] = a[(threadIdx.x * n) & 255];
}
int main() {
  int *d;
  hipMalloc(&d, 1 << 20);  // never freed: the GPU timeline needs a live block
  scr<<<1, 64>>>(d, 3);
  hipDeviceSynchronize();
  return 0;
}
// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 AMARBARO · amarbaro.org labs (header at the end: the tests check line numbers)
