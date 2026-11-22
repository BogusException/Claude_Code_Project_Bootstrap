# PB governance: third-party isolation

## Core principle

Project-bootstrap (PB) and all projects it creates are self-contained.
No PB hook, script, or test may depend on a third-party plugin, MCP server,
skill, or external service to function correctly. If an external tool
misbehaves, PB keeps working.

## Hook contracts

Every hook that PB installs or references must satisfy all of these:

- **Self-contained**: uses only system binaries (bash, python3, git, jq).
  No calls to plugin-managed processes, Node services, or external APIs.
- **Explicit timeout**: every hook entry in settings.json has a `timeout`
  field. The `mkproj --test` suite fails if any hook is missing one.
- **Fast exit on non-critical failure**: hooks that fail must exit non-zero
  within their timeout. They must not hang waiting for external services.
- **No side effects on other tools**: PB hooks do not write to other
  tools' state directories, modify global plugin config, or call any
  binary that another tool owns.

## What PB is not responsible for

PB cannot and does not:

- Fix bugs in third-party plugins or global hooks.
- Test its hooks against every plugin combination a user might have installed.
- Compensate for external hooks that hang, fail, or corrupt state.

If a global or plugin hook interferes with PB's operation, the fix belongs
in that tool or in the user's global settings (timeout added, hook disabled,
plugin updated). PB documents the symptoms and the fix location -- it does
not absorb the problem.

## When extending PB or mkproj

Before adding any new hook or phase:

1. Verify it has zero external dependencies.
2. Set an explicit timeout in settings.json.
3. Add a test case to `--test` that runs the hook with a 5-second hard
   timeout and verifies it exits 0.
4. Document any new side effect in this file.

If a proposed extension requires calling a third-party service or binary:

- Isolate it behind a capability flag (`--with-X`), off by default.
- Guard it with an existence check (`command -v X || exit 0`).
- Document the external dependency explicitly in CLAUDE.md and here.

## Hook health monitoring

`mkproj --test` runs every project-level hook with a 5-second hard timeout.
If any hook exceeds 5 seconds, the test fails and the hook must be fixed
before release. This prevents slow or hanging hooks from shipping to the
97-project fleet via `mkproj --scan`.

## On watchdog processes

Claude Code's `timeout` field in settings.json is the watchdog for hooks.
Every hook has an explicit timeout; Claude Code enforces it. No separate
watchdog agent is needed as long as timeout fields are present and correct.

If Claude Code's timeout enforcement is itself unreliable in a future
version, the mitigation is to wrap hook commands with the system `timeout`
binary at the command level:

    "command": "timeout 10 /path/to/hook.sh"

This provides a second enforcement layer independent of Claude Code.

## Incident log

| Date       | Symptom                        | Root cause                            | Fix                                |
|------------|-------------------------------|---------------------------------------|------------------------------------|
| 2026-11-22 | 6-min turn, 20-min cogitation | `mempalace hook run` had no timeout   | Added timeout=3 in global settings |
| 2026-11-22 | ValueError, 20-min cogitation | save-response.sh 64KB tail missed query | Backward JSONL scan, sys.exit(0) fallback |
| 2026-11-22 | Tests failing exit 126        | bootstrap.sh missing execute bit      | chmod +x, committed                |
