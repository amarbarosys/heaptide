# AMD scratch: what `GPU SCRATCH` computes

A kernel that spills registers or indexes a local array by a runtime value uses the *private segment* (scratch).
The runtime reserves device memory for it once per queue. heaptide's timeline shows that reservation as
"device: held beyond live blocks" (it is no `hipMalloc` block); `GPU SCRATCH` names it.

## Formula

Source: ROCm/rocm-systems `projects/rocr-runtime/runtime/hsa-runtime/core/runtime/amd_aql_queue.cpp`, commit 24a30043
(`AcquireQueueScratch`, lines 1169-1182; alignment lines 203-205; copy in `.work/gonzales/rocr/`).

```
device_slots    = AlignUp(cu_count, engines) * max_slots_scratch_cu
size_per_thread = AlignUp(private_segment_size, mem_alignment / lanes_per_wave)    mem_alignment = 256 on gfx11+
device_size     = size_per_thread * lanes_per_wave * device_slots                  per queue
```

A queue grows its scratch when a dispatch needs more (`main_size_per_thread`), so what one queue holds is the
**maximum over the kernels it ran**, not a sum over kernels. Several queues add up.

Inputs, none typed by hand:

| term | source |
|---|---|
| `private_segment_size` | `.private_segment_fixed_size` of the kernel in the code object (`llvm-readobj --notes`) |
| `lanes_per_wave` | `.wavefront_size` of the same kernel |
| `cu_count` | KFD node `array_count * cu_per_simd_array` |
| `engines` | KFD node `array_count / simd_arrays_per_engine` |
| `max_slots_scratch_cu` | KFD node property of the same name |

KFD node: `/sys/class/kfd/kfd/topology/nodes/N/properties`, the node with the most SIMDs. RX 7900 XTX: 12 arrays x 8 CUs = 96 CUs,
6 engines, 32 slots per CU: 3,072 slots, x 32 lanes = 98,304 threads.

## Check (Gonzales, bathroom scene, path tracer)

- `rocprofv3 --scratch-memory-trace`: one queue, 1,025 scratch allocations, the largest 2,651,848,704 B.
- Largest dispatched kernel `gonzales_gpu_pt_shade_shade_..._ac8b19d4`: 26,976 B per thread. 26,976 x 98,304 = 2,651,848,704 B.
  The prediction, written before the trace was taken, matches to the byte. Every other allocation is a kernel's `Scratch_Size` x 98,304.
- heaptide held beyond live blocks 2.5457 GiB: scratch 2.4697 GiB, 77.8 MiB left unexplained (printed, not hidden).

Limits: the table lists the code objects *in the executable*. Gonzales carries all its integrators (the VCM kernels alone would
give 3.999 GiB); `--kernels` with a `rocprofv3 --kernel-trace -f csv` of the same program keeps what was dispatched. A kernel in a
shared library or compiled at run time (`libamd_comgr`) is not in the executable and not listed. ROCr also frees and re-acquires
scratch around dispatches (the trace shows 144 allocate/free pairs per size), while the held line stays flat: the formula gives the
reservation a queue can reach, not its value at each instant.
