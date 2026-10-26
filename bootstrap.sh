#!/usr/bin/env bash
# bootstrap.sh — project-bootstrap
# Usage: cd ~/Projects && mkproj <name>
set -euo pipefail

BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$BOOTSTRAP_DIR/templates"
TEST_MODE=false
SETUP_LOCAL_REPO=false
BARE_REPO=""

# ─── Colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { printf "${GREEN}[bootstrap]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[bootstrap]${NC} %s\n" "$*"; }
err()  { printf "${RED}[bootstrap]${NC} %s\n" "$*" >&2; }

source "$BOOTSTRAP_DIR/lib/input.sh"
source "$BOOTSTRAP_DIR/lib/runtime.sh"
CREATED_FILES=()
TEST_ROOT=""
TEST_PARENT=""
CURRENT_PHASE=initialize
usage() {
    cat <<'EOF'
mkproj: Linux Python projects with shared Claude Code / Codex directives

Usage:
  mkproj [--no-global] [--agent=claude|codex|none] [name]
  mkproj --dry-run [--no-global] [--agent=claude|codex|none] [name]
  mkproj --doctor [name]       read-only environment and privacy diagnostics
  mkproj --test                isolated scaffold + negative tests; no global edits/pushes
  mkproj --help

Names: 1-64 ASCII characters, starting a-z, followed by a-z, 0-9, underscore.
Python keywords are refused. Full project paths are limited to 2048 bytes.
Prompt answers are one character; invalid answers reprompt and EOF aborts.
Existing repositories, remotes, user files, and configuration are preserved.
Bare destination collisions abort; no overwrite or destructive collision option exists.
Global shell/hook changes are opt-in and receive verified timestamped backups.
New projects get CLAUDE.md plus an AGENTS.md pointer and native private-path guards.
A project venv is verified before dependency installation and commits.
Status settings are never configured by mkproj.
EOF
}
cleanup_test() {
    [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" && ! -L "$TEST_ROOT" &&
       "$TEST_ROOT" == "$TEST_PARENT"/mkproj-test.* ]] || return 0
    rm -rf -- "$TEST_ROOT"
}
initialize() {
    parse_args "$@"
    CONFIGURE_GLOBAL=false
    if [[ "$MODE" == help ]]; then return 0; fi
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
        PROJECT_NAME="$PROJECT_ARG"
        PROJECT_DIR="$PWD/$PROJECT_NAME"
    else
        PROJECT_DIR="$PWD"
        PROJECT_NAME="$(basename "$PROJECT_DIR")"
        if [[ "$MODE" != doctor ]]; then validate_name "$PROJECT_NAME"; fi
    fi
    validate_project_path "$PROJECT_DIR"
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
    log "  Claude  : settings.json + $(ls "$TEMPLATES_DIR/hooks"/*.sh 2>/dev/null | wc -l | tr -d ' ') hooks + 4 rules (all from templates/)"
    log "  Dirs    : src/$PROJECT_NAME/  tests/  docs/  tasks/  responses/"
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
        cp "$TEMPLATES_DIR/requirements.txt" "$PROJECT_DIR/requirements.txt"
        CREATED_FILES+=(requirements.txt)
        log "  Created requirements.txt"
    else
        log "  requirements.txt exists — skipping"
    fi
}

# ─── Phase 4: Root files ──────────────────────────────────────────────────────
copy_template() {
    local src="$TEMPLATES_DIR/$1" dst="$PROJECT_DIR/$2"
    if [[ -f "$dst" ]]; then
        log "  exists — $2"
        return
    fi
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    CREATED_FILES+=("$2")
    log "  created — $2"
}

phase4_root_files() {
    log "=== Phase 4: Root files ==="

    copy_template ".gitignore"     ".gitignore"
    copy_template ".gitattributes" ".gitattributes"
    copy_template ".env.example"   ".env.example"

    for f in CLAUDE.md AGENTS.md README.md; do
        local dst="$PROJECT_DIR/$f"
        if [[ ! -f "$dst" ]]; then
            sed "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" "$TEMPLATES_DIR/$f" > "$dst"
            CREATED_FILES+=("$f")
            log "  created — $f"
        else
            log "  exists — $f"
        fi
    done
}

