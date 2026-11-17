#!/usr/bin/env bash
# llvm-symbolizer stand-in for heaptide report when LLVM is missing: GNU addr2line (binutils), one call per module.
# stdin: llvm-symbolizer requests ("MOD" 0xADDR | DATA "MOD" 0xADDR); stdout: its answers, same order
# (func / file:line:0 per inlined frame, a blank line after each; DATA answers "??" / "0 0"). Arguments are ignored.
set -euo pipefail
command -v addr2line > /dev/null || { echo "FAIL addr2sym: no addr2line (install binutils)" >&2; exit 3; }
T=$(mktemp -d "${TMPDIR:-/tmp}/addr2sym.XXXXXX"); trap 'rm -rf "$T"' EXIT
T=$T awk -F'"' '
  $1 ~ /DATA/ { data[++n] = 1; next }
  NF >= 3 { m = $2; a = $3; gsub(/ /, "", a); n++
    if (!(m in id)) { id[m] = ++k; mod[k] = m }
    print a > (ENVIRON["T"] "/" id[m]); ids[id[m]] = ids[id[m]] " " n }
  END {
    for (j = 1; j <= k; j++) {
      f = ENVIRON["T"] "/" j; close(f); split(ids[j], q, " "); c = 0
      gsub(/\047/, "\047\\\047\047", mod[j])
      cmd = "addr2line -Cfia -e \047" mod[j] "\047 < \047" f "\047"
      while ((cmd | getline l) > 0) {
        if (l ~ /^0x[0-9a-f]+$/) { cur = q[++c]; fn = ""; continue }
        if (fn == "") { fn = l; continue }
        sub(/ \(discriminator [0-9]+\)$/, "", l); sub(/:\?$/, ":0", l)
        out[cur] = out[cur] fn "\n" l ":0\n"; fn = ""
      }
      close(cmd)
    }
    for (i = 1; i <= n; i++) printf "%s\n", data[i] ? "??\n0 0\n" : (i in out ? out[i] : "??\n??:0\n")
  }'
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 AMARBARO · amarbaro.org labs
