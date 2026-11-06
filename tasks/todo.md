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

## Deferred from v2.0.0

- [ ] `--update --components=hooks,rules` selective component updates
- [ ] `--max-depth N` for scan depth control
- [ ] `--force` flag (requires audit trail before overwriting user edits)
- [ ] Component-level options in `--adopt`
- [ ] `--json` machine-readable output for scripting
- [ ] `mkproj --init` alias for the default bootstrap mode
- [ ] Windows native support (WSL2 recommended in the interim)
- [ ] `mkproj --diff NAME` -- show pending changes without updating

## Validation

182 input/boundary/no-side-effect checks and 27 Linux regression tests pass.
The regression suite includes the isolated full scaffold test, forced private
staging, private history later deleted, push failure, backup failure, launcher
failure, collision/ref preservation, archive collisions, and venv switching.
Bash syntax and git diff whitespace checks pass. Publication is verified by
comparing the final commit with each configured origin push destination.
