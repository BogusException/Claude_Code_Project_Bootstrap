# Release checklist

Run through this before calling `release.sh`.

## Pre-flight

- [ ] All tasks in `tasks/todo.md` for this version are checked off
- [ ] `MKPROJ_VERSION` in `bootstrap.sh` matches the intended release version
- [ ] `CHANGELOG.md` has a `## [VERSION] - DATE` section with accurate notes
- [ ] No uncommitted changes (`git status` is clean except untracked private files)
- [ ] The tag does not already exist (`git tag | grep vVERSION`)

## Tests

- [ ] `mkproj --test` passes all phases
- [ ] Bash syntax check: `bash -n bootstrap.sh && bash -n lib/*.sh`
- [ ] Full test count matches or exceeds the baseline in `tasks/todo.md`

## Release

Run: `bash release.sh`

The script will:
1. Read `MKPROJ_VERSION` from `bootstrap.sh`
2. Confirm the tag does not exist
3. Run `mkproj --test`
4. Compute CRC32 of `bootstrap.sh` and stamp it into `CHANGELOG.md`
5. Commit all pending changes: `Release vVERSION`
6. Push to all remotes
7. Create the GitHub release via `gh release create`
