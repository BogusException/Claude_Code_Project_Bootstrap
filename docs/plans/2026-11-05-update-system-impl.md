# mkproj v2 Update System -- Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use godmode:task-runner to implement this plan task-by-task.

**Goal:** Add `.mkproj` identity tracking, safe update/scan/adopt modes, man-page help, opt-in keybindings, and `--version` to mkproj.

**Architecture:** A `.mkproj` JSON file in each project tracks every template-derived file with two hashes: `template_hash` (hash of the source template at install time) and `installed_hash` (hash of what was actually written to disk, which differs from template_hash for files with `{{PROJECT_NAME}}` substitution). A new `lib/registry.sh` manages reading/writing this file. A new `lib/update.sh` implements the update/scan/adopt/status/pending modes. `bootstrap.sh` gains a `MKPROJ_VERSION` constant and routes the new modes. Phase 8 writes `.mkproj` after the initial commit.

**Tech stack:** bash 5+, jq (existing prerequisite), sha256sum, diff (standard), less (for paged help)

**Files created:** `lib/registry.sh`, `lib/update.sh`, `docs/plans/2026-11-05-update-system-impl.md`

**Files modified:** `bootstrap.sh`, `lib/input.sh`, `templates/.gitignore`, `README.md`, `tasks/todo.md`, `docs/doc-index.md`, `docs/usage.md`

---

## Task 1: MKPROJ_VERSION constant and keybindings opt-in flag

**Purpose:** Add a semver constant and gate keybindings install on an explicit `--keybindings` flag.

**Files:**
- Modify: `bootstrap.sh` (top section, phase7_global)
- Modify: `lib/input.sh` (parse_args)

**Step 1: Add MKPROJ_VERSION to bootstrap.sh**

After the `TEMPLATES_DIR=...` line (around line 7), add:

```bash
MKPROJ_VERSION="2.0.0"
INSTALL_KEYBINDINGS=false
```

**Step 2: Add `--keybindings` to parse_args in lib/input.sh**

Add to the `case "$arg"` block before the `-*)` catch-all:

```bash
--keybindings)
    INSTALL_KEYBINDINGS=true ;;
```

Also add `INSTALL_KEYBINDINGS=false` to the defaults at the top of `parse_args`.

**Step 3: Gate phase7_global keybindings on INSTALL_KEYBINDINGS**

In `phase7_global`, wrap the entire keybindings block with:

```bash
if [[ "$INSTALL_KEYBINDINGS" == true ]]; then
    # ... existing kb_src/kb_dst/kb_hash_file block ...
fi
```

**Step 4: Add `--version` mode to parse_args**

Add `--version` to the mode-seen block alongside `--help`:

```bash
--version) MODE=version ;;
```

**Step 5: Handle MODE=version in main()**

In `main()`, after the lock setup, add early exit:

```bash
if [[ "$MODE" == version ]]; then
    printf 'mkproj %s\n' "$MKPROJ_VERSION"; exit 0
fi
```

**Step 6: Run existing tests**

```bash
mkproj --test
```
Expected: all tests pass, no regressions.

**Step 7: Verify --version and --keybindings**

```bash
mkproj --version
# Expected: mkproj 2.0.0

mkproj --keybindings --help
# Expected: help output, no error
```

**Step 8: Commit**

```bash
git add bootstrap.sh lib/input.sh
git commit -m "feat: add MKPROJ_VERSION 2.0.0, --version flag, keybindings opt-in"
```

---

## Task 2: Add .mkproj to gitignore template and usage docs

**Purpose:** Ensure `.mkproj` is excluded from new project git history.

**Files:**
- Modify: `templates/.gitignore`
- Modify: `docs/usage.md` (note new flag)

**Step 1: Read templates/.gitignore**

```bash
cat templates/.gitignore
```

**Step 2: Add .mkproj line**

Add `.mkproj` to the "tooling" or "bootstrap" section of `templates/.gitignore`.

**Step 3: Run tests**

```bash
mkproj --test
```
Expected: test project's .gitignore contains `.mkproj`.

**Step 4: Commit**

```bash
git add templates/.gitignore
git commit -m "feat: add .mkproj to project gitignore template"
```

---

## Task 3: Create lib/registry.sh

**Purpose:** All `.mkproj` read/write logic lives here. No other file manipulates `.mkproj` directly.

**Files:**
- Create: `lib/registry.sh`
- Modify: `bootstrap.sh` (add `source "$BOOTSTRAP_DIR/lib/registry.sh"`)

**Step 1: Create lib/registry.sh with these functions**

