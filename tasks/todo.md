# Linux reliability fixes

- [x] Audit ignore files, Git configuration, native hooks, and bootstrap side effects.
- [x] Align repository/template privacy rules; untrack the empty response placeholder.
- [x] Add native private-path guards and staged-only auto-commit behavior.
- [x] Isolate test mode; add read-only dry-run and diagnostic controls.
- [x] Refuse repo collisions, dirty/live repos, and conflicting hooks/remotes.
- [x] Complete backup coverage and project venv checks; fix managed environment switching.
- [x] Offer Claude, Codex, or no launch without changing status settings.
- [x] Run negative and failure-injection integration tests.
- [x] Update documentation and prepare the reviewed commit.

## Validation

182 input/boundary/no-side-effect checks and 27 Linux regression tests pass.
The regression suite includes the isolated full scaffold test, forced private
staging, private history later deleted, push failure, backup failure, launcher
failure, collision/ref preservation, archive collisions, and venv switching.
Bash syntax and git diff whitespace checks pass. Publication is verified by
comparing the final commit with each configured origin push destination.
