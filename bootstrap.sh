#!/usr/bin/env bash
# bootstrap.sh — project-bootstrap
# Usage: cd ~/Projects && mkproj <name>
set -euo pipefail

BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$BOOTSTRAP_DIR/templates"
TEMPLATE_NAME=""    # set in initialize(); empty = prompt user
TEMPLATE_DIR=""     # set in initialize() after TEMPLATE_NAME is resolved
MODULE_NAME=""      # derived from PROJECT_NAME (hyphens -> underscores)
MKPROJ_VERSION="3.0.2"
INSTALL_KEYBINDINGS=false
TEST_MODE=false
SETUP_LOCAL_REPO=false
BARE_REPO=""
SAFE_MODE=false
CHECK_MODE=false
REPORT_MODE=false
FORCE_FILE=""
ACCEPT_FILE=""
RESTORE_INFRA_MODE=false
LIST_TIERS_MODE=false

# ─── Colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { printf "${GREEN}[bootstrap]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[bootstrap]${NC} %s\n" "$*"; }
err()  { printf "${RED}[bootstrap]${NC} %s\n" "$*" >&2; }

source "$BOOTSTRAP_DIR/lib/input.sh"
source "$BOOTSTRAP_DIR/lib/runtime.sh"
source "$BOOTSTRAP_DIR/lib/registry.sh"
source "$BOOTSTRAP_DIR/lib/update.sh"
CREATED_FILES=()
TEST_ROOT=""
TEST_PARENT=""
CURRENT_PHASE=initialize
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
       mkproj --update [NAME] [--force-file REL_PATH]
       mkproj --safe-update [DIR]
       mkproj --check [DIR]
       mkproj --report [DIR]
       mkproj --accept DIR --file REL_PATH
       mkproj --restore-infra [DIR]
       mkproj --list-tiers [DIR]
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

       Every tracked file has a tier: directive, infrastructure, or optional.
       Tiers control how deletions and conflicts are handled. See TIERS below.

FILE TIERS
       directive
              Files that directly control agent behavior: CLAUDE.md, AGENTS.md.
              mkproj never auto-updates these. Deletions are flagged as errors.
              Conflicts require a human decision. Use --report to get the full
              picture and --force-file to override after deliberate review.

       infrastructure
              Hooks, settings, git-hooks, and rules. Safe to auto-update when
              you have not modified them. Deletions are flagged with a warning
              and can be restored with --restore-infra.

       optional
              Docs, task stubs, example files, run/test scripts. If you delete
              an optional file, mkproj stops tracking it silently and never
              reinstalls it.

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
              automatically keeps the existing file (safe default). Has no
              effect on directive conflicts, which always require human review.

       --quiet, -q
              Suppress informational output. Errors and conflict prompts are
              still shown.

       --verbose, -v
              Show every file decision including up-to-date skips.

       --force-file REL_PATH
              Force a specific file to be updated from template, even if it is
              a directive or has user edits. Only valid with --update. Cannot
              be combined with --yes. The relative path must match the
              project-relative install path (e.g. CLAUDE.md or
              .claude/hooks/auto-commit.sh).

       --file REL_PATH
              Specify a single file for --accept. Required when using --accept.

MODES
       (default)
              Bootstrap a new project in the current directory or NAME.

       --update [NAME]
              Update an existing mkproj project. NAME defaults to the current
              directory. Compares every tracked file against its template and
              applies the decision table. Respects tier rules: directive files
              are never silently overwritten.

       --safe-update [DIR]
              Auto-apply only infrastructure-tier auto_update decisions. Never
              touches directive files. Never restores deleted optionals. If
              directive problems exist, prints them and exits non-zero even if
              safe updates succeeded.

       --check [DIR]
              Read-only. Walk all tracked files and report:
                - directive files that are missing or have conflicts  (ERROR)
                - infrastructure files out of sync or deleted         (WARNING)
                - optional deleted files are completely silent
              No writes. Exit 0 if clean, 1 if warnings, 2 if errors.

       --report [DIR]
              Write mkproj-issues-YYYYMMDD-HHMMSS.md to the project directory.
              Contains one section per issue with severity, tier, risk summary,
              and exact commands to fix or accept each file.

       --accept DIR --file REL_PATH
              Mark a file as "user version accepted" in .mkproj by updating
              the stored template hash to current. Resolves a conflict without
              overwriting. This is the "keep mine, stop flagging" operation.

       --restore-infra [DIR]
              Restore any infrastructure-tier files that were deleted. Does
              not touch directive or optional files. Always interactive --
              shows the list before writing. The --yes flag has no effect here.

       --list-tiers [DIR]
              Print a table of all tracked files with their tier, current
              status, and last-updated timestamp.

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
              and per-file hash pairs (template hash + installed hash + tier).

       templates/.mkproj-manifest.json
              Declares the tier for every template file. Any file not listed
              defaults to optional.

       ~/.claude/keybindings.json.last-installed-hash
              Hash sidecar for keybindings template tracking. Used only when
              --keybindings is active.

       templates/
              All files mkproj installs into new projects. Edit these to
              change what every future (and updated) project receives.

EXIT STATUS
       0      Success.
       1      Error or warnings found (--check found warnings only).
       2      --status, --scan, or --check found errors or projects with
              pending updates or unresolved conflicts.

ENVIRONMENT
       HOME          Locates ~/.claude/ for global configuration.
       TMPDIR        Scratch space for --test mode.
       STY           If unset, mkproj wraps itself in a screen session for
                     interactive agent launches.

NAMES
       Project names: 1-64 ASCII characters, starting a-z, followed by
       a-z, 0-9, underscore, or hyphen (no trailing or consecutive hyphens).
       Python keywords are refused. Full project paths are limited to 2048
       bytes. When the name contains hyphens, the Python module directory
       under src/ uses underscores (e.g. my-tool -> src/my_tool/).