```bash
#!/usr/bin/env bash
# registry.sh — manage .mkproj identity files

MKPROJ_FILE=".mkproj"

# registry_path PROJECT_DIR
# Echoes the absolute path to the .mkproj file.
registry_path() { printf '%s/%s\n' "$1" "$MKPROJ_FILE"; }

# registry_exists PROJECT_DIR
# Returns 0 if .mkproj exists and is valid JSON, 1 otherwise.
registry_exists() {
    local f; f="$(registry_path "$1")"
    [[ -f "$f" ]] && jq empty "$f" 2>/dev/null
}

# registry_read PROJECT_DIR KEY
# Echoes the value at .KEY from .mkproj (jq path expression).
registry_read() { jq -r "$2" "$(registry_path "$1")"; }

# registry_create PROJECT_DIR MKPROJ_VERSION COMPONENTS_JSON
# Writes a fresh .mkproj with no file entries.
registry_create() {
    local project_dir="$1" version="$2" components="$3"
    local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    jq -n \
        --arg v "$version" \
        --arg t "$now" \
        --argjson c "$components" \
        '{format:1, mkproj_version:$v, installed_at:$t, updated_at:$t,
          files:{}, components:$c}' \
        > "$(registry_path "$project_dir")"
}

# registry_set_file PROJECT_DIR REL_PATH TEMPLATE_HASH INSTALLED_HASH STATUS
# Upserts a file entry. STATUS: installed|deferred|skipped
registry_set_file() {
    local project_dir="$1" rel="$2" th="$3" ih="$4" st="$5"
    local f; f="$(registry_path "$project_dir")"
    local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    local tmp; tmp="$(mktemp "$(dirname "$f")/.mkproj.XXXXXXXX")"
    jq --arg p "$rel" --arg th "$th" --arg ih "$ih" --arg st "$st" --arg t "$now" \
        '.files[$p] = {template_hash:$th, installed_hash:$ih, status:$st}
         | .updated_at = $t' "$f" > "$tmp"
    mv -T -- "$tmp" "$f"
}

# registry_touch_updated PROJECT_DIR
# Updates .updated_at to now.
registry_touch_updated() {
    local f; f="$(registry_path "$1")"
    local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    local tmp; tmp="$(mktemp "$(dirname "$f")/.mkproj.XXXXXXXX")"
    jq --arg t "$now" '.updated_at = $t' "$f" > "$tmp"
    mv -T -- "$tmp" "$f"
}

# registry_file_status PROJECT_DIR REL_PATH
# Echoes status string or "unknown" if not tracked.
registry_file_status() {
    jq -r --arg p "$2" '.files[$p].status // "unknown"' "$(registry_path "$1")"
}

# registry_file_hashes PROJECT_DIR REL_PATH
# Echoes "TEMPLATE_HASH INSTALLED_HASH" space-separated.
registry_file_hashes() {
    jq -r --arg p "$2" '
        (.files[$p].template_hash // "")
        + " " +
        (.files[$p].installed_hash // "")
    ' "$(registry_path "$1")"
}

# registry_all_files PROJECT_DIR
# Echoes each tracked relative path, one per line.
registry_all_files() {
    jq -r '.files | keys[]' "$(registry_path "$1")"
}

# registry_stamp_from_disk PROJECT_DIR
# Creates .mkproj by computing hashes from files currently on disk.
# Used for retroactive stamping of existing projects.
registry_stamp_from_disk() {
    local project_dir="$1"
    registry_create "$project_dir" "$MKPROJ_VERSION" '["adopted"]'
    local rel tpl_path tpl_hash disk_hash
    while IFS= read -r -d '' tpl_file; do
        rel="$(template_to_project_path "$tpl_file")"
        [[ -n "$rel" ]] || continue
        [[ -f "$project_dir/$rel" ]] || continue
        tpl_path="$tpl_file"
        tpl_hash="$(sha256sum "$tpl_path" | cut -d' ' -f1)"
        disk_hash="$(sha256sum "$project_dir/$rel" | cut -d' ' -f1)"
        registry_set_file "$project_dir" "$rel" "$tpl_hash" "$disk_hash" "installed"
    done < <(find "$TEMPLATES_DIR" -type f \( \
        ! -path "*/backups/*" ! -name "*.bak" \
        \) -print0)
}
```

**Step 2: Add source line to bootstrap.sh**

After `source "$BOOTSTRAP_DIR/lib/runtime.sh"`, add:
```bash
source "$BOOTSTRAP_DIR/lib/registry.sh"
```

**Step 3: Add template_to_project_path helper to registry.sh**

This function maps a template absolute path to the project-relative path:

```bash
# template_to_project_path TEMPLATE_ABSOLUTE_PATH
# Echoes the project-relative path, or empty string if not mappable.
template_to_project_path() {
    local abs="$1"
    local rel="${abs#"$TEMPLATES_DIR/"}"
    # hooks/ -> .claude/hooks/
    # rules/ -> .claude/rules/
    # git-hooks/ -> .git/hooks/
    case "$rel" in
        hooks/*)     printf '.claude/%s\n' "$rel" ;;
        rules/*)     printf '.claude/%s\n' "$rel" ;;
        git-hooks/*) printf '.git/hooks/%s\n' "${rel#git-hooks/}" ;;
        docs/*)      printf '%s\n' "$rel" ;;
        tasks/*)     printf '%s\n' "$rel" ;;
        backups/*)   ;;  # skip
        *.bak)       ;;  # skip
        *)           printf '%s\n' "$rel" ;;
    esac
}
```

**Step 4: Verify registry.sh is syntactically valid**

```bash
bash -n lib/registry.sh && echo "ok"
```
Expected: `ok`

**Step 5: Commit**

```bash
git add lib/registry.sh bootstrap.sh
git commit -m "feat: add lib/registry.sh for .mkproj file management"
```

---

## Task 4: Write .mkproj on initial bootstrap (phase 8)

**Purpose:** Every new project created by mkproj gets a `.mkproj` after the first commit.

**Files:**
- Modify: `bootstrap.sh` (phase8_commit, track file helper)

**Step 1: Add registry write to phase8_commit**

After the `git commit` in `phase8_commit`, add:

```bash
write_registry_initial() {
    local components='["core","venv","docs","tasks","hooks","rules","settings"]'
    registry_create "$PROJECT_DIR" "$MKPROJ_VERSION" "$components"
    local tpl_file rel tpl_hash disk_hash
    while IFS= read -r -d '' tpl_file; do
        rel="$(template_to_project_path "$tpl_file")"
        [[ -n "$rel" ]] || continue
        [[ -f "$PROJECT_DIR/$rel" ]] || continue
        tpl_hash="$(sha256sum "$tpl_file" | cut -d' ' -f1)"
        disk_hash="$(sha256sum "$PROJECT_DIR/$rel" | cut -d' ' -f1)"
        registry_set_file "$PROJECT_DIR" "$rel" "$tpl_hash" "$disk_hash" "installed"
    done < <(find "$TEMPLATES_DIR" -type f \( \
        ! -path "*/backups/*" ! -name "*.bak" \
        \) -print0)
    # settings.json is generated (no template file), hash the generated output
    if [[ -f "$PROJECT_DIR/.claude/settings.json" ]]; then
        local gen_hash disk_hash
        gen_hash="$(generate_settings_json | sha256sum | cut -d' ' -f1)"
        disk_hash="$(sha256sum "$PROJECT_DIR/.claude/settings.json" | cut -d' ' -f1)"
        registry_set_file "$PROJECT_DIR" ".claude/settings.json" "$gen_hash" "$disk_hash" "installed"
    fi
    # keybindings.json is global, not tracked per-project
    log "  wrote .mkproj"
}
```

