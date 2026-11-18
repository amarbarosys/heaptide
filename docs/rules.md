# Rules

Each rule comes from a mistake: what broke -> rule.

- Counting `/proc/self/maps` lines hid a 192 MB mapping leak (7 vs 4 lines; the kernel merges adjacent
  anonymous maps) -> measure address-space growth with `VmSize` from `/proc/self/status`, and run the
  test on the old build first so it is seen to fail.
- A new test file had no copyright header; the pre-push hook refused it after the release was tagged ->
  run `tools/publish-check.sh` before `release-note tag`, and copy the first two lines of a sibling file.
- A push line was handed over as `git push`: `publish` tracks `origin/main`, and the hook needs
  `PUBLISH_OK=1` -> before writing a push line, read `git status -sb` and `.githooks/pre-push`; write
  `PUBLISH_OK=1 git push origin HEAD:main` and `PUBLISH_OK=1 git push origin vX.Y.Z`.
- A Brain note path was built as `~/Brain/$(brain-repo-dir ...)` and failed: that tool prints an absolute
  path -> use its output as it is, or write to `~/Brain/tools/heaptide/`.
- `cat >` rewrote `.githooks/pre-push` while a push was running it; bash reads a script by byte offset
  -> change a script that may be running by writing a copy and `mv` over it (new inode).
- A suite test hung for 19 minutes with 8 spinning threads and no test timeout -> every `run()` has
  `TEST_TIMEOUT` (60 s) and the hook caps the suite at 20 minutes.
- A stress run used a guessed `--no-report` flag and exited 2 in 0 s -> read `./heaptide run --help` first.
- A failed `git commit` left files staged, and the next handed-over commit swept them in (hook and
  release note in one commit) -> after a failed commit, `git reset -q` before handing over a commit line,
  and hand over `git add P && git commit P` with the same paths (`git commit P` alone rejects a new file).
