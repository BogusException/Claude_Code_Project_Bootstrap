# Keybindings

## 1. What mkproj installs

`mkproj` copies `templates/global/keybindings.json` to `~/.claude/keybindings.json` during phase 7 (global setup). The installed bindings:

| Key | Context | Action |
|-----|---------|--------|
| `Enter` | Chat | Insert newline (default overridden) |
| `Alt+S` | Chat | Submit |
| `Ctrl+X S` (chord) | Chat | Submit |

`Enter` is rebound to newline so that accidental presses don't fire off incomplete prompts. Submit requires an intentional key combination.

## 2. Terminal compatibility notes

The submit bindings were chosen specifically for PuTTY and MobaXterm, which cannot send `Ctrl+Enter` to terminal applications.

**Alt+S** works reliably in PuTTY. In MobaXterm, `Alt+S` and `Alt+J` are both silently ignored by Claude Code (root cause unknown). `Alt+G` is reserved by a Windows Gemini hotkey and is not usable.

**Ctrl+X S** (chord: press `Ctrl+X`, release, then `S`) works in both PuTTY and MobaXterm and serves as a fallback when `Alt+S` is unavailable.

## 3. Update policy

mkproj tracks the SHA-256 of the installed template in `~/.claude/keybindings.json.last-installed-hash`. On each run:

- If `~/.claude/keybindings.json` is absent, it is installed and the hash is recorded.
- If the file is present and the sidecar hash matches the current template, the file is left alone (hand edits are preserved).
- If the template has changed since the last install, the existing file is backed up to `~/.claude/backups/` with a timestamp before being replaced.
- If the file is present but no sidecar exists (pre-dating this feature), the current template hash is recorded and the file is left untouched. The comparison takes effect on the next template update.

## 4. Customizing

Edit `templates/global/keybindings.json` in this repository. The next `mkproj` run will detect the template change and update any installation that was laid down by mkproj. Files that were hand-edited after a mkproj install will be backed up before replacement.

To add bindings without touching the template, edit `~/.claude/keybindings.json` directly. mkproj will not overwrite it as long as the template itself does not change.