EXAMPLES
       # Bootstrap a new project
       cd ~/Projects && mkproj my_app

       # Bootstrap with keybindings installed
       mkproj --keybindings my_app

       # Update a single project
       cd ~/Projects/my_app && mkproj --update

       # Update all projects under ~/Projects
       mkproj --scan ~/Projects

       # Check for directive/infrastructure issues without writing
       mkproj --check ~/Projects/my_app

       # Run safe (infrastructure-only) updates non-interactively
       mkproj --safe-update ~/Projects/my_app

       # Write a full issue report to the project directory
       mkproj --report ~/Projects/my_app

       # Force-update a single file (use after reviewing --report)
       mkproj --update ~/Projects/my_app --force-file CLAUDE.md

       # Accept your version of a file and stop flagging it
       mkproj --accept ~/Projects/my_app --file .claude/rules/security.md

       # Restore deleted infrastructure files
       mkproj --restore-infra ~/Projects/my_app

       # Show all tracked files with tiers and status
       mkproj --list-tiers ~/Projects/my_app

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
cleanup_test() {
    [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" && ! -L "$TEST_ROOT" &&
       "$TEST_ROOT" == "$TEST_PARENT"/mkproj-test.* ]] || return 0
    rm -rf -- "$TEST_ROOT"
}
initialize() {
    parse_args "$@"
    CONFIGURE_GLOBAL=false
    if [[ "$MODE" == help || "$MODE" == version || "$MODE" == list-templates || \
          "$MODE" == scan || "$MODE" == status || "$MODE" == pending || \
          "$MODE" == check || "$MODE" == safe-update || "$MODE" == report || \
          "$MODE" == restore-infra || "$MODE" == list-tiers ]]; then return 0; fi
    if [[ "$MODE" == test ]]; then
        TEST_MODE=true
        unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
        export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
        export GIT_AUTHOR_NAME="Bootstrap test" GIT_AUTHOR_EMAIL="test@example.invalid"
        export GIT_COMMITTER_NAME="Bootstrap test" GIT_COMMITTER_EMAIL="test@example.invalid"
        TEST_PARENT="$(realpath "${TMPDIR:-/tmp}")"
        TEST_ROOT="$(mktemp -d "$TEST_PARENT/mkproj-test.XXXXXXXX")"
        PROJECT_NAME=mkproj_test
        PROJECT_DIR="$TEST_ROOT/$PROJECT_NAME"
        BARE_REPO="$TEST_ROOT/repositories/$PROJECT_NAME.git"
        SETUP_LOCAL_REPO=true
        LAUNCH_AGENT=none
        NO_GLOBAL=true
        trap cleanup_test EXIT
    elif [[ "$HAS_PROJECT_ARG" == true ]]; then
        # accept/adopt/update modes accept a directory path, not just a project name
        if [[ "$MODE" == accept || "$MODE" == adopt || "$MODE" == update ]]; then
            if [[ -d "$PROJECT_ARG" ]]; then
                PROJECT_DIR="$(realpath -- "$PROJECT_ARG")"
                PROJECT_NAME="$(basename "$PROJECT_DIR")"
            else
                PROJECT_NAME="$PROJECT_ARG"
                PROJECT_DIR="$PWD/$PROJECT_NAME"
            fi
        else
            PROJECT_NAME="$PROJECT_ARG"
            PROJECT_DIR="$PWD/$PROJECT_NAME"
        fi
        if [[ "$MODE" == setup || "$MODE" == test ]]; then validate_name "$PROJECT_NAME"; fi
    else
        PROJECT_DIR="$PWD"
        PROJECT_NAME="$(basename "$PROJECT_DIR")"
        if [[ "$MODE" != doctor && "$MODE" != accept ]]; then validate_name "$PROJECT_NAME"; fi
    fi
    validate_project_path "$PROJECT_DIR"
    # Resolve template (skip for modes that don't create a project)
    if [[ "$MODE" == setup || "$MODE" == test ]]; then
        if [[ -z "$TEMPLATE_NAME" ]]; then
            if [[ "$MODE" == setup && "${YES_MODE:-false}" == false && -t 0 ]]; then
                TEMPLATE_NAME="$(prompt_template_select)"
            else
                TEMPLATE_NAME="$(_default_template_name)"
            fi
        fi
        if [[ ! -d "$TEMPLATES_DIR/$TEMPLATE_NAME" ]]; then
            err "Template '$TEMPLATE_NAME' not found in $TEMPLATES_DIR"; return 1
        fi
        TEMPLATE_DIR="$TEMPLATES_DIR/$TEMPLATE_NAME"
        MODULE_NAME="${PROJECT_NAME//-/_}"
    fi
    if [[ "$MODE" == setup && "$LAUNCH_AGENT" != none && -z "${STY:-}" ]]; then
        command -v screen >/dev/null || { err "screen is required for an interactive launch."; return 1; }
        exec screen -S "$PROJECT_NAME" bash -c '"$1" "${@:2}"; status=$?; (( status == 0 )) || exit "$status"; exec bash' bash "$BOOTSTRAP_DIR/bootstrap.sh" "$@"
    fi
}

