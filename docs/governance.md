# PB governance: third-party isolation

## Core principle

Project-bootstrap (PB) and all projects it creates are self-contained.
No PB hook, script, or test may depend on a third-party plugin, MCP server,
skill, or external service to function correctly.

PB does not maintain compatibility with third-party software. PB does not
patch third-party bugs. PB does not absorb problems that originate outside
its own codebase. That work belongs to the third-party maintainer or to the
user who chose to install the external software.

The supported configuration for `mkproj --test` is PB's own hooks only.
Behavior in the presence of third-party global hooks is not tested and
not guaranteed.

## Hook contracts

Every hook that PB installs must satisfy all of these:

- **Self-contained**: uses only system binaries (bash, python3, git, jq).
  No calls to plugin-managed processes, Node services, or external APIs.
- **Explicit timeout**: every hook entry in settings.json has a `timeout`
  field. The `mkproj --test` suite fails if any hook is missing one.
- **Fast exit on non-critical failure**: hooks that fail must exit non-zero
  within their timeout. They must not hang waiting for external services.
- **No side effects on other tools**: PB hooks do not write to other
  tools' state directories or modify global plugin config.

## Responsibility boundary

| Situation | Owner |
|-----------|-------|
| PB hook fails or hangs | PB maintainer |
| Third-party plugin hook fails or hangs | Plugin maintainer or user |
| Third-party hook interferes with PB's hooks | User (add timeout, disable, update plugin) |
| Malicious plugin installed by user | User |

PB documents its own hook contracts. It does not document workarounds
for third-party tools, and it does not maintain a compatibility list.
Any such list would be obsolete by the next release of anything on it.

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
before release.

## On watchdog processes

Claude Code's `timeout` field in settings.json is the watchdog for hooks.
If Claude Code's timeout enforcement is itself unreliable in a future
version, wrap hook commands with the system `timeout` binary:

    "command": "timeout 10 /path/to/hook.sh"

This provides a second enforcement layer independent of Claude Code.
