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
