# CLI reference

heaptide is a command line tool. `./heaptide` is one bash launcher with seven subcommands. Run it
from a clone after `./build.sh`, or from the release tarball. With no subcommand, or an unknown
one, it prints the usage line and exits 2.

Every error prints `FAIL heaptide: <reason>` (or `FAIL report: <reason>`) on stderr and exits 2. A
missing option value, a bad value and an unknown option are all exit 2. None falls back to a
default.

| Subcommand | Use |
|---|---|
| [`run`](#run) | trace a command, write one file per process |
| [`report`](#report) | read a run directory: text, JSON or folded stacks |
| [`snapshot`](#snapshot) | make every traced process write its report now |
| [`diff`](#diff) | compare two run directories site by site |
| [`attach`](#attach) | start tracing a running process |
| [`detach`](#detach) | stop tracing it, no restart |
| [`flame`](#flame) | write an interactive flame graph |

A run directory (`DIR`, from `--out`) holds `heaptide.<pid>.bin` for each traced process and `root`
(the pid of the first process). With `--py` it also holds `py.<pid>.txt` and `pyheld.<pid>.txt`.
See [file-format.md](file-format.md).

## run

```
heaptide run [--gpu] [--py] [--py-depth N] [--every MS] [--snapshot-every S] [--gpu-timeline PARTS]
             [--no-children | --only NAME[,NAME]] [--out DIR] -- CMD...
```

Run `CMD` with the shim preloaded. At exit the shim writes `DIR/heaptide.<pid>.bin` for each
traced process.

| Flag | Meaning |
|---|---|
| `--gpu` | turn off Mojo's and PyTorch's pooling allocators, so each GPU buffer is its own block |
| `--py` | trace Python allocations by line. `CMD` must start with `python`. Writes `py.<pid>.txt` |
| `--py-depth N` | keep N Python frames per site (default 1, maximum 8) |
| `--every MS` | GROWTH sampling period in ms (default 100) |
| `--snapshot-every S` | write a full report every S seconds |
| `--gpu-timeline PARTS` | `all`, or a comma list of `sites`, `streams`, `frag`: VRAM per site over the run |
| `--no-children` | trace the command alone |
| `--only NAME[,NAME]` | trace only processes with these names (argv[0] basename) |
| `--out DIR` | output directory (default `.work/heaptide`). Earlier heaptide files in it are removed first; other files stay |

`--py-depth`, `--every` and `--snapshot-every` take a number. A flag that needs a value and gets
none, or gets another flag, is exit 2.

- Exit code: the exit code of `CMD`. Tool errors (bad flag, no command, `--py` without a python
  command) are exit 2, which a `CMD` that exits 2 also gives. Read stderr to tell them apart.
- Output: `DIR/heaptide.<pid>.bin`, `DIR/root`, and with `--py` `DIR/py.<pid>.txt`. A process
  that ended without a report (SIGKILL, OOM killer, `_exit`) gets its `.bin` written afterwards
  from `/dev/shm`, with no leak scan.
- stderr: one `heaptide: pid=... direct=... indirect=...` line per process, then
  `heaptide: report with: heaptide report DIR`. A statically linked ASan program gets a warning.

## report

```
heaptide report DIR [--json] [--top N] [--supp FILE] [--no-default-supp]
                    [--fail-on any|leaks|growth|none] [--growth-limit MIB]
                    [--folded leaked|live|peak|allocated|temporaries]
```

Print the report for every process in `DIR`: LEAKS, GROWTH, PEAK, HOTSPOTS, TEMPORARIES, and
PYTHON when present. Small helper processes fold into one QUIET line. If `DIR` holds the tables of
a killed process, `report` writes its `.bin` first.

| Flag | Meaning |
|---|---|
| `--json` | one JSON object per process, in an array. Fields: [json.md](../skills/heaptide/references/json.md) |
| `--top N` | rows per section (default 10, at least 1) |
| `--supp FILE` | drop leaks whose site contains any line of FILE (`#` starts a comment) |
| `--no-default-supp` | also list the ROCm runtime's one-time allocations that `report/default.supp` drops |
| `--fail-on W` | what sets exit 1: `any` (default), `leaks`, `growth`, `none` |
| `--growth-limit MIB` | fail GROWTH on a projected rise above MIB, whatever the mean (MIB > 0) |
| `--folded M` | print `frame;frame;... bytes` lines for one metric, for speedscope, `flamegraph.pl` or inferno |

- Exit code: 0 clean, 1 a leak or growth as `--fail-on` says, 2 tool error (no `.bin`, damaged
  `.bin`, bad option). `--folded` always exits 0.
- Output: text or JSON on stdout. No files, except the recovered `.bin` described above.
- For file:line it needs `llvm-symbolizer`: `$HEAPTIDE_SYMBOLIZER`, then `PATH`, then ROCm's.
  Without one, sites show `[module+offset]`.

## snapshot

```
heaptide snapshot DIR [--label NAME]
```

Make every traced process write its report now. It returns once the root's report is newer than
the request. `NAME` (letters, digits, `.`, `_`, `-`) keeps this state in `DIR/NAME` as hard links.

- Exit code: 0 written, 1 no report within 60 s, 2 usage (no `DIR`, or a bad `NAME`).
- Output: refreshed `DIR/heaptide.<pid>.bin`, and `DIR/NAME/` with `--label`.

## diff

```
heaptide diff BASE NEW [--fail-on new|grown|none] [--json] [--top N]
```

Compare two run directories site by site. Sites match by function chain, without line numbers,
so moved code is not a change.

- `NEW`: a leak site only `NEW` has. `GROWN`: direct or peak bytes up by more than 64 KiB and
  10%. `GONE` and `SHRUNK` are the reverse and never fail.
- `--fail-on new` (default): exit 1 on NEW. `grown`: exit 1 on NEW or GROWN. `none`: always 0.
- `--top N`: how many peak sites each side shows. Every leak is always compared.
- Exit code: 0 no failure, 1 as `--fail-on` says, 2 tool error (not two directories, bad option).
- Output: text (or JSON) on stdout. No files.

## attach

```
heaptide attach PID [--out DIR]
```

Load heaptide into a running process through gdb (`dlopen`). It sees only what the process
allocates after the attach. `DIR` defaults to `.work/heaptide`.

- Needs `gdb`, and `sudo` under Yama `ptrace_scope` 1 (or run it as the process's parent).
- Exit code: 0 attached, 2 usage, heaptide already loaded in `PID`, or gdb could not attach.
- Output: creates `DIR`. Reports appear on `snapshot`, or when the process exits.
- GROWTH reads `attached`: compare two snapshots with `diff`. The report line `before attach:`
  says how many bytes it cannot see.

## detach

```
heaptide detach DIR
```

Take a last snapshot, then let the process run on untracked. The library stays loaded and inert,
so the same process cannot be attached again.

- Exit code: 0 detached, 1 the snapshot failed or the detach did not finish within 10 s, 2 `DIR`
  is not a directory.
- Output: refreshed `DIR/heaptide.<pid>.bin`. No report is written at the process's exit.

## flame

```
heaptide flame DIR [-o OUT.html] [--open]
```

Write every call path as one offline HTML flame graph.

| Flag | Meaning |
|---|---|
| `-o OUT.html` | output file (default `DIR/flame.html`) |
| `--open` | open the file with `xdg-open` |

- Exit code: 0 written, 2 usage or no report data.
- Output: `OUT.html`, one self-contained page. stderr names the file and its size.

## Environment

| Variable | Read by | Meaning |
|---|---|---|
| `MOJO` | `build.sh` | the `mojo` that builds the report (`./.venv` wins over `PATH`) |
| `HEAPTIDE_SYMBOLIZER` | `report` | the `llvm-symbolizer` to use |
| `HEAPTIDE_DEFAULT_SUPP` | `report` | the default suppression list (the launcher sets `report/default.supp`) |
| `HEAPTIDE_DEPTH` | `run` | native stack depth (default 64; 8 under `--py`) |
| `HEAPTIDE_PY_MEM` | `run --py` | cap of the live Python table in MiB (default 1/8 of memory at start) |

`run` sets the other `HEAPTIDE_*` variables from its flags. Do not set them by hand.