# ─── Phase 1: Preflight ───────────────────────────────────────────────────────
phase1_preflight() {
    log "=== Phase 1: Preflight ==="

    # ── First: confirm the project name and path before touching anything ─────
    if [[ "$TEST_MODE" != "true" ]]; then
        echo ""
        log "  Project : $PROJECT_NAME"
        log "  Dir     : $PROJECT_DIR"
        echo ""
        local path_confirm
        read_choice path_confirm "Bootstrap '$PROJECT_NAME' in $PROJECT_DIR? [Y/n]: " y yYnN
        if [[ "${path_confirm,,}" == "n" ]]; then
            err "Aborted."
            exit 1
        fi
        echo ""
    fi

    check_prerequisites
    if [[ "$TEST_MODE" != true && ( -n "${GIT_DIR:-}" || -n "${GIT_WORK_TREE:-}" || -n "${GIT_INDEX_FILE:-}" ) ]]; then
        err "Unset Git path override variables before bootstrapping."; return 1
    fi
    check_project_repo
    if [[ "$TEST_MODE" == true ]]; then
        check_repo_destination
        return 0
    fi

    # Ask about bare repo next, so the summary can reflect the choice
    local local_repo_ans
    read_choice local_repo_ans "Set up a local bare repo in ~/Repositories/$PROJECT_NAME.git? [Y/n]: " y yYnN
    if [[ "${local_repo_ans,,}" != "n" ]]; then
        SETUP_LOCAL_REPO=true
        BARE_REPO="$(realpath -m -- "${MKPROJ_REPOSITORIES_DIR:-$HOME/Repositories}/$PROJECT_NAME.git")"
    fi

    check_repo_destination
    if [[ "$LAUNCH_AGENT" == ask ]]; then
        local agent_choice
        read_choice agent_choice "Launch 1) Claude 2) Codex 3) none [1]: " 1 123
        case "$agent_choice" in 1) LAUNCH_AGENT=claude;; 2) LAUNCH_AGENT=codex;; 3) LAUNCH_AGENT=none;; esac
    fi
    if [[ "$LAUNCH_AGENT" != none ]]; then
        command -v "$LAUNCH_AGENT" >/dev/null || { err "Selected agent is not installed: $LAUNCH_AGENT"; return 1; }
    fi
    if [[ "$NO_GLOBAL" == false ]]; then
        local global_choice
        read_choice global_choice "Configure global shell/hooks? [y/N]: " n yYnN
        [[ "$global_choice" != y ]] || CONFIGURE_GLOBAL=true
    fi

    # Summary of what will be created
    echo ""
    log "What will be set up:"
    log "  Project : $PROJECT_NAME"
    log "  Dir     : $PROJECT_DIR"
    log "  Git     : branch main"
    if [[ "$SETUP_LOCAL_REPO" == "true" ]]; then
        log "  Remote  : ~/Repositories/$PROJECT_NAME.git  (bare repo)"
    else
        log "  Remote  : none  (add later — docs/adding-remotes.md)"
    fi
    log "  Python  : .venv + requirements.txt stub"
    log "  Files   : CLAUDE.md  AGENTS.md  README.md  .gitignore  .env.example  run.sh  test.sh"
    log "  Claude  : settings.json + $(find "$TEMPLATE_DIR/claude/hooks" -name '*.sh' 2>/dev/null | wc -l | tr -d ' ') hooks + $(find "$TEMPLATE_DIR/claude/rules" -name '*.md' 2>/dev/null | wc -l | tr -d ' ') rules (from templates/$TEMPLATE_NAME)"
    log "  Dirs    : src/${PROJECT_NAME//-/_}/  tests/  docs/  tasks/  responses/"
    log "  Global  : $CONFIGURE_GLOBAL (verified configuration backups before edits)"
    log "  Launch  : $LAUNCH_AGENT"
    echo ""

    local confirm
    read_choice confirm "Proceed? [Y/n]: " y yYnN
    [[ "${confirm,,}" == "n" ]] && { err "Aborted."; exit 1; }
    echo ""
}

# ─── Phase 2: Git ─────────────────────────────────────────────────────────────
phase2_git() {
    log "=== Phase 2: Git ==="

    if [[ ! -d "$PROJECT_DIR/.git" ]]; then
        git -C "$PROJECT_DIR" init -q
        git -C "$PROJECT_DIR" checkout -qb main
        log "  Initialised repo on branch main"
    else
        log "  .git exists — skipping init"
    fi

    if [[ "$SETUP_LOCAL_REPO" == "true" ]]; then
        mkdir -p -- "$(dirname "$BARE_REPO")"
        if [[ ! -e "$BARE_REPO" ]]; then
            git init --bare -q "$BARE_REPO"
            log "  Created bare repo: $BARE_REPO"
        fi
        if ! git -C "$PROJECT_DIR" remote get-url origin >/dev/null 2>&1; then
            backup_config "$(git -C "$PROJECT_DIR" rev-parse --absolute-git-dir)/config"
            git -C "$PROJECT_DIR" remote add origin "$BARE_REPO"
        fi
        log "  Remote origin → $BARE_REPO"
    else
        log "  No remote configured — add one later (see docs/adding-remotes.md)"
    fi
}

# ─── Phase 3: Python ──────────────────────────────────────────────────────────
phase3_python() {
    log "=== Phase 3: Python ==="

    if [[ ! -d "$PROJECT_DIR/.venv" ]]; then
        python3 -m venv "$PROJECT_DIR/.venv"
        log "  Created .venv"
    else
        log "  .venv exists — skipping"
    fi

    if [[ ! -f "$PROJECT_DIR/requirements.txt" ]]; then
        cp "$TEMPLATE_DIR/project/requirements.txt" "$PROJECT_DIR/requirements.txt"
        CREATED_FILES+=(requirements.txt)
        log "  Created requirements.txt"
    else
        log "  requirements.txt exists — skipping"
    fi
}

# ─── Template helpers ─────────────────────────────────────────────────────────
_default_template_name() {
    local f="$TEMPLATES_DIR/.default"
    [[ -f "$f" ]] && tr -d '[:space:]' < "$f" || echo "claude-code"
}

list_templates() {
    local def; def="$(_default_template_name)"
    [[ -d "$TEMPLATES_DIR/$def" ]] && echo "$def"
    while IFS= read -r -d '' d; do
        local n; n="$(basename "$d")"
        [[ "$n" != "$def" ]] && echo "$n"
    done < <(find "$TEMPLATES_DIR" -mindepth 1 -maxdepth 1 -type d \
                ! -name 'global' -print0 | sort -z)
}