Call `write_registry_initial` inside `phase8_commit` after the commit, before the push:

```bash
write_registry_initial
```

`.mkproj` is not git-committed (it's gitignored). No `git add` needed.

**Step 2: Add .mkproj to verify check in phase9_verify**

After the existing `jq empty "$PROJECT_DIR/.claude/settings.json"` check, add:

```bash
registry_exists "$PROJECT_DIR" || { err ".mkproj file is missing or invalid JSON"; return 1; }
local reg_ver; reg_ver="$(registry_read "$PROJECT_DIR" '.mkproj_version')"
[[ "$reg_ver" == "$MKPROJ_VERSION" ]] || { err ".mkproj version mismatch: got $reg_ver, expected $MKPROJ_VERSION"; return 1; }
```

**Step 3: Run tests**

```bash
mkproj --test
```
Expected: all tests pass including new .mkproj check.

**Step 4: Commit**

```bash
git add bootstrap.sh
git commit -m "feat: write .mkproj registry file on initial project bootstrap"
```

---

## Task 5: CLI expansion -- new modes and flags in lib/input.sh

**Purpose:** Parse all new flags: `--update`, `--scan`, `--status`, `--pending`, `--adopt`, `--yes`/`-y`, `--quiet`/`-q`, `--verbose`/`-v`, `--keybindings` (from Task 1), `--version` (from Task 1).

**Files:**
- Modify: `lib/input.sh`

**Step 1: Add new defaults at top of parse_args**

```bash
SCAN_DIR=""
YES_MODE=false
QUIET=false
VERBOSE=false
```

**Step 2: Add new modes to the case block**

```bash
--update)   MODE=update ;;
--scan)     MODE=scan ;;
--status)   MODE=status ;;
--pending)  MODE=pending ;;
--adopt)    MODE=adopt ;;
--yes|-y)   YES_MODE=true ;;
--quiet|-q) QUIET=true ;;
--verbose|-v) VERBOSE=true ;;
```

For `--scan`, `--status`, `--pending`: the optional argument that follows is a directory, not a project name. Add a secondary pass: if `HAS_PROJECT_ARG == true` and `MODE` is one of those, treat the arg as `SCAN_DIR` instead.

**Step 3: Add validation rules**

After the loop, add:
```bash
# scan/status/pending accept a dir arg, not a project name
if [[ "$MODE" == scan || "$MODE" == status || "$MODE" == pending ]]; then
    if [[ "$HAS_PROJECT_ARG" == true ]]; then
        SCAN_DIR="$PROJECT_ARG"
        HAS_PROJECT_ARG=false
        PROJECT_ARG=""
    fi
    [[ -z "$SCAN_DIR" ]] && SCAN_DIR="$PWD"
fi
```

**Step 4: Run existing tests**

```bash
mkproj --test
```
Expected: all pass.

**Step 5: Verify new flags parse without error**

```bash
bash -n lib/input.sh && echo "ok"
source lib/input.sh
parse_args --scan /tmp && echo "MODE=$MODE SCAN_DIR=$SCAN_DIR"
# Expected: MODE=scan SCAN_DIR=/tmp
parse_args --update && echo "MODE=$MODE"
# Expected: MODE=update
parse_args --yes --verbose && echo "YES=$YES_MODE VERBOSE=$VERBOSE"
# Expected: YES=true VERBOSE=true
```

**Step 6: Commit**

```bash
git add lib/input.sh
git commit -m "feat: expand CLI with --update, --scan, --status, --pending, --adopt, -y, -q, -v"
```

---

## Task 6: Man-page style --help

**Purpose:** Replace the existing short usage() with a man-page formatted output paged through `less` on a TTY.

**Files:**
- Modify: `bootstrap.sh` (usage function and MODE=help handler)

**Step 1: Rewrite usage() in bootstrap.sh**

Replace the existing `usage()` function with:

```bash
usage() {
    local pager=""
    [[ -t 1 ]] && command -v less >/dev/null && pager="less -F"
    _usage_text | ${pager:-cat}
}
_usage_text() {
cat <<'MANPAGE'
NAME
       mkproj - bootstrap and maintain Claude Code Python projects

SYNOPSIS
       mkproj [--no-global] [--agent=claude|codex|none] [--keybindings] [NAME]
       mkproj --update [NAME]
       mkproj --scan [DIR]
       mkproj --status [DIR]
       mkproj --pending [DIR]
       mkproj --adopt [NAME]
       mkproj --dry-run [--no-global] [--agent=claude|codex|none] [NAME]
       mkproj --doctor [NAME]
       mkproj --test
       mkproj --version
       mkproj --help

DESCRIPTION
       mkproj bootstraps a complete Claude Code Python project from an empty
       directory and maintains it over time. On first run it creates a git
       repository, Python virtual environment, CLAUDE.md, AGENTS.md, hook
       scripts, permission rules, and project structure. It records every
       installed file in a .mkproj marker so future runs can update them
       safely.

       Subsequent runs (--update, --scan) compare each installed file against
       the current template. Files you have not touched are updated silently.
       Files you have edited are left alone. Files where both you and the
       template changed are presented one at a time for a manual decision.

       A file you delete is never reinstalled. Remove its entry from .mkproj
       if you change your mind.

OPTIONS
       --no-global
              Skip changes to ~/.bashrc, ~/.claude/settings.json, and global
              hooks. Useful when running in CI or on shared machines.

       --agent=claude|codex|none
              Choose which agent to launch after setup. Default: ask.

       --keybindings
              Install ~/.claude/keybindings.json from the bundled template.
              Default: off. Keybindings are personal; use this flag only on
              machines where you want the managed defaults.

       --dry-run
              Show what would be created or changed without writing anything.
              Works with the default setup mode.

       --yes, -y
              Accept all non-conflict updates without prompting. On conflicts,
              automatically keeps the existing file (safe default).

       --quiet, -q
              Suppress informational output. Errors and conflict prompts are
              still shown.

       --verbose, -v
              Show every file decision including up-to-date skips.

MODES
       (default)
              Bootstrap a new project in the current directory or NAME.

       --update [NAME]
              Update an existing mkproj project. NAME defaults to the current
              directory. Compares every tracked file against its template and
              applies the decision table (see FILES section).

       --scan [DIR]
              Recursively find and update all mkproj projects under DIR.
              DIR defaults to the current directory. Skips .git/, .venv/,
              node_modules/, and __pycache__/. Presents non-managed Claude
              Code projects separately and offers to adopt them.

       --status [DIR]
              Dry-run scan: print one line per project showing its installed
              mkproj version vs the current tool version and a file change
              summary. No files are written. Exit code 2 if any project has
              pending updates or conflicts.

       --pending [DIR]
              Find all deferred decisions across projects under DIR and
              present them interactively one by one.

       --adopt [NAME]
              Enroll an existing Claude Code project (one with .claude/ or
              CLAUDE.md but no .mkproj) into mkproj management. Only adds
              missing files; never modifies existing ones. Creates .mkproj
              recording the current state.

       --doctor [NAME]
              Read-only diagnostics: check environment and project health
              without changing anything.

       --test Isolated end-to-end scaffold and negative tests. No global
              changes or pushes.

       --version
              Print mkproj version and exit.

       --help Print this page and exit.

FILES
       .mkproj
              Per-project identity and file-tracking record. JSON. Gitignored.
              Contains installed mkproj version, install/update timestamps,
              and per-file hash pairs (template hash + installed hash).

       ~/.claude/keybindings.json.last-installed-hash
              Hash sidecar for keybindings template tracking. Used only when
              --keybindings is active.

       templates/
              All files mkproj installs into new projects. Edit these to
              change what every future (and updated) project receives.

EXIT STATUS
       0      Success.
       1      Error. Message written to stderr.
       2      --status or --scan found projects with pending updates or
              unresolved conflicts.

ENVIRONMENT
       HOME          Locates ~/.claude/ for global configuration.
       TMPDIR        Scratch space for --test mode.
       STY           If unset, mkproj wraps itself in a screen session for
                     interactive agent launches.

NAMES
       Project names: 1-64 ASCII characters, starting a-z, followed by
       a-z, 0-9, or underscore. Python keywords are refused. Full project
       paths are limited to 2048 bytes.

EXAMPLES
       # Bootstrap a new project
       cd ~/Projects && mkproj my_app

       # Bootstrap with keybindings installed
       mkproj --keybindings my_app

       # Update a single project
       cd ~/Projects/my_app && mkproj --update

       # Update all projects under ~/Projects
       mkproj --scan ~/Projects

       # See what would change without touching anything
       mkproj --status ~/Projects

       # Enroll an existing project
       cd ~/Projects/legacy_project && mkproj --adopt

       # Non-interactive update (keep all conflicts)
       mkproj --scan ~/Projects --yes --quiet

SEE ALSO
       claude(1), codex(1), git(1), screen(1)

       Project repository and documentation:
       https://github.com/BogusException/project-bootstrap
MANPAGE
}
```

**Step 2: Verify help output**

```bash
mkproj --help | head -20
# Expected: starts with "NAME"
mkproj --help | grep -c "SYNOPSIS\|DESCRIPTION\|OPTIONS\|MODES\|FILES\|EXIT STATUS\|EXAMPLES"
# Expected: 7
```

**Step 3: Run tests**

```bash
mkproj --test
```
Expected: pass.

**Step 4: Commit**

```bash
git add bootstrap.sh
git commit -m "feat: rewrite --help as man-page format with pager support"
```

---

## Task 7: Create lib/update.sh -- file comparison engine

**Purpose:** Core logic for comparing a project file against its template entry.

**Files:**
- Create: `lib/update.sh`
- Modify: `bootstrap.sh` (add source line)

**Step 1: Create lib/update.sh with the comparison function**

```bash
#!/usr/bin/env bash
# update.sh — mkproj update and scan logic

# file_update_decision PROJECT_DIR REL_PATH
# Echoes one of: skip_unchanged | auto_update | skip_user_edit |
#                conflict | skip_deleted | new_file | untracked
file_update_decision() {
    local project_dir="$1" rel="$2"
    local disk_path="$project_dir/$rel"
    local status; status="$(registry_file_status "$project_dir" "$rel")"

    # File tracked as installed but missing: user deleted it
    if [[ "$status" == "installed" && ! -f "$disk_path" ]]; then
        printf 'skip_deleted\n'; return
    fi
    # Deferred from a previous run
    if [[ "$status" == "deferred" ]]; then
        printf 'conflict\n'; return
    fi
    # Not tracked at all: new template file
    if [[ "$status" == "unknown" ]]; then
        [[ -f "$disk_path" ]] && printf 'untracked\n' || printf 'new_file\n'
        return
    fi

    local hashes; hashes="$(registry_file_hashes "$project_dir" "$rel")"
    local stored_tpl_hash="${hashes%% *}"
    local stored_inst_hash="${hashes##* }"

    # Recompute current hashes
    local cur_tpl_hash cur_disk_hash
    cur_tpl_hash="$(current_template_hash "$rel")"
    [[ -f "$disk_path" ]] && cur_disk_hash="$(sha256sum "$disk_path" | cut -d' ' -f1)" || cur_disk_hash=""

    local tpl_changed=false disk_changed=false
    [[ "$cur_tpl_hash" != "$stored_tpl_hash" ]] && tpl_changed=true
    [[ "$cur_disk_hash" != "$stored_inst_hash" ]] && disk_changed=true

    if [[ "$tpl_changed" == false && "$disk_changed" == false ]]; then
        printf 'skip_unchanged\n'
    elif [[ "$tpl_changed" == true && "$disk_changed" == false ]]; then
        printf 'auto_update\n'
    elif [[ "$tpl_changed" == false && "$disk_changed" == true ]]; then
        printf 'skip_user_edit\n'
    else
        printf 'conflict\n'
    fi
}

# current_template_hash REL_PATH
# Echoes the SHA-256 of the current template for this project-relative path.
# For settings.json (generated), echoes hash of generate_settings_json output.
current_template_hash() {
    local rel="$1"
    if [[ "$rel" == ".claude/settings.json" ]]; then
        generate_settings_json | sha256sum | cut -d' ' -f1
        return
    fi
    local tpl_path; tpl_path="$(project_to_template_path "$rel")"
    [[ -f "$tpl_path" ]] && sha256sum "$tpl_path" | cut -d' ' -f1 || printf '\n'
}

# project_to_template_path REL_PATH
# Inverse of template_to_project_path: maps a project path to the template source.
project_to_template_path() {
    local rel="$1"
    case "$rel" in
        .claude/hooks/*) printf '%s/hooks/%s\n' "$TEMPLATES_DIR" "${rel#.claude/hooks/}" ;;
        .claude/rules/*) printf '%s/rules/%s\n' "$TEMPLATES_DIR" "${rel#.claude/rules/}" ;;
        .git/hooks/*)    printf '%s/git-hooks/%s\n' "$TEMPLATES_DIR" "${rel#.git/hooks/}" ;;
        docs/*)          printf '%s/%s\n' "$TEMPLATES_DIR" "$rel" ;;
        tasks/*)         printf '%s/%s\n' "$TEMPLATES_DIR" "$rel" ;;
        *)               printf '%s/%s\n' "$TEMPLATES_DIR" "$rel" ;;
    esac
}

# apply_template_file PROJECT_DIR REL_PATH
# Copies (or generates) the current template version to the project file.
# Handles {{PROJECT_NAME}} substitution. Returns 0 on success.
apply_template_file() {
    local project_dir="$1" rel="$2"
    local project_name; project_name="$(basename "$project_dir")"
    local disk_path="$project_dir/$rel"
    mkdir -p "$(dirname "$disk_path")"

    if [[ "$rel" == ".claude/settings.json" ]]; then
        generate_settings_json > "$disk_path"
    else
        local tpl_path; tpl_path="$(project_to_template_path "$rel")"
        [[ -f "$tpl_path" ]] || { err "Template not found: $tpl_path"; return 1; }
        sed "s/{{PROJECT_NAME}}/$project_name/g" "$tpl_path" > "$disk_path"
    fi

    local tpl_hash disk_hash
    tpl_hash="$(current_template_hash "$rel")"
    disk_hash="$(sha256sum "$disk_path" | cut -d' ' -f1)"
    registry_set_file "$project_dir" "$rel" "$tpl_hash" "$disk_hash" "installed"
}

# show_conflict_ui PROJECT_DIR REL_PATH
# Presents the conflict diff to the user and returns their choice:
# u (update) | k (keep) | d (defer) | s (stop)
show_conflict_ui() {
    local project_dir="$1" rel="$2"
    local disk_path="$project_dir/$rel"
    local tpl_path; tpl_path="$(project_to_template_path "$rel")"

    printf '\n%s\n' "─────────────────────────────────────────────────────"
    printf '  [conflict]  %s\n' "$rel"
    printf '  Project:    %s\n' "$project_dir"
    printf '  %s\n' "─────────"

    # Show unified diff (template vs disk), truncate at 20 lines
    local diff_output
    if [[ "$rel" == ".claude/settings.json" ]]; then
        diff_output="$(diff -u <(generate_settings_json) "$disk_path" 2>/dev/null || true)"
    else
        diff_output="$(diff -u "$tpl_path" "$disk_path" 2>/dev/null || true)"
    fi

    local line_count; line_count="$(printf '%s\n' "$diff_output" | wc -l)"
    if (( line_count > 20 )); then
        printf '%s\n' "$diff_output" | head -20
        printf '  ... (%d more lines)\n' "$(( line_count - 20 ))"
    else
        printf '%s\n' "$diff_output"
    fi

    printf '  %s\n' "─────────"
    printf '  [u] Update to new template version\n'
    printf '  [k] Keep your version unchanged\n'
    printf '  [d] Defer this decision (revisit with --pending)\n'
    printf '  [s] Stop reviewing; leave all remaining for later\n\n'

    local choice
    read_choice choice "  Choice [u/k/d/s, default=d]: " d ukdsUKDS
    printf '%s\n' "${choice,,}"
}

# update_project PROJECT_DIR
# Runs the update loop for one project. Writes updated .mkproj.
# Returns exit code 2 if any conflicts remain unresolved.
update_project() {
    local project_dir="$1"
    local had_conflict=false stopped=false

    # Retroactively stamp if no .mkproj exists but project has mkproj markers
    if ! registry_exists "$project_dir"; then
        if _is_claude_project "$project_dir"; then
            log "  stamping $project_dir (no .mkproj found)"
            registry_stamp_from_disk "$project_dir"
        else
            err "$project_dir is not a mkproj project."
            return 1
        fi
    fi

    local all_template_files=()
    while IFS= read -r -d '' f; do
        local rel; rel="$(template_to_project_path "$f")"
        [[ -n "$rel" ]] || continue
        all_template_files+=("$rel")
    done < <(find "$TEMPLATES_DIR" -type f \( ! -path "*/backups/*" ! -name "*.bak" \) -print0)
    # Also add settings.json (generated, not in TEMPLATES_DIR)
    all_template_files+=(".claude/settings.json")

    for rel in "${all_template_files[@]}"; do
        [[ "$stopped" == true ]] && break
        local decision; decision="$(file_update_decision "$project_dir" "$rel")"

        case "$decision" in
            skip_unchanged)
                [[ "$VERBOSE" == true ]] && log "  up to date: $rel" ;;
            auto_update)
                log "  updating: $rel"
                apply_template_file "$project_dir" "$rel" ;;
            skip_user_edit)
                [[ "$VERBOSE" == true ]] && log "  kept (user edits): $rel" ;;
            skip_deleted)
                [[ "$QUIET" != true ]] && log "  skipped (user deleted): $rel" ;;
            new_file)
                log "  installing new file: $rel"
                apply_template_file "$project_dir" "$rel" ;;
            untracked)
                [[ "$VERBOSE" == true ]] && log "  untracked (exists, not from template): $rel" ;;
            conflict)
                had_conflict=true
                if [[ "$YES_MODE" == true ]]; then
                    log "  kept (conflict, --yes): $rel"
                    registry_set_file "$project_dir" "$rel" \
                        "$(current_template_hash "$rel")" \
                        "$(sha256sum "$project_dir/$rel" | cut -d' ' -f1)" "installed"
                else
                    local choice; choice="$(show_conflict_ui "$project_dir" "$rel")"
                    case "$choice" in
                        u) apply_template_file "$project_dir" "$rel" ;;
                        k) registry_set_file "$project_dir" "$rel" \
                               "$(current_template_hash "$rel")" \
                               "$(sha256sum "$project_dir/$rel" | cut -d' ' -f1)" "installed" ;;
                        d) registry_set_file "$project_dir" "$rel" \
                               "$(current_template_hash "$rel")" \
                               "$(sha256sum "$project_dir/$rel" | cut -d' ' -f1)" "deferred" ;;
                        s) stopped=true ;;
                    esac
                fi ;;
        esac
    done

    registry_touch_updated "$project_dir"
    [[ "$had_conflict" == false && "$stopped" == false ]]
}

# _is_claude_project DIR
# Returns 0 if DIR looks like a Claude Code project.
_is_claude_project() {
    [[ -f "$1/.claude/settings.json" || -f "$1/CLAUDE.md" ]]
}

# scan_projects ROOT_DIR
# Finds .mkproj files and non-managed Claude Code projects under ROOT_DIR.
# Echoes lines: "managed:PATH" or "unmanaged:PATH"
scan_projects() {
    local root="$1"
    # Use find with pruning for excluded dirs
    while IFS= read -r -d '' item; do
        local dir; dir="$(dirname "$item")"
        printf 'managed:%s\n' "$dir"
    done < <(find "$root" \
        -not \( \
            -name ".git" -o -name ".venv" -o -name "node_modules" \
            -o -name "__pycache__" -o -name "backups" -o -name "responses" \
        \) -prune \
        -name ".mkproj" -print0 2>/dev/null)

    while IFS= read -r -d '' item; do
        local dir; dir="$(dirname "$item")"
        # Skip if already has .mkproj
        [[ -f "$dir/.mkproj" ]] && continue
        printf 'unmanaged:%s\n' "$dir"
    done < <(find "$root" \
        -not \( \
            -name ".git" -o -name ".venv" -o -name "node_modules" \
            -o -name "__pycache__" -o -name "backups" -o -name "responses" \
        \) -prune \
        -name "CLAUDE.md" -print0 2>/dev/null)
}

# adopt_project PROJECT_DIR
# Minimal adoption: create .mkproj, add missing .gitignore guards, add AGENTS.md if absent.
adopt_project() {
    local project_dir="$1"
    registry_create "$project_dir" "$MKPROJ_VERSION" '["adopted"]'

    # Add missing .gitignore privacy guards
    local gitignore="$project_dir/.gitignore"
    local guard_lines=(
        "responses/" "backups/" ".env" ".venv/" "*.pyc" "__pycache__/"
        ".mkproj"
    )
    for line in "${guard_lines[@]}"; do
        grep -qxF "$line" "$gitignore" 2>/dev/null || printf '%s\n' "$line" >> "$gitignore"
    done

    # Add AGENTS.md if absent
    if [[ ! -f "$project_dir/AGENTS.md" ]]; then
        cp "$TEMPLATES_DIR/AGENTS.md" "$project_dir/AGENTS.md"
        registry_set_file "$project_dir" "AGENTS.md" \
            "$(sha256sum "$TEMPLATES_DIR/AGENTS.md" | cut -d' ' -f1)" \
            "$(sha256sum "$project_dir/AGENTS.md" | cut -d' ' -f1)" "installed"
    fi

    log "  adopted: $project_dir"
}
```

**Step 2: Source lib/update.sh in bootstrap.sh**

Add after the registry.sh source line:
```bash
source "$BOOTSTRAP_DIR/lib/update.sh"
```

**Step 3: Syntax check**

```bash
bash -n lib/update.sh && echo "ok"
```
Expected: `ok`

**Step 4: Commit**

```bash
git add lib/update.sh bootstrap.sh
git commit -m "feat: add lib/update.sh with file comparison, conflict UI, scan, and adopt logic"
```

---

## Task 8: Wire new modes into main()

**Purpose:** Route `--update`, `--scan`, `--status`, `--pending`, and `--adopt` from main().

**Files:**
- Modify: `bootstrap.sh` (main function and mode handlers)

**Step 1: Add mode dispatch to main() before the phase loop**

After `initialize "$@"` and after MODE=version is handled, add:

```bash
case "$MODE" in
    update)  run_update_mode;  exit $? ;;
    scan)    run_scan_mode;    exit $? ;;
    status)  run_status_mode;  exit $? ;;
    pending) run_pending_mode; exit $? ;;
    adopt)   run_adopt_mode;   exit $? ;;
esac
```

**Step 2: Implement run_update_mode()**

```bash
run_update_mode() {
    local target="$PROJECT_DIR"
    [[ "$HAS_PROJECT_ARG" == true ]] && target="$PWD/$PROJECT_ARG"
    [[ -d "$target" ]] || { err "Not a directory: $target"; return 1; }
    registry_exists "$target" || _is_claude_project "$target" || {
        err "Not a mkproj or Claude Code project: $target"; return 1;
    }
    log "Updating: $target"
    update_project "$target"
}
```

**Step 3: Implement run_scan_mode()**

```bash
run_scan_mode() {
    local had_issues=false
    local managed=() unmanaged=()
    while IFS= read -r line; do
        case "$line" in
            managed:*)   managed+=("${line#managed:}") ;;
            unmanaged:*) unmanaged+=("${line#unmanaged:}") ;;
        esac
    done < <(scan_projects "$SCAN_DIR")

    for d in "${managed[@]}"; do
        log "=== $d ==="
        update_project "$d" || had_issues=true
    done

    if (( ${#unmanaged[@]} )); then
        printf '\nClaude Code projects (not managed by mkproj):\n'
        for d in "${unmanaged[@]}"; do
            printf '  %s\n' "$d"
            if [[ "$YES_MODE" == true ]]; then
                adopt_project "$d"
            else
                local adopt_ans
                read_choice adopt_ans "  Adopt this project? [y/N]: " n yYnN
                [[ "${adopt_ans,,}" == y ]] && adopt_project "$d"
            fi
        done
    fi

    [[ "$had_issues" == false ]]
}
```

**Step 4: Implement run_status_mode()**

```bash
run_status_mode() {
    local managed=() unmanaged=() other=()
    while IFS= read -r line; do
        case "$line" in
            managed:*)   managed+=("${line#managed:}") ;;
            unmanaged:*) unmanaged+=("${line#unmanaged:}") ;;
        esac
    done < <(scan_projects "$SCAN_DIR")

    local exit_code=0
    printf '\nManaged projects (%d):\n' "${#managed[@]}"
    for d in "${managed[@]}"; do
        local inst_ver changes
        inst_ver="$(registry_read "$d" '.mkproj_version // "?"')"
        # Quick change count (auto_update + conflict only)
        changes=0
        while IFS= read -r -d '' f; do
            local rel; rel="$(template_to_project_path "$f")"
            [[ -n "$rel" ]] || continue
            local dec; dec="$(file_update_decision "$d" "$rel")"
            [[ "$dec" == "auto_update" || "$dec" == "conflict" ]] && ((changes++)) || true
        done < <(find "$TEMPLATES_DIR" -type f \( ! -path "*/backups/*" ! -name "*.bak" \) -print0)
        (( changes > 0 )) && exit_code=2
        printf '  %-30s  installed %-8s  current %-8s  %s\n' \
            "$(basename "$d")" "$inst_ver" "$MKPROJ_VERSION" \
            "$(( changes == 0 )) && echo 'up to date' || echo "$changes files pending""
    done

    if (( ${#unmanaged[@]} )); then
        printf '\nClaude Code projects (not managed, %d):\n' "${#unmanaged[@]}"
        for d in "${unmanaged[@]}"; do
            printf '  %-30s  no .mkproj -- run: mkproj --adopt %s\n' \
                "$(basename "$d")" "$(basename "$d")"
            exit_code=2
        done
    fi

    return "$exit_code"
}
```

**Step 5: Implement run_pending_mode()**

```bash
run_pending_mode() {
    local managed=()
    while IFS= read -r line; do
        [[ "$line" == managed:* ]] && managed+=("${line#managed:}")
    done < <(scan_projects "$SCAN_DIR")

    local found=false
    for d in "${managed[@]}"; do
        registry_exists "$d" || continue
        while IFS= read -r rel; do
            local st; st="$(registry_file_status "$d" "$rel")"
            [[ "$st" == "deferred" ]] || continue
            found=true
            log "Pending: $d / $rel"
            local choice; choice="$(show_conflict_ui "$d" "$rel")"
            case "$choice" in
                u) apply_template_file "$d" "$rel" ;;
                k) registry_set_file "$d" "$rel" \
                       "$(current_template_hash "$rel")" \
                       "$(sha256sum "$d/$rel" | cut -d' ' -f1)" "installed" ;;
                d) : ;;  # keep deferred
                s) return 0 ;;
            esac
        done < <(registry_all_files "$d")
    done

    [[ "$found" == true ]] || log "No pending decisions found under $SCAN_DIR."
}
```

**Step 6: Implement run_adopt_mode()**

```bash
run_adopt_mode() {
    local target="$PROJECT_DIR"
    [[ "$HAS_PROJECT_ARG" == true ]] && target="$PWD/$PROJECT_ARG"
    [[ -d "$target" ]] || { err "Not a directory: $target"; return 1; }
    if registry_exists "$target"; then
        log "Already managed: $target"
        return 0
    fi
    _is_claude_project "$target" || {
        err "No .claude/ or CLAUDE.md found in: $target"; return 1;
    }
    adopt_project "$target"
}
```

**Step 7: Run tests**

```bash
mkproj --test
```

**Step 8: Smoke test new modes**

```bash
mkproj --version
mkproj --status ~/Projects 2>&1 | head -5
mkproj --scan ~/Projects --dry-run 2>&1 | head -10
```

**Step 9: Commit**

```bash
git add bootstrap.sh
git commit -m "feat: wire --update, --scan, --status, --pending, --adopt modes into main()"
```

---

## Task 9: Tests for new functionality

**Purpose:** Extend phase9_test_validate with tests for new modes and .mkproj output.

**Files:**
- Modify: `bootstrap.sh` (phase9_test_validate)

**Step 1: Add .mkproj tests to phase9_test_validate**

After the existing test blocks, add:

```bash
# .mkproj registry tests
run_test "mkproj_file_created" test -f "$PROJECT_DIR/.mkproj"
run_test "mkproj_valid_json" jq empty "$PROJECT_DIR/.mkproj"
run_test "mkproj_version_set" test "$(jq -r '.mkproj_version' "$PROJECT_DIR/.mkproj")" = "$MKPROJ_VERSION"
run_test "mkproj_has_claude_md" test "$(jq -r '.files["CLAUDE.md"].status' "$PROJECT_DIR/.mkproj")" = "installed"
run_test "mkproj_gitignored" grep -qxF ".mkproj" "$PROJECT_DIR/.gitignore"

# --version test
run_test "version_output" test "$(mkproj --version)" = "mkproj $MKPROJ_VERSION"

# --update test: create a modified file, verify update detects it
cp "$TEMPLATES_DIR/AGENTS.md" "$PROJECT_DIR/AGENTS.md.orig"
printf 'MODIFIED\n' >> "$PROJECT_DIR/AGENTS.md"
run_test "update_detects_conflict" bash -c '
    source "$BOOTSTRAP_DIR/lib/registry.sh"
    source "$BOOTSTRAP_DIR/lib/update.sh"
    PROJECT_DIR="'"$PROJECT_DIR"'"
    dec="$(file_update_decision "$PROJECT_DIR" "AGENTS.md")"
    [[ "$dec" == "conflict" || "$dec" == "skip_user_edit" ]]
'
mv "$PROJECT_DIR/AGENTS.md.orig" "$PROJECT_DIR/AGENTS.md"
```

**Step 2: Run the full test suite**

```bash
mkproj --test
```
Expected: all tests pass including new ones.

**Step 3: Commit**

```bash
git add bootstrap.sh
git commit -m "test: add .mkproj registry and update detection tests to phase9_test_validate"
```

---

## Task 10: TODO.md and documentation updates

**Purpose:** Record deferred features and update usage docs.

**Files:**
- Create or update: `tasks/todo.md`
- Modify: `docs/usage.md`
- Modify: `docs/doc-index.md`
- Modify: `README.md`

**Step 1: Update tasks/todo.md with deferred items**

Add a section:

```markdown
## Deferred from v2.0.0

- [ ] `--update --components=hooks,rules` -- selective component updates
- [ ] `--max-depth N` for scan depth control
- [ ] `--force` flag to auto-accept template on conflicts (requires audit trail)
- [ ] Component-level options in `--adopt`
- [ ] `--json` machine-readable output for scripting
- [ ] `mkproj --init` alias for setup
- [ ] Windows native support (PowerShell port -- low priority, WSL2 is recommended path)
- [ ] `mkproj --diff NAME` -- show pending changes without updating
- [ ] Automatic `--scan` on `mkproj --doctor` to surface stale projects
```

**Step 2: Update docs/usage.md**

Add sections for:
- `§8 Updating existing projects (--update, --scan, --status)`
- `§9 Adopting non-mkproj projects (--adopt)`
- `§10 Keybindings (--keybindings)`

**Step 3: Update docs/doc-index.md**

Add entries under M for `.mkproj`, U for `--update`, S for `--scan`, `--status`.

**Step 4: Update README.md**

Expand the Commands section with:
```bash
# Update a single project
mkproj --update [name]

# Scan and update all projects under ~/Projects
mkproj --scan ~/Projects

# Check what would change (dry-run)
mkproj --status ~/Projects

# Adopt an existing Claude Code project
mkproj --adopt [name]
```

**Step 5: Commit**

```bash
git add tasks/todo.md docs/usage.md docs/doc-index.md README.md
git commit -m "docs: update README, usage, doc-index, and TODO for v2.0.0 update system"
```

---

## Final: push and verify

```bash
git log --oneline -10
# Verify all tasks committed cleanly

mkproj --test
# Final full test run

mkproj --version
# mkproj 2.0.0

mkproj --help | head -5
# NAME
#        mkproj ...

git push origin main
```

---

## Notes for implementer

- `run_status_mode` has a printf with an inline conditional that needs to be corrected during implementation -- the shell quoting shown is conceptual; rewrite as a proper `if/else` block.
- The `scan_projects` function uses a find with `-prune` before `-name`; test carefully as find prune behavior with `-not ... -prune` is nuanced. Use `-mindepth 1` if needed to avoid pruning the root dir.
- `read_choice` is defined in `lib/input.sh` and requires the global `BOOTSTRAP_DIR` to be set. All new mode functions run after `initialize` so this is guaranteed.
- `.mkproj` is written outside the git tree (gitignored). No `git add` ever touches it.
- Phase 7 global changes (bashrc, settings, hooks) do NOT run for `--update`/`--scan` modes unless `--no-global` was not passed and the user opts in. The simplest approach: just skip phase7 for these modes (don't call it from their handlers).