# ─── Phase 5: Claude Code config ──────────────────────────────────────────────
phase5_claude_config() {
    log "=== Phase 5: Claude Code config ==="

    mkdir -p "$PROJECT_DIR/.claude/hooks"
    mkdir -p "$PROJECT_DIR/.claude/rules"
    mkdir -p "$PROJECT_DIR/.claude/skills"

    # Disable branch protection by default (single-developer workflow)
    if [[ ! -f "$PROJECT_DIR/.claude/protected-branches" ]]; then
        touch "$PROJECT_DIR/.claude/protected-branches"
        CREATED_FILES+=(.claude/protected-branches)
        log "  created .claude/protected-branches (branch protection disabled)"
    fi

    # All hooks bundled in templates/hooks/
    local hook_count=0
    while IFS= read -r -d '' hook; do
        local name; name="$(basename "$hook")"
        local dst="$PROJECT_DIR/.claude/hooks/$name"
        if [[ ! -f "$dst" ]]; then
            cp "$hook" "$dst"
            chmod +x "$dst"
            CREATED_FILES+=(".claude/hooks/$name")
            log "  hook: $name"
            ((hook_count++)) || true
        fi
    done < <(find "$TEMPLATES_DIR/hooks" -maxdepth 1 -name "*.sh" -print0 2>/dev/null)
    [[ $hook_count -eq 0 ]] && log "  all hooks already present — skipping"

    # 4 rules bundled in templates/rules/
    local rule_count=0
    while IFS= read -r -d '' rule; do
        local name; name="$(basename "$rule")"
        local dst="$PROJECT_DIR/.claude/rules/$name"
        if [[ ! -f "$dst" ]]; then
            cp "$rule" "$dst"
            CREATED_FILES+=(".claude/rules/$name")
            log "  rule: $name"
            ((rule_count++)) || true
        fi
    done < <(find "$TEMPLATES_DIR/rules" -maxdepth 1 -name "*.md" -print0 2>/dev/null)
    [[ $rule_count -eq 0 ]] && log "  all rules already present — skipping"

    # settings.json
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
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/save-response.sh",        "timeout": 15, "statusMessage": "Saving response..."},
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

    # src/<module>/ and tests/
    if [[ ! -d "$PROJECT_DIR/src/$PROJECT_NAME" ]]; then
        mkdir -p "$PROJECT_DIR/src/$PROJECT_NAME"
        touch "$PROJECT_DIR/src/$PROJECT_NAME/__init__.py"
        CREATED_FILES+=("src/$PROJECT_NAME/__init__.py")
        log "  created src/$PROJECT_NAME/"
    else
        log "  src/$PROJECT_NAME/ exists — skipping"
    fi
    if [[ ! -d "$PROJECT_DIR/tests" ]]; then
        mkdir -p "$PROJECT_DIR/tests"
        touch "$PROJECT_DIR/tests/.gitkeep"
        CREATED_FILES+=(tests/.gitkeep)
        log "  created tests/"
    else
        log "  tests/ exists — skipping"
    fi

    # Private exchanges and attachments stay entirely outside Git.
    mkdir -p "$PROJECT_DIR/responses"
    log "  responses/ ready (private, git-ignored)"

    copy_template "tasks/todo.md"            "tasks/todo.md"
    copy_template "tasks/skills-manifest.md" "tasks/skills-manifest.md"

    for doc in install running api-keys architecture customizing adding-agents privacy-and-security troubleshooting doc-index; do
        copy_template "docs/$doc.md" "docs/$doc.md"
    done

    for script in run.sh test.sh; do
        local dst="$PROJECT_DIR/$script"
        if [[ ! -f "$dst" ]]; then
            cp "$TEMPLATES_DIR/$script" "$dst"
            chmod +x "$dst"
            CREATED_FILES+=("$script")
            log "  created $script (executable)"
        else
            log "  exists — $script"
        fi
    done
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
        cp "$TEMPLATES_DIR/hooks/auto-import-skill.sh" "$global_hook"
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
    check "src/$PROJECT_NAME/"   "$PROJECT_DIR/src/$PROJECT_NAME"  d
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
    test_name "my-tool"      invalid
    test_name "MyTool"       invalid
    test_name "UPPER"        invalid
    test_name "2bad"         invalid
    test_name "_bad"         invalid
    test_name "bad name"     invalid
    test_name "bad@name"     invalid
    test_name "bad.name"     invalid

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
        help) usage ;;
        doctor) doctor ;;
        dry-run) dry_run ;;
        *) main ;;
    esac
fi