prompt_template_select() {
    local def; def="$(_default_template_name)"
    local templates=()
    readarray -t templates < <(list_templates)
    if (( ${#templates[@]} == 1 )); then
        echo "${templates[0]}"; return
    fi
    printf '\nAvailable templates:\n'
    local i
    for (( i=0; i<${#templates[@]}; i++ )); do
        printf '  %d) %s\n' "$((i+1))" "${templates[$i]}"
    done
    local def_idx=1
    for (( i=0; i<${#templates[@]}; i++ )); do
        [[ "${templates[$i]}" == "$def" ]] && def_idx=$((i+1)) && break
    done
    local choice
    while true; do
        printf '\nSelect template [%d - %s]: ' "$def_idx" "${templates[$((def_idx-1))]}"
        IFS= read -r choice
        choice="${choice:-$def_idx}"
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#templates[@]} )); then
            echo "${templates[$((choice-1))]}"; return
        fi
        printf 'Invalid. Enter 1-%d.\n' "${#templates[@]}"
    done
}

install_project_tree() {
    local tree="$TEMPLATE_DIR/project"
    [[ -d "$tree" ]] || { err "Template project tree not found: $tree"; return 1; }
    while IFS= read -r -d '' src; do
        local rel="${src#$tree/}"
        local rel_dst="${rel//\{\{PROJECT_NAME\}\}/$PROJECT_NAME}"
        rel_dst="${rel_dst//\{\{MODULE_NAME\}\}/$MODULE_NAME}"
        if [[ "$(basename "$src")" == ".gitkeep" ]]; then
            mkdir -p "$PROJECT_DIR/$(dirname "$rel_dst")"
            continue
        fi
        local dst="$PROJECT_DIR/$rel_dst"
        if [[ -f "$dst" ]]; then log "  exists — $rel_dst"; continue; fi
        mkdir -p "$(dirname "$dst")"
        sed -e "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" \
            -e "s/{{MODULE_NAME}}/$MODULE_NAME/g" \
            "$src" > "$dst"
        [[ "$src" == *.sh ]] && chmod +x "$dst"
        CREATED_FILES+=("$rel_dst")
        log "  created — $rel_dst"
    done < <(find "$tree" -type f -print0 | sort -z)
}

install_claude_tree() {
    local tree="$TEMPLATE_DIR/claude"
    [[ -d "$tree" ]] || { err "Template claude tree not found: $tree"; return 1; }
    mkdir -p "$PROJECT_DIR/.claude"
    while IFS= read -r -d '' src; do
        local rel="${src#$tree/}"
        if [[ "$(basename "$src")" == ".gitkeep" ]]; then
            mkdir -p "$PROJECT_DIR/.claude/$(dirname "$rel")"
            continue
        fi
        local dst="$PROJECT_DIR/.claude/$rel"
        if [[ -f "$dst" ]]; then log "  exists — .claude/$rel"; continue; fi
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        [[ "$src" == *.sh ]] && chmod +x "$dst"
        CREATED_FILES+=(".claude/$rel")
        log "  installed — .claude/$rel"
    done < <(find "$tree" -type f -print0 | sort -z)
}

install_git_hooks() {
    local tree="$TEMPLATE_DIR/git-hooks"
    [[ -d "$tree" ]] || return 0
    while IFS= read -r -d '' src; do
        local name; name="$(basename "$src")"
        [[ "$name" == ".gitkeep" ]] && continue
        local dst="$PROJECT_DIR/.git/hooks/$name"
        if [[ -f "$dst" ]]; then log "  exists — .git/hooks/$name"; continue; fi
        cp "$src" "$dst"
        chmod +x "$dst"
        CREATED_FILES+=(".git/hooks/$name")
        log "  git-hook: $name"
    done < <(find "$tree" -maxdepth 1 -type f -print0 | sort -z)
}

# ─── Phase 4: Root files ──────────────────────────────────────────────────────
phase4_root_files() {
    log "=== Phase 4: Root files ==="
    # Handled by install_project_tree() in phase 6
    :
}

# ─── Phase 5: Claude Code config ──────────────────────────────────────────────
phase5_claude_config() {
    log "=== Phase 5: Claude Code config ==="

    install_claude_tree

    # Disable branch protection by default (single-developer workflow)
    if [[ ! -f "$PROJECT_DIR/.claude/protected-branches" ]]; then
        touch "$PROJECT_DIR/.claude/protected-branches"
        CREATED_FILES+=(.claude/protected-branches)
        log "  created .claude/protected-branches (branch protection disabled)"
    fi

    # settings.json is generated dynamically (not a template file)
    if [[ ! -f "$PROJECT_DIR/.claude/settings.json" ]]; then
        generate_settings_json > "$PROJECT_DIR/.claude/settings.json"
        CREATED_FILES+=(.claude/settings.json)
        log "  generated settings.json"
    else
        log "  settings.json exists — skipping"
    fi
}

generate_settings_json() {
    cat <<'EOF'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": [
      "Bash(git add *)",
      "Bash(git commit *)",
      "Bash(git push *)",
      "Bash(git push)",
      "Bash(git status)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(git branch *)",
      "Bash(git stash *)",
      "Bash(git fetch *)",
      "Bash(git checkout *)",
      "Bash(git switch *)",
      "Bash(git remote *)",
      "Bash(git init *)",
      "Bash(git mv *)",
      "Bash(chmod +x *)",
      "Bash(python3 *)",
      "Bash(python *)",
      "Bash(find *)",
      "Bash(grep *)",
      "Bash(ls *)",
      "Bash(mkdir *)",
      "Bash(touch *)",
      "Bash(.claude/hooks/*.sh)"
    ],
    "deny": [
      "Read(**/.env)",
      "Read(**/.env.*)",
      "Read(**/secrets/**)",
      "Read(**/*.pem)",
      "Read(**/*.key)",
      "Edit(**/.env)",
      "Edit(**/.env.*)",
      "Edit(**/secrets/**)",
      "Edit(**/*.pem)",
      "Edit(**/*.key)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/protect-files.sh",        "timeout": 10, "statusMessage": "Checking file protections..."},
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/warn-large-files.sh",     "timeout": 10, "statusMessage": "Checking for build artifacts..."},
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/scan-secrets.sh",         "timeout": 10, "statusMessage": "Scanning for secrets..."}
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/block-dangerous-commands.sh", "timeout": 10, "statusMessage": "Checking command safety..."}
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/auto-test.sh",            "timeout": 30, "statusMessage": "Running tests..."},
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/format-on-save.sh",       "timeout": 10, "statusMessage": "Formatting..."}
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/session-start.sh",        "timeout": 10, "statusMessage": "Loading project context..."}
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/notify.sh",               "timeout": 10}
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/save-response.sh",        "timeout": 30, "statusMessage": "Saving response..."},
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/auto-commit.sh",          "timeout": 30, "statusMessage": "Auto-committing changes..."}
        ]
      }
    ]
  }
}
EOF
}

# ─── Phase 6: Project structure ───────────────────────────────────────────────
phase6_structure() {
    log "=== Phase 6: Project structure ==="

    install_project_tree

    # src/<module>/ requires dynamic MODULE_NAME; create Python package after walker
    if [[ ! -d "$PROJECT_DIR/src/$MODULE_NAME" ]]; then
        mkdir -p "$PROJECT_DIR/src/$MODULE_NAME"
        touch "$PROJECT_DIR/src/$MODULE_NAME/__init__.py"
        CREATED_FILES+=("src/$MODULE_NAME/__init__.py")
        log "  created src/$MODULE_NAME/"
    else
        log "  src/$MODULE_NAME/ exists — skipping"
    fi

    log "  responses/ ready (private, git-ignored)"
}

# ─── Phase 7: Global setup (idempotent) ───────────────────────────────────────
phase7_global() {
    if [[ "$TEST_MODE" == true || "$CONFIGURE_GLOBAL" != true ]]; then
        log "Global setup skipped."
        return 0
    fi
    local global_root="${1:-$HOME}"
    local global_hook="$global_root/.claude/hooks/auto-import-skill.sh"
    local settings="$global_root/.claude/settings.json" bashrc="$global_root/.bashrc" content
    if [[ -f "$settings" ]]; then
        jq empty "$settings"
        if ! jq -e '.hooks.PostToolUse[]? | select(.matcher == "Skill") | .hooks[]? | select(.command | contains("auto-import-skill"))' "$settings" >/dev/null; then
            content="$(jq '.hooks.PostToolUse += [{"matcher":"Skill","hooks":[{"type":"command","command":"~/.claude/hooks/auto-import-skill.sh","timeout":15,"statusMessage":"Checking skill locality..."}]}]' "$settings")"
            replace_config "$settings" "$content"$'\n'
        fi
    fi
    if [[ ! -e "$global_hook" ]]; then
        mkdir -p -- "$(dirname "$global_hook")"
        cp "$TEMPLATE_DIR/claude/hooks/auto-import-skill.sh" "$global_hook"
        chmod u+x "$global_hook"
    fi
    content=""
    [[ ! -f "$bashrc" ]] || content="$(cat "$bashrc")"
    local changed=false
    if ! grep -q "CLAUDE_PROTECTED_BRANCHES" "$bashrc" 2>/dev/null; then
        content+=$'\nexport CLAUDE_PROTECTED_BRANCHES=""\n'
        changed=true
    fi
    local auto_venv legacy_venv
    auto_venv="$(cat <<'BASHRC'
# auto-venv cd override
cd() {
    builtin cd "$@" || return
    if [[ -n "${MKPROJ_AUTO_VENV:-}" && "${VIRTUAL_ENV:-}" == "$MKPROJ_AUTO_VENV" ]]; then
        deactivate
        unset MKPROJ_AUTO_VENV
    fi
    if [[ -f .venv/bin/activate && -z "${VIRTUAL_ENV:-}" ]]; then
        source .venv/bin/activate || return
        MKPROJ_AUTO_VENV="$VIRTUAL_ENV"
    fi
}
BASHRC
)"
    legacy_venv="$(cat <<'BASHRC'
# auto-venv cd override
cd() {
    builtin cd "$@"
    if [[ -f ".venv/bin/activate" && -z "${VIRTUAL_ENV:-}" ]]; then
        source .venv/bin/activate
    fi
}
BASHRC
)"
    if [[ "$content" == *"$legacy_venv"* ]]; then
        content="${content/"$legacy_venv"/"$auto_venv"}"
        changed=true
    elif ! grep -q "auto-venv cd override" "$bashrc" 2>/dev/null; then
        content+=$'\n'"$auto_venv"
        changed=true
    elif [[ "$content" != *MKPROJ_AUTO_VENV* ]]; then
        warn "Custom auto-venv function retained; review its environment switching manually."
    fi
    if [[ "$changed" == true ]]; then replace_config "$bashrc" "$content"$'\n'; fi

    if [[ "$INSTALL_KEYBINDINGS" == true ]]; then
        local kb_src="$TEMPLATES_DIR/global/keybindings.json"
        local kb_dst="$global_root/.claude/keybindings.json"
        local kb_hash_file="$global_root/.claude/keybindings.json.last-installed-hash"
        local template_hash
        template_hash="$(sha256sum "$kb_src" | cut -d' ' -f1)"
        if [[ ! -e "$kb_dst" ]]; then
            mkdir -p -- "$(dirname "$kb_dst")"
            cp -- "$kb_src" "$kb_dst"
            printf '%s\n' "$template_hash" > "$kb_hash_file"
            log "  keybindings: installed"
        else
            local installed_hash=""
            [[ -f "$kb_hash_file" ]] && installed_hash="$(< "$kb_hash_file")"
            if [[ -z "$installed_hash" ]]; then
                printf '%s\n' "$template_hash" > "$kb_hash_file"
                log "  keybindings: present (no install record; recorded current template hash)"
            elif [[ "$template_hash" != "$installed_hash" ]]; then
                backup_config "$kb_dst" || return
                cp -- "$kb_src" "$kb_dst"
                printf '%s\n' "$template_hash" > "$kb_hash_file"
                log "  keybindings: updated (template changed)"
            else
                log "  keybindings: up to date"
            fi
        fi
    fi
}

write_registry_initial() {
    local components='["core","venv","docs","tasks","hooks","rules","settings"]'
    registry_create "$PROJECT_DIR" "$MKPROJ_VERSION" "$components"
    local tpl_file rel tpl_hash disk_hash tier
    while IFS= read -r -d '' tpl_file; do
        rel="$(template_to_project_path "$tpl_file")"
        [[ -n "$rel" ]] || continue
        [[ -f "$PROJECT_DIR/$rel" ]] || continue
        tpl_hash="$(sha256sum "$tpl_file" | cut -d' ' -f1)"
        disk_hash="$(sha256sum "$PROJECT_DIR/$rel" | cut -d' ' -f1)"
        tier="$(file_tier "$rel")"
        registry_set_file "$PROJECT_DIR" "$rel" "$tpl_hash" "$disk_hash" "installed" "$tier"
    done < <(find "$TEMPLATE_DIR/project" "$TEMPLATE_DIR/claude" -type f \( \
        ! -name ".gitkeep" \
        \) -print0)
    if [[ -f "$PROJECT_DIR/.claude/settings.json" ]]; then
        local gen_hash
        gen_hash="$(generate_settings_json | sha256sum | cut -d' ' -f1)"
        disk_hash="$(sha256sum "$PROJECT_DIR/.claude/settings.json" | cut -d' ' -f1)"
        tier="$(file_tier ".claude/settings.json")"
        registry_set_file "$PROJECT_DIR" ".claude/settings.json" "$gen_hash" "$disk_hash" "installed" "$tier"
    fi
    log "  wrote .mkproj"
}

# ─── Phase 8: Initial commit ──────────────────────────────────────────────────
phase8_commit() {
    local message="Initial project scaffold"
    git -C "$PROJECT_DIR" diff --cached --quiet || {
        err "Index contains staged user changes; nothing was automatically added."; return 1;
    }
    if (( ${#CREATED_FILES[@]} )); then
        git -C "$PROJECT_DIR" add -- "${CREATED_FILES[@]}"
        if ! git -C "$PROJECT_DIR" diff --cached --quiet; then
            if git -C "$PROJECT_DIR" rev-parse HEAD >/dev/null 2>&1; then message="Complete project scaffold"; fi
            git -C "$PROJECT_DIR" commit -m "$message"
        fi
    fi
    write_registry_initial
    if [[ "$TEST_MODE" == true ]]; then
        log "Test mode: remote push skipped."
    elif git -C "$PROJECT_DIR" remote get-url origin >/dev/null 2>&1; then
        git -C "$PROJECT_DIR" push -u origin main
    fi
}

# ─── Phase 9: Verify ──────────────────────────────────────────────────────────
phase9_verify() {
    log "=== Phase 9: Verify ==="

    local file
    for file in CLAUDE.md AGENTS.md .gitignore .gitattributes .claude/settings.json; do
        [[ -f "$PROJECT_DIR/$file" ]] || { err "Required file missing: $file"; return 1; }
    done
    jq empty "$PROJECT_DIR/.claude/settings.json"
    verify_privacy_rules
    [[ -x "$PROJECT_DIR/.venv/bin/python" ]] || { err "Project venv is not executable."; return 1; }
    "$PROJECT_DIR/.venv/bin/python" -c 'import pathlib,sys; sys.exit(pathlib.Path(sys.prefix).resolve()!=pathlib.Path(sys.argv[1]).resolve())' "$PROJECT_DIR/.venv"
    if [[ "$TEST_MODE" != true ]]; then
        PIP_DISABLE_PIP_VERSION_CHECK=1 "$PROJECT_DIR/.venv/bin/python" -m pip install -r "$PROJECT_DIR/requirements.txt" -q
    fi
    if [[ ! -e "$PROJECT_DIR/.env" ]]; then cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"; fi
    log "Project verified."
}

launch_agent() {
    if [[ "$LAUNCH_AGENT" == none || "$TEST_MODE" == true ]]; then return 0; fi
    if [[ "$LAUNCH_AGENT" == codex ]]; then
        cd -- "$PROJECT_DIR"
        exec codex
    fi
    # ── Claude Code launch options ────────────────────────────────────────────
    echo ""
    log "Configure Claude Code launch:"
    echo ""

    # Bypass permission prompts?
    local bypass_ans
    read_choice bypass_ans "  Bypass permission prompts? [Y/n]: " y yYnN
    local bypass=false
    [[ "${bypass_ans,,}" != "n" ]] && bypass=true

    # Model selection
    echo ""
    log "  Model:"
    log "    1) haiku        — fast, lightweight tasks"
    log "    2) sonnet       — standard daily coding  [default]"
    log "    3) sonnet[1m]   — sonnet with 1M context window"
    log "    4) opus         — complex architectural tasks"
    log "    5) opusplan     — opus for planning, sonnet for execution"
    log "    6) fable        — deep reasoning, long autonomous sessions"
    log "    7) fable[1m]    — fable with 1M context window"
    log "    8) best         — latest fable or opus (plan-dependent)"
    echo ""
    local model_choice
    read_choice model_choice "  Choose model [1-8, default 2]: " 2 12345678
    local model_val
    case "${model_choice:-2}" in
        1) model_val="haiku" ;;
        2) model_val="sonnet" ;;
        3) model_val="sonnet[1m]" ;;
        4) model_val="opus" ;;
        5) model_val="opusplan" ;;
        6) model_val="fable" ;;
        7) model_val="fable[1m]" ;;
        8) model_val="best" ;;
        *) err "Invalid validated model choice."; return 1 ;;
    esac

    # Effort selection
    echo ""
    log "  Effort:"
    log "    1) low"
    log "    2) medium   [default]"
    log "    3) high"
    log "    4) max"
    echo ""
    local effort_choice
    read_choice effort_choice "  Choose effort [1-4, default 2]: " 2 1234
    local effort_val
    case "${effort_choice:-2}" in
        1) effort_val="low" ;;
        2) effort_val="medium" ;;
        3) effort_val="high" ;;
        4) effort_val="max" ;;
        *) err "Invalid validated effort choice."; return 1 ;;
    esac

    # Build command array (array avoids glob expansion on brackets in model names)
    local cmd_args=("claude")
    [[ "$bypass" == "true" ]] && cmd_args+=("--dangerously-skip-permissions")
    cmd_args+=("--model" "$model_val")
    cmd_args+=("--effort" "$effort_val")

    echo ""
    log "Launching: ${cmd_args[*]}"
    echo ""

    cd "$PROJECT_DIR"
    exec "${cmd_args[@]}"
}

