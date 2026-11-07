# Design

heaptide records allocations and scans for leaks inside the target. The report only reads a file.
Details: [how-it-works.md](how-it-works.md). File layout: [file-format.md](file-format.md).

## Layout: one job per part

```
heaptide (bash)  ->  libheaptide.so (C, in the target)  ->  heaptide.<pid>.bin  ->  heaptide_report (Mojo)
launch, wrap         hooks, counters, reachability scan      one file per process     symbolize, judge, print
```

- `heaptide` (bash): sets `LD_PRELOAD`, maps flags to `HEAPTIDE_*` variables, recovers the report of
  a killed process, and implements `snapshot`, `attach`, `detach`, `diff` and `flame`.
- `shim/heaptide.c` (C, one file): lives in the target, so no runtime of its own. Its memory comes from raw `mmap`, never from the allocator it hooks.
- `report/heaptide_report.mojo`: runs after the target is gone and only reads the file. It
  symbolizes all needed addresses in one `llvm-symbolizer` batch and judges GROWTH.
- `py/run.py`: the runner for `--py`. It starts the user's script and writes the Python holders.

## Data flow

1. Each hooked call unwinds, turns the stack into a 64-bit hash plus a 32-bit check, and bumps one
   counter row for that stack. A live block costs one 16 B table entry.
2. A sampler thread records live bytes every `--every` ms. GROWTH is a fit over these samples.
3. At exit, on a stop signal, on a crash or on `snapshot`, the shim scans the heap the way
   LeakSanitizer does: roots are globals, other threads' stacks and registers, and the linker's
   blocks. Each unfreed block is direct, indirect or reachable.
4. The shim writes `heaptide.<pid>.bin` as `.tmp`, then renames it. A reader never sees half a file.
5. `report` reads the `.bin`, symbolizes, and prints LEAKS, GROWTH, PEAK, HOTSPOTS, TEMPORARIES.

## Memory model

- One counter row per distinct call stack, one 16 B entry per live block. Cost does not grow with
  the number of events, only with live blocks and distinct stacks.
- Each thread keeps its own live total and batches updates to a stack's row. It also remembers the
  ids of its last 64 stacks, so a known site skips the shared table.
- The site tables sit in a sparse file in `/dev/shm`. It outlives a process killed by SIGKILL or
  the OOM killer, so a report is still possible (without a leak scan: the heap is gone).
- `--py` tracks about 37 B per live Python block. The table is capped at 1/8 of the memory
  available at start. Past the cap blocks go untracked and the report says so.
- A snapshot forks the program with a raw `clone` and scans the copy. The pause is the fork
  (10M live blocks: 15 ms). The cost is copy-on-write memory while the program rewrites pages.

## What was rejected

- **Stream every event to a second process** (heaptrack's way). Measured on an 8-thread malloc
  loop: 1.65 s against 0.13 s for heaptide, and 62 MB against 9 MB of added memory.
- **`tracemalloc` for Python.** It was used until v0.1.5: 30 s and 3.86 GB on the Python
  benchmark, against 2.9 s and 849 MB with CPython's allocator hooks.
- **Signal every thread for a snapshot.** A signal ends a `nanosleep` or `poll` early, so a thread
  asleep in a system call is scanned from `/proc`. Its saved registers are not read: a block held
  only there can show as leaked in a snapshot, never at exit.
- **Scan GPU blocks.** The HIP runtime's own tables point at every one, so GPU and pinned host
  blocks are never scanned: unfreed at exit means leaked.
- **Pooled GPU allocators.** A pool hides each buffer in one big block. `--gpu` turns Mojo's and
  PyTorch's pools off, so peak figures under `--gpu` are not production figures.
- **Line numbers in `diff` keys.** Sites match without them, so moved code is not a change. Without
  `llvm-symbolizer`, `diff` is valid only between identical binaries.
- **A relative-only GROWTH rule.** It passes a 12 GB process that rose 527 MiB. `--growth-limit`
  sets an absolute bound, and the window moves later to skip a long setup.