# ─── Test validation ──────────────────────────────────────────────────────────
phase9_test_validate() {
    echo ""
    log "=== Test validation ==="
    local pass=true

    check() {
        local label="$1" path="$2" kind="${3:-f}"
        if [[ "$kind" == "f" && -f "$path" ]]; then
            log "  PASS  $label"
        elif [[ "$kind" == "d" && -d "$path" ]]; then
            log "  PASS  $label"
        elif [[ "$kind" == "x" && -x "$path" ]]; then
            log "  PASS  $label"
        else
            err "  FAIL  $label  ($path)"
            pass=false
        fi
    }

    # Root files
    check ".gitignore"          "$PROJECT_DIR/.gitignore"
    check ".gitattributes"      "$PROJECT_DIR/.gitattributes"
    check "CLAUDE.md"           "$PROJECT_DIR/CLAUDE.md"
    check "AGENTS.md"           "$PROJECT_DIR/AGENTS.md"
    check "README.md"           "$PROJECT_DIR/README.md"
    check "requirements.txt"    "$PROJECT_DIR/requirements.txt"
    check "run.sh"              "$PROJECT_DIR/run.sh"
    check "test.sh"             "$PROJECT_DIR/test.sh"
    check ".env.example"        "$PROJECT_DIR/.env.example"

    # Directories
    check "src/${PROJECT_NAME//-/_}/"   "$PROJECT_DIR/src/${PROJECT_NAME//-/_}"  d
    check "tests/"              "$PROJECT_DIR/tests"             d
    check "docs/"               "$PROJECT_DIR/docs"              d
    check "tasks/"              "$PROJECT_DIR/tasks"             d
    check "responses/"          "$PROJECT_DIR/responses"         d
    check ".venv/"              "$PROJECT_DIR/.venv"             d

    # Claude config
    check "settings.json"       "$PROJECT_DIR/.claude/settings.json"
    check "hooks/ dir"          "$PROJECT_DIR/.claude/hooks"         d
    check "rules/ dir"          "$PROJECT_DIR/.claude/rules"         d

    # Hooks executable
    for hook in "$PROJECT_DIR/.claude/hooks/"*.sh; do
        [[ -e "$hook" ]] || continue
        check "hook +x $(basename "$hook")" "$hook" x
    done

    # settings.json valid JSON
    if jq empty "$PROJECT_DIR/.claude/settings.json" 2>/dev/null; then
        log "  PASS  settings.json valid JSON"
    else
        err "  FAIL  settings.json invalid JSON"
        pass=false
    fi

    # tasks stubs
    check "tasks/todo.md"           "$PROJECT_DIR/tasks/todo.md"
    check "tasks/skills-manifest.md" "$PROJECT_DIR/tasks/skills-manifest.md"

    # Local repo has scaffold commit
    if git -C "$PROJECT_DIR" log --oneline 2>/dev/null | grep -q "Initial project scaffold"; then
        log "  PASS  local repo scaffold commit"
    else
        err "  FAIL  local repo missing scaffold commit"
        pass=false
    fi

    if ! bash "$BOOTSTRAP_DIR/tests/test-input.sh"; then
        pass=false
    fi

    # Name validation
    test_name() {
        local name="$1" expect="$2"
        if ( validate_name "$name" 2>/dev/null ); then
            local result="valid"
        else
            local result="invalid"
        fi
        if [[ "$result" == "$expect" ]]; then
            log "  PASS  name '$name' -> $result"
        else
            err "  FAIL  name '$name' expected $expect, got $result"
            pass=false
        fi
    }
    test_name "my_tool"      valid
    test_name "agent2024"    valid
    test_name "a"            valid
    test_name "abc_123"      valid
    test_name "my-tool"          valid
    test_name "claude-skill-go"  valid
    test_name "tool-"            invalid
    test_name "my--tool"         invalid
    test_name "MyTool"           invalid
    test_name "UPPER"            invalid
    test_name "2bad"             invalid
    test_name "_bad"             invalid
    test_name "bad name"         invalid
    test_name "bad@name"         invalid
    test_name "bad.name"         invalid

    # .mkproj registry tests
    if [[ -f "$PROJECT_DIR/.mkproj" ]]; then
        log "  PASS  .mkproj created"
    else
        err "  FAIL  .mkproj missing"
        pass=false
    fi
    if jq empty "$PROJECT_DIR/.mkproj" 2>/dev/null; then
        log "  PASS  .mkproj valid JSON"
    else
        err "  FAIL  .mkproj invalid JSON"
        pass=false
    fi
    local mkproj_ver; mkproj_ver="$(jq -r '.mkproj_version' "$PROJECT_DIR/.mkproj" 2>/dev/null)"
    if [[ "$mkproj_ver" == "$MKPROJ_VERSION" ]]; then
        log "  PASS  .mkproj version $mkproj_ver"
    else
        err "  FAIL  .mkproj version mismatch: got '$mkproj_ver', expected '$MKPROJ_VERSION'"
        pass=false
    fi
    local claude_md_status; claude_md_status="$(jq -r '.files["CLAUDE.md"].status // "missing"' "$PROJECT_DIR/.mkproj" 2>/dev/null)"
    if [[ "$claude_md_status" == "installed" ]]; then
        log "  PASS  .mkproj tracks CLAUDE.md"
    else
        err "  FAIL  .mkproj CLAUDE.md status: '$claude_md_status'"
        pass=false
    fi
    if grep -qxF ".mkproj" "$PROJECT_DIR/.gitignore"; then
        log "  PASS  .mkproj in .gitignore"
    else
        err "  FAIL  .mkproj missing from .gitignore"
        pass=false
    fi

    # --version test
    local ver_out; ver_out="$(mkproj --version 2>&1)"
    if [[ "$ver_out" == "mkproj $MKPROJ_VERSION" ]]; then
        log "  PASS  --version output: $ver_out"
    else
        err "  FAIL  --version: expected 'mkproj $MKPROJ_VERSION', got '$ver_out'"
        pass=false
    fi

    echo ""
    if [[ "$pass" == "true" ]]; then
        log "All checks passed. Bootstrap is working correctly."
    else
        err "One or more checks failed — see above."
    fi

    echo ""
    log "Cleaning up test artifacts..."
    log "Temporary artifacts will be removed by the test cleanup trap."
    [[ "$pass" == "true" ]]
}

run_update_mode() {
    local target="$PROJECT_DIR"
    [[ -d "$target" ]] || { err "Not a directory: $target"; return 1; }
    registry_exists "$target" || _is_claude_project "$target" || {
        err "Not a mkproj or Claude Code project: $target"; return 1
    }
    log "Updating: $target"

    if [[ -n "$FORCE_FILE" ]]; then
        log "  force-updating: $FORCE_FILE"
        apply_template_file "$target" "$FORCE_FILE"
        return $?
    fi

    update_project "$target"
}

run_safe_update_mode() {
    local target="$SCAN_DIR"
    [[ -d "$target" ]] || { err "Not a directory: $target"; return 1; }
    registry_exists "$target" || _is_claude_project "$target" || {
        err "Not a mkproj or Claude Code project: $target"; return 1
    }
    log "Safe-update: $target"
    SAFE_MODE=true update_project "$target"
}

run_check_mode() {
    local target="$SCAN_DIR"
    [[ -d "$target" ]] || { err "Not a directory: $target"; return 1; }
    registry_exists "$target" || {
        err "Not a mkproj project: $target"; return 1
    }
    log "Checking: $target"
    CHECK_MODE=true check_project "$target"
}

run_report_mode() {
    local target="$SCAN_DIR"
    [[ -d "$target" ]] || { err "Not a directory: $target"; return 1; }
    registry_exists "$target" || {
        err "Not a mkproj project: $target"; return 1
    }
    log "Generating report for: $target"
    local report_path
    report_path="$(generate_report "$target")"
    log "Report written: $report_path"
}

run_accept_mode() {
    local target="$PROJECT_DIR"
    [[ -d "$target" ]] || { err "Not a directory: $target"; return 1; }
    registry_exists "$target" || {
        err "Not a mkproj project: $target"; return 1
    }
    [[ -n "$ACCEPT_FILE" ]] || { err "--accept requires --file REL_PATH."; return 1; }
    local disk_path="$target/$ACCEPT_FILE"
    [[ -f "$disk_path" ]] || { err "File does not exist: $disk_path"; return 1; }
    local tier; tier="$(file_tier "$ACCEPT_FILE")"
    registry_set_file "$target" "$ACCEPT_FILE" \
        "$(current_template_hash "$ACCEPT_FILE")" \
        "$(sha256sum "$disk_path" | cut -d' ' -f1)" "installed" "$tier"
    log "Accepted: $ACCEPT_FILE (your version is now the baseline)"
}

run_restore_infra_mode() {
    local target="$SCAN_DIR"
    [[ -d "$target" ]] || { err "Not a directory: $target"; return 1; }
    registry_exists "$target" || {
        err "Not a mkproj project: $target"; return 1
    }
    restore_infra "$target"
}

run_list_tiers_mode() {
    local target="$SCAN_DIR"
    [[ -d "$target" ]] || { err "Not a directory: $target"; return 1; }
    registry_exists "$target" || {
        err "Not a mkproj project: $target"; return 1
    }
    list_tiers "$target"
}

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

run_status_mode() {
    local managed=() unmanaged=()
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
        changes=0
        while IFS= read -r -d '' f; do
            local rel; rel="$(template_to_project_path "$f")"
            [[ -n "$rel" ]] || continue
            local dec; dec="$(file_update_decision "$d" "$rel")"
            [[ "$dec" == "auto_update" || "$dec" == "conflict" ]] && (( changes++ )) || true
        done < <(find "$TEMPLATES_DIR" -type f \( ! -path "*/backups/*" ! -name "*.bak" ! -name ".mkproj-manifest.json" \) -print0)
        (( changes > 0 )) && exit_code=2 || true
        local status_str
        if (( changes == 0 )); then
            status_str="up to date"
        else
            status_str="$changes files pending"
        fi
        printf '  %-30s  installed %-8s  current %-8s  %s\n' \
            "$(basename "$d")" "$inst_ver" "$MKPROJ_VERSION" "$status_str"
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
                d) : ;;
                s) return 0 ;;
            esac
        done < <(registry_all_files "$d")
    done

    [[ "$found" == true ]] || log "No pending decisions found under $SCAN_DIR."
}

run_adopt_mode() {
    local target="$PROJECT_DIR"
    [[ -d "$target" ]] || { err "Not a directory: $target"; return 1; }
    if registry_exists "$target"; then
        log "Already managed: $target"
        return 0
    fi
    _is_claude_project "$target" || {
        err "No .claude/ or CLAUDE.md found in: $target"; return 1
    }
    adopt_project "$target"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    CURRENT_PHASE=preflight
    phase1_preflight
    local lock_dir lock_key
    if [[ "$TEST_MODE" == true ]]; then lock_dir="$TEST_ROOT/locks"; else lock_dir="/tmp/mkproj-locks-$UID"; fi
    [[ ! -L "$lock_dir" ]] || { err "Refusing symlinked lock directory."; return 1; }
    (umask 077; mkdir -p -- "$lock_dir")
    [[ -O "$lock_dir" ]] || { err "Lock directory belongs to another user."; return 1; }
    chmod 700 "$lock_dir"
    lock_key="$(printf '%s' "$PROJECT_DIR" | sha256sum | cut -d' ' -f1)"
    exec {LOCK_FD}>"$lock_dir/$lock_key"
    flock -n "$LOCK_FD" || { err "Another mkproj instance owns this project."; return 1; }
    if [[ "$SETUP_LOCAL_REPO" == true ]]; then
        lock_key="$(printf '%s' "bare:$BARE_REPO" | sha256sum | cut -d' ' -f1)"
        exec {BARE_LOCK_FD}>"$lock_dir/$lock_key"
        flock -n "$BARE_LOCK_FD" || { err "Another mkproj instance owns the bare destination."; return 1; }
    fi
    case "$MODE" in
        update)        run_update_mode;        exit $? ;;
        safe-update)   run_safe_update_mode;   exit $? ;;
        check)         run_check_mode;         exit $? ;;
        report)        run_report_mode;        exit $? ;;
        accept)        run_accept_mode;        exit $? ;;
        restore-infra) run_restore_infra_mode; exit $? ;;
        list-tiers)    run_list_tiers_mode;    exit $? ;;
        scan)          run_scan_mode;          exit $? ;;
        status)        run_status_mode;        exit $? ;;
        pending)       run_pending_mode;       exit $? ;;
        adopt)         run_adopt_mode;         exit $? ;;
    esac
    check_project_repo
    check_repo_destination
    mkdir -p -- "$PROJECT_DIR"
    CURRENT_PHASE=git; phase2_git
    CURRENT_PHASE=python; phase3_python
    CURRENT_PHASE=files; phase4_root_files
    CURRENT_PHASE=claude; phase5_claude_config
    CURRENT_PHASE=structure; phase6_structure
    CURRENT_PHASE=guards; configure_git_guards
    CURRENT_PHASE=verify; phase9_verify
    CURRENT_PHASE=global; phase7_global
    CURRENT_PHASE=commit; phase8_commit
    if [[ "$TEST_MODE" == true ]]; then
        phase9_test_validate
    else
        log "Bootstrap complete: $PROJECT_DIR"
        printf '\nTip: run /audit in Claude Code once you have a working draft.\n     See docs/skills.md in your new project for details.\n\n'
        flock -u "$LOCK_FD"
        if [[ -n "${BARE_LOCK_FD:-}" ]]; then flock -u "$BARE_LOCK_FD"; fi
        CURRENT_PHASE=launch
        launch_agent
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -E
    trap 'status=$?; err "mkproj failed in phase $CURRENT_PHASE (line $LINENO, exit $status). Existing project data and backups are retained."; exit "$status"' ERR
    initialize "$@"
    case "$MODE" in
        help)            usage ;;
        version)         printf 'mkproj %s\n' "$MKPROJ_VERSION" ;;
        list-templates)  list_templates ;;
        doctor)          doctor ;;
        dry-run)         dry_run ;;
        *)               main ;;
    esac
fi
